# Scanaract: CV-Powered Cataract Detector

Scanaract is a low-cost, AI-powered cataract screening system designed for medically underserved regions. It integrates custom hardware (Raspberry Pi 4B + macro camera), a cross-platform Flutter mobile application, a Supabase database, and a deep learning model (ResNet50) deployed on Hugging Face.

## Repository Structure

```
FYP_Scanaract/
├── RaspberryPi-Hardware/ # Raspberry Pi server files
│ ├── app.py # Flask camera server
│ ├── Scanaract_Wifi.conf # Wi-Fi access point config
│ ├── camera-server.service # Auto-start on boot
│ └── requirements.txt # Python dependencies
│
├── Hybrid ViT/ # ViT-ResNet50 hybrid model
│ ├── Hybrid_result/ # Training results & outputs
│ ├── Yolo11/ # YOLO-based preprocessing workflow
│ ├── train_ResVit_attentionRe.py # Main training script
│ ├── compare_heatmap.py # Heatmap comparison (Grad-CAM)
│ └── readme.md # ViT-specific documentation
│
├── resnet50/ # ResNet50 model (selected for deployment)
│ ├── train_evaluate_models.py # Main training & evaluation script
│ ├── predict_custom_images.py # Inference on custom images
│ ├── requirements.txt # Python dependencies
│ ├── ResNet50_confusion_matrix.png # Confusion matrix visualization
│ ├── ResNet50_convergence.png # Training convergence plot
│ ├── ResNet50_metrics_summary.png # Metrics bar chart
│ ├── ResNet50_roc_curve.png # ROC curve with AUC
│ ├── comparison.png # Model comparison results
│ ├── custom_predictions.png # Sample predictions
│ └── readme.md # ResNet50-specific documentation
| └── for model, please download at https://drive.google.com/file/d/13rBgLFD9fbEoSDMaJ3C9BNjmM-BteV_C/view?usp=sharing
│
├── FYP_Frontend/ # Flutter mobile application
│ └── lib/ # Dart files (screens, widgets)
│
└── README.md # This file
```

## System Architecture

```
User → Goggles (RPi + Camera) → Wi-Fi → Flutter App → Supabase (Storage)
                                                          ↓
                                                    Hugging Face (AI)
                                                          ↓
                                              Result → App → User
```

## Hardware Requirements

- Raspberry Pi 4B
- USB macro camera (HXY-216 or compatible)
- LED lighting strip
- 3D-printed goggle housing
- Power bank (5V USB)

## Quick Setup

### 1. Raspberry Pi (Camera Server)

```bash
cd RaspberryPi-Hardware

# Install dependencies
pip3 install -r requirements.txt

# Setup Wi-Fi access point
sudo cp Scanaract_Wifi.conf /etc/NetworkManager/system-connections/
sudo chmod 600 /etc/NetworkManager/system-connections/Scanaract_Wifi.conf
sudo systemctl restart NetworkManager

# Setup auto-start service
sudo cp camera-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable camera-server.service
sudo systemctl start camera-server.service
```

**Wi-Fi Details:**
- SSID: `Scanaract_Wifi`
- Password: `scanaractpi`
- IP: `10.42.0.1:8081`

### 2. AI Model (ResNet50)

```bash
cd resnet50

# Train the model
python train.py --epochs 30 --batch_size 16 --lr 5e-5

# Evaluate
python evaluate.py --checkpoint best_model.pth

# Deploy to Hugging Face
python deploy.py --model best_model.pth --space perram27/cataract-detection
```

### 3. Mobile App (Flutter)

```bash
cd FYP_Frontend

# Get dependencies
flutter pub get

# Configure Supabase
# Update lib/supabase_config.dart with your project URL and anon key

# Run
flutter run
```

## API Endpoints (Raspberry Pi Server)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/capture_fast` | GET | Instant image capture |
| `/video_feed` | GET | Live MJPEG stream |
| `/photos` | GET | List all captured images |
| `/shutdown` | GET | Safely shutdown Pi |

## Model Performance

| Model | Accuracy | Precision | Recall |
|-------|----------|-----------|--------|
| ResNet50 | 100% | 100% | 95.54% |
| ViT Hybrid | 99.7% | 99.67% | 99.67% |

**ResNet50 selected for deployment** (prioritizing recall in medical screening)

## Database (Supabase)

**Tables:**
- `profiles` - User information (1:1 with auth.users)
- `examinations` - Scan history (health index, image URL, AI results)

**Storage Buckets:**
- `avatars` - User profile pictures
- `inspection_results` - Captured eye images

**Security:** Row Level Security (RLS) ensures users access only their own data.

## Cloud Deployment

- **Platform:** Hugging Face Spaces
- **Framework:** Gradio SDK


## Contributors

| Name | Role | Responsibilities |
|------|------|------------------|
| SHAH Pooja Zenit | Project Manager | Hardware, RPi config, integration |
| FU Yuhao | AI Researcher & Engineer | ResNet50 training, deployment |
| KE Yankai | Mobile Developer | Flutter app, Supabase |
| LI Xilin | AI Researcher & Engineer| ViT hybrid, YOLO preprocessing |

## License

Academic use only. For final year project COMP S456F at Hong Kong Metropolitan University.

## References

- [World Health Organization - Cataract](https://www.who.int/news-room/fact-sheets/detail/blindness-and-visual-impairment)
- [Hugging Face Model Space](https://huggingface.co/spaces/perram27/cataract-detection-api)
- [Supabase Documentation](https://supabase.com/docs)
- [Flutter Documentation](https://flutter.dev)
