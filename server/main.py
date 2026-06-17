"""
FastAPI Server - Pneumonia Detection Grad-CAM
=============================================
Run:
    cd server
    .\\venv\\Scripts\\uvicorn main:app --host 0.0.0.0 --port 8000 --reload

Requires the real Keras model (densenet_BEST_FINAL.keras) from Google Drive.
Place it at: model/densenet_BEST_FINAL.keras
"""

import io
import base64
import numpy as np
import tensorflow as tf
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from PIL import Image
import cv2

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
MODEL_PATH      = "../model/densenet_BEST_FINAL.keras"
INPUT_SIZE      = 224
# The last convolutional layer inside DenseNet121 - confirmed from training code
LAST_CONV_LAYER = "conv5_block16_concat"

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="Pneumonia Grad-CAM API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Global models (loaded once at startup)
# ---------------------------------------------------------------------------
model: tf.keras.Model      = None
grad_model: tf.keras.Model = None


class GradModel(tf.keras.Model):
    def __init__(self, sequential_model, last_conv_layer_name):
        super().__init__()
        self.densenet_base = sequential_model.layers[0]
        conv_layer = self.densenet_base.get_layer(last_conv_layer_name)
        self.densenet_submodel = tf.keras.Model(
            inputs=self.densenet_base.input,
            outputs=[conv_layer.output, self.densenet_base.output]
        )
        self.remaining_layers = sequential_model.layers[1:]

    def call(self, inputs):
        conv_outputs, base_outputs = self.densenet_submodel(inputs)
        x = base_outputs
        for layer in self.remaining_layers:
            x = layer(x)
        return conv_outputs, x


@app.on_event("startup")
def load_model():
    global model, grad_model

    print("Loading Keras model ...")
    model = tf.keras.models.load_model(MODEL_PATH)
    print("Model loaded.")

    try:
        grad_model = GradModel(model, LAST_CONV_LAYER)
        print("Grad-CAM sub-model ready.")
    except Exception as e:
        print(f"WARNING: Could not build Grad-CAM sub-model: {e}")
        grad_model = None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def preprocess(pil_image: Image.Image) -> np.ndarray:
    """Resize to 224x224, normalise to [0,1], add batch dimension."""
    img = pil_image.convert("RGB").resize((INPUT_SIZE, INPUT_SIZE))
    arr = np.array(img, dtype=np.float32) / 255.0
    return np.expand_dims(arr, axis=0)  # shape: (1, 224, 224, 3)


def compute_gradcam(img_array: np.ndarray) -> np.ndarray:
    """
    Compute Grad-CAM heatmap.

    Steps:
      1. Forward pass through grad_model inside GradientTape.
      2. Compute gradient of prediction score w.r.t. conv layer outputs.
      3. Pool gradients across spatial dims -> importance weight per channel.
      4. Weighted sum of feature maps -> raw heatmap (7 x 7).
      5. ReLU to keep only positive activations.
      6. Normalise to [0, 1].
      7. Resize to INPUT_SIZE x INPUT_SIZE.

    Returns float32 array of shape (224, 224) with values in [0, 1].
    """
    with tf.GradientTape() as tape:
        conv_outputs, predictions = grad_model(img_array)
        # Binary sigmoid: gradient w.r.t. the single output neuron
        class_channel = predictions[:, 0]

    grads        = tape.gradient(class_channel, conv_outputs)  # (1, 7, 7, 1024)
    pooled_grads = tf.reduce_mean(grads, axis=(0, 1, 2))       # (1024,)

    conv_map = conv_outputs[0]                                  # (7, 7, 1024)
    heatmap  = conv_map @ pooled_grads[..., tf.newaxis]        # (7, 7, 1)
    heatmap  = tf.squeeze(heatmap).numpy()                     # (7, 7)

    heatmap = np.maximum(heatmap, 0)
    if heatmap.max() > 0:
        heatmap = heatmap / heatmap.max()

    return cv2.resize(heatmap.astype(np.float32), (INPUT_SIZE, INPUT_SIZE))


def overlay_heatmap(pil_image: Image.Image, heatmap: np.ndarray) -> str:
    """
    Blend JET colormap heatmap over the original image.
    Returns a base64-encoded PNG string ready to send to Flutter.
    """
    heatmap_uint8   = (heatmap * 255).astype(np.uint8)
    heatmap_colored = cv2.applyColorMap(heatmap_uint8, cv2.COLORMAP_JET)
    heatmap_colored = cv2.cvtColor(heatmap_colored, cv2.COLOR_BGR2RGB)

    base    = np.array(pil_image.convert("RGB").resize((INPUT_SIZE, INPUT_SIZE)))
    overlay = cv2.addWeighted(base, 0.60, heatmap_colored, 0.40, 0)

    _, buf = cv2.imencode(".png", cv2.cvtColor(overlay, cv2.COLOR_RGB2BGR))
    return base64.b64encode(buf).decode("utf-8")


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.get("/")
def root():
    return {"status": "ok", "message": "Pneumonia Grad-CAM API is running"}


@app.get("/health")
def health():
    return {
        "model_loaded":  model is not None,
        "gradcam_ready": grad_model is not None,
    }


@app.post("/gradcam")
async def gradcam(file: UploadFile = File(...)):
    """
    Accepts a chest X-ray image and returns a Grad-CAM heatmap overlay.
    Response: { "gradcam_image": "<base64 PNG string>" }
    """
    if not file:
        raise HTTPException(status_code=400, detail="No file uploaded")

    if grad_model is None:
        raise HTTPException(status_code=503, detail="Grad-CAM model is not available")

    contents = await file.read()
    try:
        pil_image = Image.open(io.BytesIO(contents))
    except Exception:
        raise HTTPException(status_code=400, detail="Cannot decode image")

    img_array = preprocess(pil_image)

    try:
        heatmap        = compute_gradcam(img_array)
        gradcam_base64 = overlay_heatmap(pil_image, heatmap)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Grad-CAM failed: {str(e)}")

    return JSONResponse({"gradcam_image": gradcam_base64})
