import os
import json
import numpy as np
import tensorflow as tf
from tensorflow import keras

model_path = r"c:\Users\sheet\OneDrive\Documents\Middle East College (MEC)\Graduation Project\Implementation\pneumonia_detection--\model\densenet_BEST_FINAL.keras"
output_path = r"c:\Users\sheet\OneDrive\Documents\Middle East College (MEC)\Graduation Project\Implementation\pneumonia_detection--\assets\model\dense_weights.json"

print(f"Loading model from {model_path}...")
try:
    model = keras.models.load_model(model_path)
    print("Model loaded successfully.")
    model.summary()
    
    # Let's find the Dense layers and BatchNormalization layers in the classification head
    # The layers after the DenseNet base
    print("\nListing model layers:")
    dense_layers = []
    for layer in model.layers:
        print(f"- {layer.name} ({type(layer).__name__})")
        if isinstance(layer, keras.layers.Dense):
            dense_layers.append(layer)
    
    dense_256 = None
    dense_output = None
    
    for layer in model.layers:
        if isinstance(layer, keras.layers.Dense) or "dense" in layer.name.lower():
            w, b = layer.get_weights()
            print(f"Found dense layer: {layer.name}, weights shape: {w.shape}, bias shape: {b.shape}")
            if w.shape[1] == 256:
                dense_256 = layer
            elif w.shape[1] == 1:
                dense_output = layer
                
    if dense_256 is not None and dense_output is not None:
        w1, b1 = dense_256.get_weights()
        w2, b2 = dense_output.get_weights()
        
        # Save to JSON
        data = {
            "w1": w1.tolist(), # shape (1024, 256)
            "b1": b1.tolist(), # shape (256,)
            "w2": w2.tolist(), # shape (256, 1)
            "b2": b2.tolist(), # shape (1,)
        }
        
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "w") as f:
            json.dump(data, f)
            
        print(f"\nSuccessfully extracted and saved dense weights to: {output_path}")
    else:
        print("\nERROR: Could not locate the dense layers of shape 256 and 1.")
        
except Exception as e:
    print(f"Error: {e}")
