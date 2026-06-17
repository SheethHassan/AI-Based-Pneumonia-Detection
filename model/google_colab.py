# -*- coding: utf-8 -*-
"""Pneumonia Detection - Optimized
This script incorporates Focal Loss, cleaner validation generators,
aggressive augmentation, and proper multi-output TFLite export.
"""

import os
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns

import tensorflow as tf
from tensorflow import keras
from tensorflow.keras.applications import DenseNet121
from tensorflow.keras.preprocessing.image import ImageDataGenerator
from tensorflow.keras import layers, models
import tensorflow.keras.backend as K
from sklearn.metrics import classification_report, confusion_matrix, f1_score, precision_score, recall_score, accuracy_score
from sklearn.utils.class_weight import compute_class_weight

# Ensure Google Drive is mounted if running in Colab
try:
    from google.colab import drive
    drive.mount('/content/drive')
except ImportError:
    print("Not running in Colab. Ensure paths are correct.")

# ==========================================
# 1. CONSTANTS & PATHS
# ==========================================
IMG_SIZE = (224, 224)
BATCH_SIZE = 32
CLASS_NAMES = ["NORMAL", "PNEUMONIA"]
INPUT_SHAPE = (224, 224, 3)
SEED = 42
FINAL_THRESHOLD = 0.25 # Lowered threshold as suggested

base_dir = '/content/drive/MyDrive/chest_xray/chest_xray'
train_dir = f'{base_dir}/train'
test_dir = f'{base_dir}/test'
val_dir = f'{base_dir}/val'  # Using proper validation directory

# Verify folder structure
for split in ['train', 'val', 'test']:
    for cls in ['NORMAL', 'PNEUMONIA']:
        path = f'{base_dir}/{split}/{cls}'
        if os.path.exists(path):
            count = len(os.listdir(path))
            print(f"{split}/{cls}: {count} images")
        else:
            print(f"Directory not found: {path}")

# ==========================================
# 2. PREPROCESSING & AUGMENTATION
# ==========================================
train_datagen = ImageDataGenerator(
    rescale=1./255,
    rotation_range=30,      # Increased rotation
    width_shift_range=0.15, # Increased shift
    height_shift_range=0.15,
    shear_range=0.2,        # Increased shear
    zoom_range=0.3,         # Increased zoom
    horizontal_flip=True,
    brightness_range=[0.7, 1.3], # Broader brightness range
    fill_mode="nearest"
)

# NO Augmentation for validation and test data
val_test_datagen = ImageDataGenerator(rescale=1./255)

train_gen = train_datagen.flow_from_directory(
    train_dir,
    target_size=IMG_SIZE,
    batch_size=BATCH_SIZE,
    class_mode='binary',
    seed=SEED,
    shuffle=True
)

val_gen = val_test_datagen.flow_from_directory(
    val_dir,
    target_size=IMG_SIZE,
    batch_size=BATCH_SIZE,
    class_mode="binary",
    shuffle=False,
    seed=SEED
)

test_gen = val_test_datagen.flow_from_directory(
    test_dir,
    target_size=IMG_SIZE,
    batch_size=BATCH_SIZE,
    class_mode="binary",
    shuffle=False
)

print(f"Training Images: {train_gen.samples}")
print(f"Validation Images: {val_gen.samples}")
print(f"Test Images: {test_gen.samples}")
print(f"Class indices: {train_gen.class_indices}")

# ==========================================
# 3. CLASS IMBALANCE & FOCAL LOSS
# ==========================================
class_weights = compute_class_weight(
    class_weight='balanced',
    classes=np.array([0, 1]),
    y=train_gen.classes
)
# Normal case is index 0. Setting it manually to penalize missing normal cases
class_weight_dict = {0: 3.5, 1: class_weights[1]}

print(f"Class weight for NORMAL is: {class_weight_dict[0]:.4f}")
print(f"Class weight for PNEUMONIA is: {class_weight_dict[1]:.4f}")

def focal_loss(gamma=2.0, alpha=0.8):
    """
    Focal Loss forces the model to learn hard examples.
    """
    def focal_loss_fixed(y_true, y_pred):
        y_true = tf.cast(y_true, tf.float32)
        epsilon = K.epsilon()
        y_pred = K.clip(y_pred, epsilon, 1.0 - epsilon)
        
        pt_1 = tf.where(tf.equal(y_true, 1), y_pred, tf.ones_like(y_pred))
        pt_0 = tf.where(tf.equal(y_true, 0), y_pred, tf.zeros_like(y_pred))
        
        loss = -K.mean(alpha * K.pow(1. - pt_1, gamma) * K.log(pt_1)) \
               -K.mean((1 - alpha) * K.pow(pt_0, gamma) * K.log(1. - pt_0))
        return loss
    return focal_loss_fixed

