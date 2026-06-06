# PneumoScan AI — Pneumonia Detection

AI-powered pneumonia detection from chest X-ray images using **DenseNet121** deep learning model.

## Architecture

- **Model**: DenseNet121 (Transfer Learning + Fine-Tuning)
- **Input**: 224×224 RGB chest X-ray images
- **Output**: Binary classification — Normal / Pneumonia (sigmoid)
- **Preprocessing**: ImageNet normalization (mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
- **Format**: TensorFlow Lite (`.tflite`) for on-device inference

## Project Structure

```
pneumonia_detection/
├── lib/
│   ├── main.dart                    # App entry, splash, auth gate
│   ├── firebase_options.dart        # Firebase configuration
│   ├── models/
│   │   └── classification_result.dart   # Prediction data model
│   ├── screens/
│   │   ├── login_screen.dart        # Doctor ID authentication
│   │   ├── home_screen.dart         # X-ray upload & analysis
│   │   └── result_screen.dart       # Classification results display
│   ├── services/
│   │   ├── auth_service.dart        # Firebase Auth wrapper
│   │   ├── classifier_service.dart  # TFLite DenseNet121 inference
│   │   └── image_service.dart       # Gallery image picker
│   └── theme/
│       └── app_theme.dart           # Medical-themed design system
├── assets/
│   └── model/
│       ├── densenet_pneumonia.tflite # Trained DenseNet121 model (~28MB)
│       └── labels.txt               # Class labels (Normal, Pneumonia)
├── model/
│   ├── train_model.py               # DenseNet121 training pipeline
│   ├── generate_placeholder_model.py # Placeholder model generator
│   └── requirements.txt             # Python dependencies
└── pubspec.yaml
```

## Features

- 🔐 **Doctor Authentication** — Firebase Auth with Doctor ID lookup via Firestore
- 📷 **X-Ray Upload** — Pick chest X-ray images from gallery
- 🧠 **AI Analysis** — On-device DenseNet121 inference via TensorFlow Lite
- 📊 **Results Display** — Animated confidence ring, color-coded labels
- ⚕️ **Medical Disclaimer** — Educational use notice on all screens

## Getting Started

1. Ensure Flutter SDK is installed
2. Run `flutter pub get`
3. Configure Firebase (`firebase_options.dart`)
4. Run `flutter run`

## Model Training

```bash
cd model
pip install -r requirements.txt
python train_model.py --data_dir ./dataset --epochs_phase1 10 --epochs_phase2 10
```

The trained `densenet_pneumonia.tflite` model will be automatically copied to `assets/model/`.
