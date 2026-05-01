# Cataract Detection with ResNet50

## Overview
This repository implements a **ResNet50-based deep learning model** for cataract detection.  
It leverages transfer learning from ImageNet, applies domain-specific preprocessing, and integrates staged fine-tuning to achieve robust diagnostic performance.  
The code includes training, evaluation, visualization, and deployment routines, designed for reproducibility and integration with cloud services such as Hugging Face.

---

## Features
- **Preprocessing Pipeline**
  - Hough Circle Transform for ocular localization
  - Dynamic cropping of the crystalline lens (ROI)
  - Data augmentation (rotation, flipping, color jittering)
  - Normalization aligned with ImageNet standards

- **Model Architecture**
  - ResNet50 backbone with pretrained ImageNet weights
  - Custom classification head with dropout regularization
  - Staged fine-tuning strategy (warm-up + gradual unfreezing of deeper layers)

- **Training Workflow**
  - Mixed precision training (`torch.amp.autocast`, `GradScaler`)
  - AdamW optimizer with weight decay
  - CosineAnnealingLR scheduler for learning rate management
  - Automatic checkpoint saving (timestamped + “latest” version)

- **Evaluation & Visualization**
  - Accuracy, Precision, Recall, F1-score, ROC-AUC
  - Confusion matrix (counts + normalized)
  - ROC curve with AUC
  - Convergence plots for loss and accuracy
  - Metrics summary bar chart

- **Deployment**
  - Model artifacts saved in `.pth` format
  - Hugging Face cloud integration for scalable inference
  - Flask server compatibility for local testing and Supabase database integration

---

## Requirements
- Python 3.9+
- PyTorch 2.0+
- Torchvision
- NumPy
- Matplotlib
- Seaborn
- scikit-learn

Install dependencies:
```bash
pip install torch torchvision numpy matplotlib seaborn scikit-learn
