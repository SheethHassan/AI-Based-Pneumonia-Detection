# OmniSense AI — Pneumonia Detection

AI-powered pneumonia detection from chest X-ray images using a **DenseNet121** deep learning model, delivered as a Flutter mobile app with on-device inference.

## Architecture

- **Model**: DenseNet121 (transfer learning + fine-tuning)
- **Input**: 224×224 RGB chest X-ray images
- **Output**: Binary classification — Normal / Pneumonia (sigmoid)
- **Preprocessing**: ImageNet normalization (mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
- **Format**: TensorFlow Lite (`.tflite`) for on-device inference

## Project Structure

```
pneumonia_detection/
├── lib/
│   ├── main.dart                         # App entry, splash, auth gate
│   ├── firebase_options.dart             # Firebase configuration
│   ├── models/
│   │   ├── classification_result.dart    # Prediction data model
│   │   ├── model_info.dart               # Model version metadata
│   │   └── doctor.dart                   # Doctor user model
│   ├── screens/
│   │   ├── login_screen.dart             # Doctor ID authentication
│   │   ├── home_screen.dart              # X-ray upload & analysis
│   │   ├── result_screen.dart            # Results + share export
│   │   └── admin/
│   │       └── admin_dashboard.dart      # User mgmt, analytics, alerts
│   ├── services/
│   │   ├── auth_service.dart             # Firebase Auth wrapper
│   │   ├── classifier_service.dart       # Singleton TFLite inference
│   │   ├── image_service.dart            # Gallery image picker
│   │   ├── image_validation.dart         # Pre-inference file checks
│   │   └── result_export_service.dart    # Share analysis results
│   ├── widgets/
│   │   └── custom_drawer.dart            # Navigation drawer
│   └── theme/
│       └── app_theme.dart                # Medical-themed design system
├── assets/
│   └── model/
│       ├── densenet_pneumonia.tflite     # Trained DenseNet121 model
│       ├── labels.txt                    # Class labels (Normal, Pneumonia)
│       └── model_info.json               # Model name, version, input size
├── model/
│   ├── train_model.py                    # DenseNet121 training pipeline
│   ├── generate_placeholder_model.py     # Placeholder model generator
│   └── requirements.txt                  # Python dependencies
└── pubspec.yaml
```

## Features

- **Doctor Authentication** — Firebase Auth with Doctor ID lookup via Firestore
- **Admin Console** — User management, scan analytics, system alerts, audit logs
- **X-Ray Upload** — Pick chest X-ray images from gallery with validation
- **AI Analysis** — On-device DenseNet121 inference via TensorFlow Lite (singleton loader)
- **Results Display** — Animated confidence ring, Grad-CAM toggle, model version
- **Share Results** — Export summary + X-ray via system share sheet
- **Scan Logging** — Predictions saved to Firestore for analytics
- **Maintenance Mode** — Remote system lockout via Firestore settings
- **Dark Mode** — Light/dark theme toggle
- **Medical Disclaimer** — Educational use notice on all screens

## Getting Started

1. Ensure Flutter SDK is installed
2. Run `flutter pub get`
3. Configure Firebase (`firebase_options.dart`)
4. Place `densenet_pneumonia.tflite` in `assets/model/`
5. Run `flutter run`

## Model Training

```bash
cd model
pip install -r requirements.txt
python train_model.py --data_dir ./dataset --epochs_phase1 10 --epochs_phase2 10
```

The trained `densenet_pneumonia.tflite` model is automatically copied to `assets/model/`. Update `assets/model/model_info.json` when you retrain (version, description).

## Testing

```bash
flutter analyze
flutter test
```

## Disclaimer

This system is for **educational and support purposes only**. It is not a substitute for professional medical diagnosis. Always consult a qualified healthcare provider.
