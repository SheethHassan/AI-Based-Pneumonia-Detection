"""
=============================================================================
Pneumonia Detection — DenseNet121 Transfer Learning Pipeline
=============================================================================
Trains a DenseNet121-based model (transfer learning + fine-tuning) to
classify chest X-ray images as Normal or Pneumonia.
Exports .h5 and .tflite models ready for the Flutter app.

Dataset structure:
    dataset/
        train/  NORMAL/  PNEUMONIA/
        val/    NORMAL/  PNEUMONIA/
        test/   NORMAL/  PNEUMONIA/

Usage (Google Colab recommended):
    python train_model.py --data_dir ./dataset --epochs_phase1 10 --epochs_phase2 10

Author : PneumoScan AI Team
=============================================================================
"""

import os
import argparse
import numpy as np
import matplotlib
matplotlib.use("Agg")  # non-interactive backend
import matplotlib.pyplot as plt
import seaborn as sns

import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers, callbacks, applications
from sklearn.metrics import (
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    accuracy_score,
)

# ── Constants ────────────────────────────────────────────────────────────────
IMG_SIZE         = 224
BATCH_SIZE       = 32
CLASS_NAMES      = ["NORMAL", "PNEUMONIA"]
INPUT_SHAPE      = (IMG_SIZE, IMG_SIZE, 3)
DEFAULT_PHASE1   = 10   # Feature extraction epochs
DEFAULT_PHASE2   = 10   # Fine-tuning epochs
SEED             = 42
FINE_TUNE_AT     = 313  # Unfreeze DenseNet121 layers from this index onward


# ── Argument Parser ──────────────────────────────────────────────────────────
def parse_args():
    parser = argparse.ArgumentParser(
        description="Train DenseNet121 Pneumonia Classifier"
    )
    parser.add_argument("--data_dir",      type=str, default="./dataset")
    parser.add_argument("--epochs_phase1", type=int, default=DEFAULT_PHASE1,
                        help="Epochs for frozen-base feature extraction")
    parser.add_argument("--epochs_phase2", type=int, default=DEFAULT_PHASE2,
                        help="Epochs for fine-tuning unfrozen top layers")
    parser.add_argument("--batch_size",    type=int, default=BATCH_SIZE)
    parser.add_argument("--output_dir",    type=str, default="./output")
    return parser.parse_args()


# ══════════════════════════════════════════════════════════════════════════════
# 1. DATA LOADING & AUGMENTATION
# ══════════════════════════════════════════════════════════════════════════════
def load_datasets(data_dir: str, batch_size: int):
    """Load train / validation / test datasets with augmentation."""

    # DenseNet121 uses ImageNet preprocessing:
    # Scale to [0, 1], then normalize with mean=[0.485, 0.456, 0.406],
    # std=[0.229, 0.224, 0.225]
    train_datagen = keras.preprocessing.image.ImageDataGenerator(
        preprocessing_function=applications.densenet.preprocess_input,
        rotation_range=20,
        width_shift_range=0.1,
        height_shift_range=0.1,
        shear_range=0.15,
        zoom_range=0.2,
        horizontal_flip=True,
        brightness_range=[0.8, 1.2],
        fill_mode="nearest",
        validation_split=0.20,
    )

    val_datagen = keras.preprocessing.image.ImageDataGenerator(
        preprocessing_function=applications.densenet.preprocess_input,
        validation_split=0.20,
    )

    train_gen = train_datagen.flow_from_directory(
        os.path.join(data_dir, "train"),
        target_size=(IMG_SIZE, IMG_SIZE),
        batch_size=batch_size,
        class_mode="binary",
        classes=CLASS_NAMES,
        seed=SEED,
        subset="training",
    )

    val_gen = val_datagen.flow_from_directory(
        os.path.join(data_dir, "train"),
        target_size=(IMG_SIZE, IMG_SIZE),
        batch_size=batch_size,
        class_mode="binary",
        classes=CLASS_NAMES,
        seed=SEED,
        subset="validation",
    )

    test_datagen = keras.preprocessing.image.ImageDataGenerator(
        preprocessing_function=applications.densenet.preprocess_input
    )

    test_gen = test_datagen.flow_from_directory(
        os.path.join(data_dir, "test"),
        target_size=(IMG_SIZE, IMG_SIZE),
        batch_size=batch_size,
        class_mode="binary",
        classes=CLASS_NAMES,
        shuffle=False,
        seed=SEED,
    )

    return train_gen, val_gen, test_gen


