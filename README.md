# AI-Based Pneumonia Detection

An AI-powered medical imaging project for detecting pneumonia from chest X-ray images. The repository combines a Flutter mobile application with a deep learning pipeline and a Python/FastAPI Grad-CAM inference server, making it useful for clinical screening support and model explainability.

## Overview

This project is designed to help identify pneumonia in chest X-ray images using a trained deep learning model. The app provides a user-friendly interface for clinicians or researchers to upload or inspect medical images, while the backend can generate Grad-CAM heatmaps to highlight the image regions that influenced the prediction.

## Project Structure

- `android/`, `ios/`, `linux/`, `macos/`, `windows/`, `web/` — platform-specific Flutter app folders
- `lib/` — Dart application source code
- `assets/` — app assets and model files
- `model/` — training, inference, and notebook scripts for the AI model
- `server/` — FastAPI backend for Grad-CAM inference
- `test/` — Flutter tests
- `pubspec.yaml` — Flutter package configuration and dependencies
- `firebase.json` — Firebase configuration

## Technologies Used

- Dart / Flutter for the cross-platform frontend
- Python / TensorFlow / Keras for model training and inference
- OpenCV, NumPy, and Pillow for image preprocessing
- FastAPI for the backend API
- Firebase for authentication and app services

## Installation

### Prerequisites

- Flutter SDK (3.10+ recommended)
- Dart SDK (included with Flutter)
- Python 3.9+ or newer
- A configured Firebase project (if using authentication and Firestore)
- Optional: Python virtual environment tool such as `venv` or `conda`

### 1. Clone the repository

```bash
git clone https://github.com/SheethHassan/AI-Based-Pneumonia-Detection.git
cd AI-Based-Pneumonia-Detection
```

### 2. Install Flutter dependencies

```bash
flutter pub get
```

Then run the app:

```bash
flutter run
```

### 3. Set up the Python model environment

```bash
cd model
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

The project includes training and inspection scripts in the `model/` directory, including:

- `train_model.py`
- `inspect_model.py`
- `generate_placeholder_model.py`
- `extract_dense_weights.py`
- `google_colab.py` / `google_colab.ipynb`

### 4. Start the backend API (optional)

The FastAPI service in `server/` provides Grad-CAM generation for uploaded X-ray images.

```bash
cd server
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

> Note: The backend expects a trained Keras model at `model/densenet_BEST_FINAL.keras`.

## Usage Examples

### Run the Flutter app

```bash
cd AI-Based-Pneumonia-Detection
flutter pub get
flutter run
```

### Run the training scripts in Python

```bash
cd model
python train_model.py
```

### Call the Grad-CAM API

```bash
curl -X POST "http://localhost:8000/gradcam" \
  -F "file=@/path/to/chest_xray.jpg"
```

This endpoint returns a base64-encoded Grad-CAM overlay image that can be displayed in the frontend or processed further.

## Configuration Details

The project includes several configuration points:

- `pubspec.yaml` defines Flutter dependencies and asset configuration.
- `lib/firebase_options.dart` contains Firebase platform configuration.
- `firebase.json` is used for Firebase deployment-related configuration.
- `server/main.py` expects the model path to be:

```python
MODEL_PATH = "../model/densenet_BEST_FINAL.keras"
```

- `pubspec.yaml` includes the app asset folder:

```yaml
flutter:
  assets:
    - assets/model/
```

A trained model file and dataset are not bundled in this repository, so you must provide or train the model separately before running inference.

## Contributing Guidelines

Contributions are welcome. If you would like to improve the project:

1. Fork the repository.
2. Create a feature branch.
3. Make your changes and test them locally.
4. Open a pull request with a clear description of the update.
5. Include any relevant screenshots, commands, or validation steps.

For bug reports or feature requests, please open an issue in the repository.

## License Information

No license file is currently present in this repository, so no explicit open-source license terms are defined for the project at this time.

## Code of Conduct / Citations

No formal code of conduct or academic citation file is currently included in the repository.

## Credits and Acknowledgments

This project makes use of the following technologies and libraries:

- Flutter and Dart
- TensorFlow / Keras
- OpenCV
- NumPy and Pillow
- FastAPI
- Firebase

The project is maintained under the GitHub account `SheethHassan` and is intended for medical AI research and prototype development.

## Troubleshooting and FAQs

### Flutter app fails to start

```bash
flutter clean
flutter pub get
flutter run
```

### Missing Python dependencies

```bash
python -m pip install --upgrade pip
pip install -r model/requirements.txt
```

### Server returns 503 or model errors

Check that the trained model exists at:

```text
model/densenet_BEST_FINAL.keras
```

If the file is missing, train the model or add the correct path to the backend configuration.

### Firebase configuration issues

Verify that the app has been configured for the correct platform and that the Firebase project is initialized correctly in `lib/firebase_options.dart`.

## Contact Information

For support, questions, or issues, please use the GitHub Issues page for this repository:

https://github.com/SheethHassan/AI-Based-Pneumonia-Detection/issues

No direct email or alternate support channel is currently listed in the repository.

## Changelog

A dedicated changelog file is not currently included in this repository. Version history can be tracked through repository commits and GitHub release notes.

## Summary

This project provides a complete prototype workflow for AI-based pneumonia detection using chest X-ray images: a Flutter frontend, Firebase integration, deep learning training pipelines, and a server-side Grad-CAM API for explainable AI. It is a strong foundation for research, clinical prototype development, and further extension into deployment-ready medical imaging systems.