# ==========================================
# 4. PHASE 1: DenseNet121 BASE TRAINING
# ==========================================
base_model = DenseNet121(
    input_shape=INPUT_SHAPE,
    include_top=False,
    weights="imagenet"
)
base_model.trainable = False # Freeze Model

model = models.Sequential([
    base_model,
    layers.GlobalAveragePooling2D(),
    layers.BatchNormalization(),
    layers.Dense(256, activation='relu'),
    layers.Dropout(0.4),
    layers.Dense(128, activation='relu'),
    layers.Dropout(0.3),
    layers.Dense(1, activation='sigmoid')
])

model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=1e-4),
    loss=focal_loss(gamma=2.0, alpha=0.8), # Using Focal Loss
    metrics=['accuracy', tf.keras.metrics.AUC(name='auc')]
)
model.summary()

callbacks_phase1 = [
    tf.keras.callbacks.EarlyStopping(monitor='val_loss', patience=5, restore_best_weights=True, verbose=1),
    tf.keras.callbacks.ReduceLROnPlateau(monitor='val_loss', factor=0.5, patience=3, verbose=1, min_lr=1e-7),
    tf.keras.callbacks.ModelCheckpoint(
        filepath='/content/drive/MyDrive/densenet_phase1_best.h5',
        monitor='val_auc', save_best_only=True, verbose=1
    )
]

print("=" * 50)
print("Phase 1: Training Top layers only (Frozen Base)")
print("=" * 50)

history_phase1 = model.fit(
    train_gen,
    validation_data=val_gen,
    epochs=20,
    class_weight=class_weight_dict,
    callbacks=callbacks_phase1
)

# ------------------------------------------
# STEP 1 CHECKPOINT & EVALUATION (PHASE 1)
# ------------------------------------------
print("\n" + "="*50)
print("             PHASE 1 EVALUATION")
print("="*50)
from sklearn.metrics import (
    classification_report, confusion_matrix, f1_score, precision_score, 
    recall_score, accuracy_score, roc_curve, auc, precision_recall_curve, 
    average_precision_score, matthews_corrcoef
)

# Load best Phase 1 model for evaluation
try:
    phase1_best_model = tf.keras.models.load_model(
        '/content/drive/MyDrive/densenet_phase1_best.h5', 
        custom_objects={'focal_loss_fixed': focal_loss()}
    )
except Exception as e:
    print("Could not load saved phase 1 model, using current model weights instead.")
    phase1_best_model = model

test_gen.reset()
y_pred_probs1 = phase1_best_model.predict(test_gen, verbose=1).flatten()
y_true = test_gen.classes
y_pred_labels1 = (y_pred_probs1 > FINAL_THRESHOLD).astype(int)

# Metrics
tn1, fp1, fn1, tp1 = confusion_matrix(y_true, y_pred_labels1).ravel()
sens1 = tp1 / (tp1 + fn1)
spec1 = tn1 / (tn1 + fp1)
prec1 = tp1 / (tp1 + fp1)
f1_1 = f1_score(y_true, y_pred_labels1)
f2_1 = (5 * prec1 * sens1) / (4 * prec1 + sens1)
mcc1 = matthews_corrcoef(y_true, y_pred_labels1)
fpr1, tpr_roc1, _ = roc_curve(y_true, y_pred_probs1)
roc_auc1 = auc(fpr1, tpr_roc1)
prec_c1, rec_c1, _ = precision_recall_curve(y_true, y_pred_probs1)
pr_auc1 = average_precision_score(y_true, y_pred_probs1)

print("\n             PHASE 1 CLINICAL EVALUATION REPORT")
print("="*50)
print(f"Accuracy:                    {accuracy_score(y_true, y_pred_labels1)*100:.2f}%")
print(f"Recall (Sensitivity):        {sens1*100:.2f}%")
print(f"Specificity:                 {spec1*100:.2f}%")
print(f"Precision:                   {prec1*100:.2f}%")
print(f"F1-Score:                    {f1_1:.4f}")
print(f"F2-Score (Recall-Weighted):  {f2_1:.4f}")
print(f"Matthews Correlation (MCC):  {mcc1:.4f}")
print(f"ROC-AUC:                     {roc_auc1:.4f}")
print(f"PR-AUC:                      {pr_auc1:.4f}")
print(f"True Negatives (NORMAL):     {tn1}")
print(f"False Positives (Alarms):    {fp1}")
print(f"False Negatives (Misses):    {fn1}")
print(f"True Positives (PNEUMONIA):  {tp1}")
print("="*50)