# ══════════════════════════════════════════════════════════════════════════════
# 2. MODEL ARCHITECTURE — DenseNet121 + Custom Head
# ══════════════════════════════════════════════════════════════════════════════
def build_densenet121_model() -> keras.Model:
    """
    Transfer Learning Architecture:
        DenseNet121 (ImageNet weights, frozen)
        → GlobalAveragePooling2D
        → Dense(256, relu) + BatchNorm + Dropout(0.5)
        → Dense(1, sigmoid)
    """
    # Load DenseNet121 base (no top classification layers)
    base_model = applications.DenseNet121(
        input_shape=INPUT_SHAPE,
        include_top=False,
        weights="imagenet",
    )
    # Freeze entire base for Phase 1
    base_model.trainable = False

    print(f"\n  DenseNet121 base layers: {len(base_model.layers)}")
    print(f"  Trainable in Phase 1: {len(base_model.trainable_variables)} variables")

    # Classification head
    inputs = keras.Input(shape=INPUT_SHAPE)
    x = base_model(inputs, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dense(256, activation="relu")(x)
    x = layers.BatchNormalization()(x)
    x = layers.Dropout(0.5)(x)
    outputs = layers.Dense(1, activation="sigmoid", name="output")(x)

    model = keras.Model(inputs, outputs)

    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=1e-3),
        loss="binary_crossentropy",
        metrics=[
            "accuracy",
            keras.metrics.Precision(name="precision"),
            keras.metrics.Recall(name="recall"),
        ],
    )
    return model, base_model


def unfreeze_top_layers(model: keras.Model, base_model: keras.Model):
    """
    Phase 2: Unfreeze top layers of DenseNet121 for fine-tuning.
    Only layers from index FINE_TUNE_AT onward are unfrozen.
    """
    base_model.trainable = True

    # Freeze all layers before FINE_TUNE_AT
    for layer in base_model.layers[:FINE_TUNE_AT]:
        layer.trainable = False

    fine_tune_count = sum(1 for l in base_model.layers[FINE_TUNE_AT:] if l.trainable)
    print(f"\n  Fine-tuning {fine_tune_count} layers from index {FINE_TUNE_AT} onward")

    # Recompile with much lower learning rate for fine-tuning
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=1e-5),
        loss="binary_crossentropy",
        metrics=[
            "accuracy",
            keras.metrics.Precision(name="precision"),
            keras.metrics.Recall(name="recall"),
        ],
    )
    return model


# ══════════════════════════════════════════════════════════════════════════════
# 3. TRAINING
# ══════════════════════════════════════════════════════════════════════════════
def train_phase1(model, train_gen, val_gen, epochs: int, output_dir: str):
    """Phase 1: Train with frozen DenseNet121 base."""
    print("\n" + "─" * 60)
    print("  PHASE 1 — Feature Extraction (Frozen DenseNet121 Base)")
    print("─" * 60)

    cb = [
        callbacks.EarlyStopping(
            monitor="val_loss", patience=5, restore_best_weights=True, verbose=1
        ),
        callbacks.ReduceLROnPlateau(
            monitor="val_loss", factor=0.5, patience=3, min_lr=1e-7, verbose=1
        ),
        callbacks.ModelCheckpoint(
            os.path.join(output_dir, "phase1_best.h5"),
            monitor="val_accuracy", save_best_only=True, verbose=1,
        ),
    ]

    history = model.fit(
        train_gen,
        epochs=epochs,
        validation_data=val_gen,
        callbacks=cb,
        verbose=1,
    )
    return history


