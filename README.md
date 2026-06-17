# Pneumonia Detection App

A Flutter mobile application that uses deep learning to detect pneumonia from chest X-ray images.

---

## 📱 Overview

This project combines mobile development and machine learning to create an intelligent pneumonia detection system. Users can upload chest X-ray images to the mobile app, and the on-device AI model will analyze them to detect the presence of pneumonia.

---

## 🏗️ Project Structure

| Branch | Purpose | Language |
|--------|---------|----------|
| `FLUTTER_FRONTEND` | Mobile application UI & user interactions | Dart |
| `ML-MODEL` | Model training & experimentation | Python/Colab |

---

## 🛠️ Tech Stack

### Frontend
- **Flutter** — Cross-platform mobile framework
- **Firebase** — Authentication & backend services

### Machine Learning
- **TensorFlow & Keras** — Model training & development
- **MobileNetV2** — Pre-trained architecture for efficient inference
- **TensorFlow Lite** — On-device inference for mobile

---

## 📊 Dataset

**Source:** [Kaggle Chest X-Ray Images (Pneumonia)](https://www.kaggle.com/datasets/paultimothymooney/chest-xray-pneumonia)

The dataset contains labeled chest X-ray images for training and validation.

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK
- Python 3.8+ (for model training)
- TensorFlow & Keras
- Kaggle API access (for dataset download)

### Installation

#### Clone the Repository
```bash
git clone https://github.com/SheethHassan/AI-Based-Pneumonia-Detection.git
cd AI-Based-Pneumonia-Detection
```

#### Flutter Frontend
```bash
git checkout FLUTTER_FRONTEND
flutter pub get
flutter run
```

#### ML Model Development
```bash
git checkout ML-MODEL
pip install -r requirements.txt
jupyter notebook
```

---

## 📈 Model Performance

*(Add your model accuracy, precision, recall, and F1-score metrics here)*

---

## 🤝 Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your improvements.

---

## 📝 License

This project is open source and available under the [MIT License](LICENSE).

---

## 📧 Contact

For questions or feedback, please open an issue on GitHub.