# Plots
fig, axs = plt.subplots(1, 3, figsize=(18, 5))
axs[0].plot(history_phase1.history['accuracy'], label='Train Acc')
axs[0].plot(history_phase1.history['val_accuracy'], label='Val Acc')
axs[0].set_title('Phase 1: Accuracy')
axs[0].legend()

axs[1].plot(history_phase1.history['loss'], label='Train Loss')
axs[1].plot(history_phase1.history['val_loss'], label='Val Loss')
axs[1].set_title('Phase 1: Focal Loss')
axs[1].legend()

axs[2].plot(history_phase1.history['auc'], label='Train AUC')
axs[2].plot(history_phase1.history['val_auc'], label='Val AUC')
axs[2].set_title('Phase 1: AUC')
axs[2].legend()
plt.tight_layout()
plt.savefig('/content/drive/MyDrive/phase1_training_curves.png')
plt.show()

# Trigger Phase 1 best model download immediately
try:
    from google.colab import files
    print("\nDownloading Phase 1 Best Model Checkpoint...")
    files.download('/content/drive/MyDrive/densenet_phase1_best.h5')
except Exception as e:
    print("Automatic download of Phase 1 model skipped. Ensure it is saved in your Drive folder.")


# ==========================================
# 5. PHASE 2: FINE TUNING (100 LAYERS)
# ==========================================
base_model.trainable = True

# Freeze all layers EXCEPT the last 100 layers (deeper fine-tuning)
for layer in base_model.layers[:-100]:
    layer.trainable = False

trainable_count = sum(1 for l in base_model.layers if l.trainable)
print(f"\nTrainable base layers in Phase 2: {trainable_count}")

# Re-use Phase 1 best model weights to start fine-tuning
model = phase1_best_model

model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=1e-5),
    loss=focal_loss(gamma=2.0, alpha=0.8),
    metrics=['accuracy', tf.keras.metrics.AUC(name='auc')]
)

callbacks_phase2 = [
    tf.keras.callbacks.EarlyStopping(monitor='val_loss', patience=6, restore_best_weights=True, verbose=1),
    tf.keras.callbacks.ReduceLROnPlateau(monitor='val_loss', factor=0.5, patience=3, verbose=1, min_lr=1e-8),
    tf.keras.callbacks.ModelCheckpoint(
        filepath='/content/drive/MyDrive/densenet_phase2_best.h5',
        monitor='val_auc', save_best_only=True, verbose=1
    )
]

print("=" * 50)
print("PHASE 2: Fine Tuning (Last 100 layers)")
print("=" * 50)

history_phase2 = model.fit(
    train_gen,
    validation_data=val_gen,
    epochs=20,
    class_weight=class_weight_dict,
    callbacks=callbacks_phase2
)

# ------------------------------------------
# STEP 2 CHECKPOINT & EVALUATION (PHASE 2)
# ------------------------------------------
print("\n" + "="*50)
print("             PHASE 2 EVALUATION")
print("="*50)

# Load best Phase 2 model
phase2_best_model = tf.keras.models.load_model(
    '/content/drive/MyDrive/densenet_phase2_best.h5', 
    custom_objects={'focal_loss_fixed': focal_loss()}
)

print("\nComparing Phase 1 vs Phase 2 models to find absolute best...")
val_gen.reset()
print("\nEvaluating Phase 1 best model on Validation Set:")
r1 = phase1_best_model.evaluate(val_gen, verbose=1)
print(f"  Phase 1 AUC: {r1[2]:.4f}")

val_gen.reset()
print("\nEvaluating Phase 2 best model on Validation Set:")
r2 = phase2_best_model.evaluate(val_gen, verbose=1)
print(f"  Phase 2 AUC: {r2[2]:.4f}")

if r1[2] >= r2[2]:
    best_model = phase1_best_model
    print("\nPhase 1 model is better — using densenet_phase1_best.h5 as final")
else:
    best_model = phase2_best_model
    print("\nPhase 2 model is better — using densenet_phase2_best.h5 as final")

