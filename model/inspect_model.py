import tensorflow as tf
from tensorflow import keras

# Path to your .h5 model
model_path = r'c:\Users\sheet\OneDrive\Documents\Middle East College (MEC)\Graduation Project\Project\pneumonia_detection--\assets\model\densenet_BEST_FINAL.h5'

try:
    print(f"--- Loading Model: {model_path} ---")
    model = keras.models.load_model(model_path)
    
    print("\n[SUMMARY]")
    model.summary()
    
    print("\n[INPUTS]")
    print(model.input)
    
    print("\n[OUTPUTS]")
    print(model.output)
    
    # Identify the DenseNet base and the last conv layer
    # Usually index 1 is the base model in our pipeline
    for i, layer in enumerate(model.layers):
        print(f"Layer {i}: {layer.name} ({type(layer).__name__})")
        if "densenet121" in layer.name.lower():
            print(f"  -> Found DenseNet base at index {i}")
            # Try to find the concat layer in the base
            try:
                target = layer.get_layer("conv5_block16_concat")
                print(f"  -> Successfully found Grad-CAM target layer: {target.name}")
            except:
                print("  -> Could NOT find 'conv5_block16_concat' in base. Listing base layers...")
                for j, sub_layer in enumerate(layer.layers[-10:]): # list last 10
                    print(f"     Sub-Layer: {sub_layer.name}")

except Exception as e:
    print(f"\nERROR: {e}")
