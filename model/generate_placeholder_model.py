"""
=============================================================================
Generate Placeholder DenseNet121 TFLite Model
=============================================================================
Creates a randomly initialized DenseNet121-based TFLite model with
the EXACT same input/output shape as the real trained model, so the
Flutter app can be tested without a trained model.

Input  : (1, 224, 224, 3) — float32 (ImageNet normalized)
Output : (1, 1)            — float32 (sigmoid 0..1)

Usage:
    python generate_placeholder_model.py
=============================================================================
"""

import os
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers, applications


def main():
    print("🔧 Building DenseNet121 placeholder model...")

    # Same architecture as the real model
    base_model = applications.DenseNet121(
        input_shape=(224, 224, 3),
        include_top=False,
        weights=None,  # Random weights — no download needed
    )
    base_model.trainable = False

    inputs = keras.Input(shape=(224, 224, 3))
    x = base_model(inputs, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dense(256, activation="relu")(x)
    x = layers.BatchNormalization()(x)
    x = layers.Dropout(0.5)(x)
    outputs = layers.Dense(1, activation="sigmoid", name="output")(x)
    model = keras.Model(inputs, outputs)

    model.compile(optimizer="adam", loss="binary_crossentropy")
    model.summary()

    # Convert to TFLite
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    # Save to assets directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    assets_dir = os.path.join(script_dir, "..", "assets", "model")
    os.makedirs(assets_dir, exist_ok=True)

    output_path = os.path.join(assets_dir, "densenet_pneumonia.tflite")
    with open(output_path, "wb") as f:
        f.write(tflite_model)

    size_kb = os.path.getsize(output_path) / 1024
    print(f"\n✅ DenseNet121 placeholder model saved: {output_path}")
    print(f"   Size: {size_kb:.1f} KB")
    print(f"\n⚠️  This is a PLACEHOLDER model with random weights.")
    print(f"   Train the real model with: python train_model.py")


if __name__ == "__main__":
    main()