def train_phase2(model, train_gen, val_gen, epochs: int, output_dir: str):
    """Phase 2: Fine-tune unfrozen DenseNet121 top layers."""
    print("\n" + "─" * 60)
    print("  PHASE 2 — Fine-Tuning (Unfrozen Top Layers)")
    print("─" * 60)

    cb = [
        callbacks.EarlyStopping(
            monitor="val_loss", patience=5, restore_best_weights=True, verbose=1
        ),
        callbacks.ReduceLROnPlateau(
            monitor="val_loss", factor=0.2, patience=3, min_lr=1e-8, verbose=1
        ),
        callbacks.ModelCheckpoint(
            os.path.join(output_dir, "best_model.h5"),
            monitor="val_accuracy", save_best_only=True, verbose=1,
        ),
    ]

    history = model.fit(
        train_gen,
        epochs=epochs,
        validation_data=val_gen,
        callbacks=cb,
        verbose=1,
    )
    return history


# ══════════════════════════════════════════════════════════════════════════════
# 4. EVALUATION
# ══════════════════════════════════════════════════════════════════════════════
def evaluate(model, test_gen, output_dir: str):
    """Generate confusion matrix, classification report, and metrics."""

    y_pred_prob = model.predict(test_gen, verbose=0)
    y_pred = (y_pred_prob > 0.5).astype(int).flatten()
    y_true = test_gen.classes

    acc  = accuracy_score(y_true, y_pred)
    prec = precision_score(y_true, y_pred, zero_division=0)
    rec  = recall_score(y_true, y_pred, zero_division=0)
    f1   = f1_score(y_true, y_pred, zero_division=0)

    print("\n" + "=" * 60)
    print("  EVALUATION RESULTS")
    print("=" * 60)
    print(f"  Accuracy  : {acc:.4f}")
    print(f"  Precision : {prec:.4f}")
    print(f"  Recall    : {rec:.4f}")
    print(f"  F1 Score  : {f1:.4f}")
    print("=" * 60)
    print("\nClassification Report:")
    print(classification_report(y_true, y_pred, target_names=CLASS_NAMES))

    # Confusion Matrix plot
    cm = confusion_matrix(y_true, y_pred)
    plt.figure(figsize=(8, 6))
    sns.heatmap(cm, annot=True, fmt="d", cmap="Blues",
                xticklabels=CLASS_NAMES, yticklabels=CLASS_NAMES)
    plt.title("Confusion Matrix — DenseNet121")
    plt.ylabel("Actual")
    plt.xlabel("Predicted")
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "confusion_matrix.png"), dpi=150)
    plt.close()
    print(f"  ✓ Confusion matrix saved")

    return {"accuracy": acc, "precision": prec, "recall": rec, "f1": f1}


def plot_history(h1, h2, output_dir: str):
    """Save combined Phase 1 + Phase 2 training curves."""
    # Combine histories
    acc  = h1.history["accuracy"]     + h2.history["accuracy"]
    val_acc  = h1.history["val_accuracy"] + h2.history["val_accuracy"]
    loss = h1.history["loss"]         + h2.history["loss"]
    val_loss = h1.history["val_loss"] + h2.history["val_loss"]

    p1_end = len(h1.history["accuracy"])

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    for ax, train_data, val_data, title, ylabel in zip(
        axes,
        [acc, loss], [val_acc, val_loss],
        ["Model Accuracy", "Model Loss"],
        ["Accuracy", "Loss"],
    ):
        ax.plot(train_data, label="Train")
        ax.plot(val_data, label="Validation")
        ax.axvline(x=p1_end - 1, color="gray", linestyle="--",
                   alpha=0.7, label="Fine-tuning starts")
        ax.set_title(title)
        ax.set_xlabel("Epoch")
        ax.set_ylabel(ylabel)
        ax.legend()
        ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "training_curves.png"), dpi=150)
    plt.close()
    print(f"  ✓ Training curves saved")