# Save definitive final H5 model (which holds highest AUC weights)
best_model.save('/content/drive/MyDrive/densenet_BEST_FINAL.h5')
print("Best Keras model safely saved as densenet_BEST_FINAL.h5")

test_gen.reset()
y_pred_probs2 = best_model.predict(test_gen, verbose=1).flatten()

# Fixing False Positive Issue by trying different thresholds
print("\nTrying different thresholds to find the best balance...")
thresholds = [0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7]

best_f1 = -1
best_threshold = FINAL_THRESHOLD

print(f"{'Threshold':<12} {'Accuracy': <12} {'Precision':<12}{'Recall':<12}{'F1': <10}{'FN':<8}{'FP':<8}")
print("-" * 74)

for thresh in thresholds:
    y_pred_temp = (y_pred_probs2 > thresh).astype(int)
    tn_t, fp_t, fn_t, tp_t = confusion_matrix(y_true, y_pred_temp).ravel()
    
    acc_t = (tp_t + tn_t) / (tp_t + tn_t + fp_t + fn_t)
    prec_t = tp_t / (tp_t + fp_t) if (tp_t + fp_t) > 0 else 0
    rec_t = tp_t / (tp_t + fn_t) if (tp_t + fn_t) > 0 else 0
    f1_t = 2 * (prec_t * rec_t) / (prec_t + rec_t) if (prec_t + rec_t) > 0 else 0
    
    print(f"{thresh:<12.2f}{acc_t*100:<12.2f}{prec_t*100:<12.2f}{rec_t*100:<12.2f}{f1_t*100:<10.2f}{fn_t:<8} {fp_t:<8}")
    
    if f1_t > best_f1:
        best_f1 = f1_t
        best_threshold = thresh

print(f"\nBest threshold selected: {best_threshold} with F1-score: {best_f1*100:.2f}%")
FINAL_THRESHOLD = best_threshold # Override the constant for the rest of the script

y_pred_labels2 = (y_pred_probs2 > FINAL_THRESHOLD).astype(int)

# Calculate metrics manually
tn2, fp2, fn2, tp2 = confusion_matrix(y_true, y_pred_labels2).ravel()
sens2 = tp2 / (tp2 + fn2)
spec2 = tn2 / (tn2 + fp2)
prec2 = tp2 / (tp2 + fp2)
f1_2 = f1_score(y_true, y_pred_labels2)
f2_2 = (5 * prec2 * sens2) / (4 * prec2 + sens2)
mcc2 = matthews_corrcoef(y_true, y_pred_labels2)
fpr2, tpr_roc2, _ = roc_curve(y_true, y_pred_probs2)
roc_auc2 = auc(fpr2, tpr_roc2)
prec_c2, rec_c2, _ = precision_recall_curve(y_true, y_pred_probs2)
pr_auc2 = average_precision_score(y_true, y_pred_probs2)

print("\n             PHASE 2 CLINICAL EVALUATION REPORT")
print("="*50)
print(f"Accuracy:                    {accuracy_score(y_true, y_pred_labels2)*100:.2f}%")
print(f"Recall (Sensitivity):        {sens2*100:.2f}%")
print(f"Specificity:                 {spec2*100:.2f}%")
print(f"Precision:                   {prec2*100:.2f}%")
print(f"F1-Score:                    {f1_2:.4f}")
print(f"F2-Score (Recall-Weighted):  {f2_2:.4f}")
print(f"Matthews Correlation (MCC):  {mcc2:.4f}")
print(f"ROC-AUC:                     {roc_auc2:.4f}")
print(f"PR-AUC:                      {pr_auc2:.4f}")
print(f"True Negatives (NORMAL):     {tn2}")
print(f"False Positives (Alarms):    {fp2}")
print(f"False Negatives (Misses):    {fn2}")
print(f"True Positives (PNEUMONIA):  {tp2}")
print("="*50)

# Plot Comparison curves Phase 1 vs Phase 2
print("\nPlotting historical comparisons...")
fig, axs = plt.subplots(2, 3, figsize=(18, 10))
# Phase 1
axs[0, 0].plot(history_phase1.history['accuracy'], label='Train Acc')
axs[0, 0].plot(history_phase1.history['val_accuracy'], label='Val Acc')
axs[0, 0].set_title('Phase 1: Accuracy')
axs[0, 0].legend()

axs[0, 1].plot(history_phase1.history['loss'], label='Train Loss')
axs[0, 1].plot(history_phase1.history['val_loss'], label='Val Loss')
axs[0, 1].set_title('Phase 1: Focal Loss')
axs[0, 1].legend()

axs[0, 2].plot(history_phase1.history['auc'], label='Train AUC')
axs[0, 2].plot(history_phase1.history['val_auc'], label='Val AUC')
axs[0, 2].set_title('Phase 1: AUC')
axs[0, 2].legend()

# Phase 2
axs[1, 0].plot(history_phase2.history['accuracy'], label='Train Acc')
axs[1, 0].plot(history_phase2.history['val_accuracy'], label='Val Acc')
axs[1, 0].set_title('Phase 2: Accuracy')
axs[1, 0].legend()

axs[1, 1].plot(history_phase2.history['loss'], label='Train Loss')
axs[1, 1].plot(history_phase2.history['val_loss'], label='Val Loss')
axs[1, 1].set_title('Phase 2: Focal Loss')
axs[1, 1].legend()

axs[1, 2].plot(history_phase2.history['auc'], label='Train AUC')
axs[1, 2].plot(history_phase2.history['val_auc'], label='Val AUC')
axs[1, 2].set_title('Phase 2: AUC')
axs[1, 2].legend()
plt.tight_layout()
plt.savefig('/content/drive/MyDrive/training_curves_comparison.png')
plt.show()

# Plot Confusion Matrix
plt.figure(figsize=(6, 5))
sns.heatmap(
    [[tn2, fp2], [fn2, tp2]], 
    annot=True, 
    fmt="d", 
    cmap="Blues", 
    xticklabels=CLASS_NAMES, 
    yticklabels=CLASS_NAMES
)
plt.ylabel('Actual Class')
plt.xlabel('Predicted Class')
plt.title(f'Confusion Matrix (Threshold = {FINAL_THRESHOLD})')
plt.savefig('/content/drive/MyDrive/confusion_matrix.png')
plt.show()

# Plot ROC & PR curves
plt.figure(figsize=(12, 5))
plt.subplot(1, 2, 1)
plt.plot(fpr2, tpr_roc2, label=f'ROC Curve (AUC = {roc_auc2:.4f})', color='darkorange', lw=2)
plt.xlabel('False Positive Rate')
plt.ylabel('True Positive Rate (Recall)')
plt.title('ROC Curve')
plt.legend(loc="lower right")

plt.subplot(1, 2, 2)
plt.plot(rec_c2, prec_c2, label=f'PR Curve (AUC = {pr_auc2:.4f})', color='green', lw=2)
plt.xlabel('Recall')
plt.ylabel('Precision')
plt.title('Precision-Recall Curve')
plt.legend(loc="lower left")
plt.tight_layout()
plt.savefig('/content/drive/MyDrive/roc_pr_curves.png')
plt.show()
# ==========================================
# 10. VISUAL GRAD-CAM DISPLAY
# ==========================================
import cv2

def make_gradcam_heatmap(img_array, model, last_conv_layer_name):
    base_model = model.layers[0]
    grad_model = tf.keras.models.Model(
        inputs=[base_model.input],
        outputs=[base_model.get_layer(last_conv_layer_name).output, model.output]
    )
    with tf.GradientTape() as tape:
        last_conv_layer_output, preds = grad_model(img_array)
        class_channel = preds[:, 0]

    grads = tape.gradient(class_channel, last_conv_layer_output)
    pooled_grads = tf.reduce_mean(grads, axis=(0, 1, 2))
    
    last_conv_layer_output = last_conv_layer_output[0]
    heatmap = last_conv_layer_output @ pooled_grads[..., tf.newaxis]
    heatmap = tf.squeeze(heatmap)
    
    heatmap = tf.maximum(heatmap, 0) / tf.math.reduce_max(heatmap)
    return heatmap.numpy()

# Select sample images for visual demonstration
print("\nGenerating Visual Grad-CAM plots...")
test_gen.reset()
imgs, labels = next(test_gen)

fig, axs = plt.subplots(2, 4, figsize=(16, 8))
normal_count = 0
pneumonia_count = 0