# ══════════════════════════════════════════════════════════════════════════════
# 5. GRAD-CAM VISUALIZATION
# ══════════════════════════════════════════════════════════════════════════════
def grad_cam(model, img_array, last_conv_layer_name="conv5_block16_concat"):
    """
    Generate Grad-CAM heatmap.
    For DenseNet121, the last conv layer is named 'conv5_block16_concat'.
    """
    # Get the sub-model that is the DenseNet121 base
    base_model = model.layers[1]  # index 1 is the DenseNet121 base

    grad_model = keras.Model(
        inputs=base_model.input,
        outputs=[
            base_model.get_layer(last_conv_layer_name).output,
            model.output,
        ],
    )

    inputs_for_grad = tf.cast(img_array, tf.float32)
    with tf.GradientTape() as tape:
        conv_outputs, predictions = grad_model(inputs_for_grad)
        loss = predictions[:, 0]

    grads = tape.gradient(loss, conv_outputs)
    pooled_grads = tf.reduce_mean(grads, axis=(0, 1, 2))
    conv_outputs = conv_outputs[0]
    heatmap = conv_outputs @ pooled_grads[..., tf.newaxis]
    heatmap = tf.squeeze(heatmap)
    heatmap = tf.maximum(heatmap, 0) / (tf.math.reduce_max(heatmap) + 1e-8)
    return heatmap.numpy()


def save_gradcam(model, test_gen, output_dir: str, num_images=5):
    """Save Grad-CAM visualizations for sample test images."""
    try:
        import cv2
    except ImportError:
        print("  ⚠ Skipping Grad-CAM (install opencv-python)")
        return

    gradcam_dir = os.path.join(output_dir, "gradcam")
    os.makedirs(gradcam_dir, exist_ok=True)

    batch_x, batch_y = next(iter(test_gen))
    num_images = min(num_images, len(batch_x))

    for i in range(num_images):
        img = batch_x[i]
        # DenseNet preprocess_input scales to [0,1] with ImageNet normalization
        # For display, we need to reverse the normalization
        img_display = img.copy()
        mean = np.array([0.485, 0.456, 0.406])
        std = np.array([0.229, 0.224, 0.225])
        img_display = img_display * std + mean
        img_display = np.clip(img_display, 0, 1)
        img_expanded = np.expand_dims(img, axis=0)

        try:
            heatmap = grad_cam(model, img_expanded)
            heatmap_resized = cv2.resize(heatmap, (IMG_SIZE, IMG_SIZE))
            heatmap_colored = cv2.applyColorMap(
                np.uint8(255 * heatmap_resized), cv2.COLORMAP_JET
            )
            heatmap_colored = heatmap_colored.astype(np.float32) / 255.0
            superimposed = 0.6 * img_display + 0.4 * heatmap_colored
            superimposed = np.clip(superimposed, 0, 1)

            pred = model.predict(img_expanded, verbose=0)[0][0]
            label = "PNEUMONIA" if pred > 0.5 else "NORMAL"
            true_label = "PNEUMONIA" if batch_y[i] == 1 else "NORMAL"

            fig, axes = plt.subplots(1, 3, figsize=(15, 5))
            axes[0].imshow(img_display)
            axes[0].set_title(f"Original (True: {true_label})")
            axes[0].axis("off")
            axes[1].imshow(heatmap_resized, cmap="jet")
            axes[1].set_title("Grad-CAM Heatmap")
            axes[1].axis("off")
            axes[2].imshow(superimposed)
            axes[2].set_title(f"Overlay (Pred: {label}, {pred:.1%})")
            axes[2].axis("off")
            plt.tight_layout()
            plt.savefig(os.path.join(gradcam_dir, f"gradcam_{i+1}.png"), dpi=150)
            plt.close()
        except Exception as e:
            print(f"  ⚠ Grad-CAM failed for image {i+1}: {e}")

    print(f"  ✓ Grad-CAM visualizations saved to {gradcam_dir}/")


# ══════════════════════════════════════════════════════════════════════════════
# 6. TFLITE CONVERSION
# ══════════════════════════════════════════════════════════════════════════════
def convert_to_tflite(model, output_dir: str, assets_dir: str = None):
    """
    Convert trained Keras model to optimized TFLite format.
    Modified to export TWO outputs:
    1. The final prediction (sigmoid)
    2. The last convolutional layer activations (for Grad-CAM)
    """
    print("\n🏗️  Preparing multi-output model for TFLite (Grad-CAM support)...")
    
    # DenseNet121 base is at index 1 in our model
    base_model = model.layers[1]
    last_conv_layer = base_model.get_layer("conv5_block16_concat")
    
    # Create a model that outputs both the prediction and the activations
    multi_output_model = keras.Model(
        inputs=model.input,
        outputs=[model.output, last_conv_layer.output]
    )

    converter = tf.lite.TFLiteConverter.from_keras_model(multi_output_model)
    # Dynamic range quantization — reduces size ~4x with minimal accuracy loss
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    tflite_path = os.path.join(output_dir, "densenet_pneumonia.tflite")
    with open(tflite_path, "wb") as f:
        f.write(tflite_model)

    size_mb = os.path.getsize(tflite_path) / (1024 * 1024)
    print(f"\n  ✓ TFLite model saved: {tflite_path} ({size_mb:.2f} MB)")

    if assets_dir:
        os.makedirs(assets_dir, exist_ok=True)
        assets_path = os.path.join(assets_dir, "densenet_pneumonia.tflite")
        with open(assets_path, "wb") as f:
            f.write(tflite_model)
        print(f"  ✓ Copied to Flutter assets: {assets_path}")

    return tflite_path


# ══════════════════════════════════════════════════════════════════════════════
# 7. MAIN
# ══════════════════════════════════════════════════════════════════════════════
def main():
    args = parse_args()
    os.makedirs(args.output_dir, exist_ok=True)

    print("\n" + "=" * 60)
    print("  PNEUMOSCAN AI — DENSENET121 TRANSFER LEARNING")
    print("=" * 60)

    # 1. Data
    print("\n📂 Loading datasets...")
    train_gen, val_gen, test_gen = load_datasets(args.data_dir, args.batch_size)
    print(f"   Train : {train_gen.samples} images")
    print(f"   Val   : {val_gen.samples} images")
    print(f"   Test  : {test_gen.samples} images")

    # 2. Build model
    print("\n🏗️  Building DenseNet121 model...")
    model, base_model = build_densenet121_model()
    model.summary()

    # 3. Phase 1 — Feature Extraction
    history1 = train_phase1(
        model, train_gen, val_gen, args.epochs_phase1, args.output_dir
    )

    # 4. Phase 2 — Fine-tuning
    model = unfreeze_top_layers(model, base_model)
    history2 = train_phase2(
        model, train_gen, val_gen, args.epochs_phase2, args.output_dir
    )

    # 5. Evaluate
    print("\n📊 Evaluating on test set...")
    metrics = evaluate(model, test_gen, args.output_dir)
    plot_history(history1, history2, args.output_dir)

    # 6. Grad-CAM
    print("\n🔍 Generating Grad-CAM visualizations...")
    save_gradcam(model, test_gen, args.output_dir)

    # 7. Save & convert
    print("\n💾 Saving models...")
    h5_path = os.path.join(args.output_dir, "densenet_pneumonia.h5")
    model.save(h5_path)
    print(f"  ✓ Keras model saved: {h5_path}")

    script_dir = os.path.dirname(os.path.abspath(__file__))
    assets_dir = os.path.join(script_dir, "..", "assets", "model")
    convert_to_tflite(model, args.output_dir, assets_dir)

    print("\n" + "=" * 60)
    print("  ✅ TRAINING COMPLETE!")
    print("=" * 60)
    print(f"  Accuracy : {metrics['accuracy']:.4f}")
    print(f"  F1 Score : {metrics['f1']:.4f}")
    print(f"  Model    : {h5_path}")
    print("=" * 60 + "\n")


if __name__ == "__main__":
    main()