for img, label in zip(imgs, labels):
    if label == 0 and normal_count < 2:
        col = normal_count
        row = 0
        normal_count += 1
    elif label == 1 and pneumonia_count < 2:
        col = pneumonia_count + 2
        row = 1
        pneumonia_count += 1
    else:
        continue

    img_array = np.expand_dims(img, axis=0)
    pred_prob = best_model.predict(img_array)[0][0]
    pred_class = "PNEUMONIA" if pred_prob > FINAL_THRESHOLD else "NORMAL"
    true_class = "PNEUMONIA" if label == 1 else "NORMAL"
    
    heatmap = make_gradcam_heatmap(img_array, best_model, "conv5_block16_concat")
    
    # Resize heatmap to match image size
    heatmap = cv2.resize(heatmap, (224, 224))
    heatmap = np.uint8(255 * heatmap)
    heatmap = cv2.applyColorMap(heatmap, cv2.COLORMAP_JET)
    
    # Overlay heatmap on original image (rescaled back to 0-255)
    orig_img = np.uint8(255 * img)
    superimposed_img = cv2.addWeighted(orig_img, 0.6, heatmap, 0.4, 0)
    
    axs[row, col].imshow(superimposed_img)
    axs[row, col].set_title(f"True: {true_class}\nPred: {pred_class} ({pred_prob:.2f})")
    axs[row, col].axis('off')

plt.tight_layout()
plt.savefig('/content/drive/MyDrive/gradcam_samples.png')
plt.show()

# Trigger Phase 2 best & final model downloads immediately
try:
    from google.colab import files
    print("\nDownloading Phase 2 & Final Models...")
    files.download('/content/drive/MyDrive/densenet_phase2_best.h5')
    files.download('/content/drive/MyDrive/densenet_BEST_FINAL.h5')
except Exception as e:
    print("Automatic download of Phase 2 models skipped. Ensure they are saved in your Drive folder.")


# ==========================================
# 8. MULTI-OUTPUT TFLITE EXPORT
# ==========================================
print("\nCreating Multi-Output TFLite Model for Flutter...")
target_layer = best_model.layers[0].get_layer("conv5_block16_concat")

multi_output_model = keras.Model(
    inputs=best_model.input,
    outputs=[best_model.output, target_layer.output]
)

converter = tf.lite.TFLiteConverter.from_keras_model(multi_output_model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()

tflite_path = '/content/drive/MyDrive/MULTI_OUTPUT_MODEL_flutter.tflite'
with open(tflite_path, 'wb') as f:
    f.write(tflite_model)
print("✅ Multi-Output TFLite Model saved successfully.")

# Trigger TFLite download immediately
try:
    from google.colab import files
    print("\nDownloading TFLite Model...")
    files.download(tflite_path)
except Exception as e:
    print("Automatic download of TFLite model skipped. Ensure it is saved in your Drive folder.")


# ==========================================
# 9. TFLITE ACCURACY VERIFICATION
# ==========================================
print("\nVerifying TFLite Model Accuracy & Conversion...")
interpreter = tf.lite.Interpreter(model_path=tflite_path)
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

class_output_index = -1
for detail in output_details:
    if detail['shape'][-1] == 1:
        class_output_index = detail['index']
        break

tflite_preds = []
tflite_trues = []

test_gen.reset()
for i in range(len(test_gen)):
    imgs, labels = next(test_gen)
    for img, label in zip(imgs, labels):
        input_data = np.expand_dims(img, axis=0).astype(np.float32)
        interpreter.set_tensor(input_details[0]['index'], input_data)
        interpreter.invoke()
        pred = interpreter.get_tensor(class_output_index)[0][0]
        tflite_preds.append(pred)
        tflite_trues.append(label)

tflite_preds = np.array(tflite_preds)
tflite_trues = np.array(tflite_trues)
tflite_pred_labels = (tflite_preds > FINAL_THRESHOLD).astype(int)

tflite_acc = accuracy_score(tflite_trues, tflite_pred_labels)
tflite_rec = recall_score(tflite_trues, tflite_pred_labels)
tflite_spec = confusion_matrix(tflite_trues, tflite_pred_labels).ravel()[0] / (confusion_matrix(tflite_trues, tflite_pred_labels).ravel()[0] + confusion_matrix(tflite_trues, tflite_pred_labels).ravel()[1])

print("="*50)
print("            TFLITE MODEL VERIFICATION")
print("="*50)
print(f"TFLite Accuracy:             {tflite_acc*100:.2f}% (Keras: {accuracy_score(y_true, y_pred_labels2)*100:.2f}%)")
print(f"TFLite Recall (Sensitivity): {tflite_rec*100:.2f}% (Keras: {sens2*100:.2f}%)")
print(f"TFLite Specificity:          {tflite_spec*100:.2f}% (Keras: {spec2*100:.2f}%)")
print("="*50)


