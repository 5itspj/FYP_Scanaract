
# Scanaract - Raspberry Pi Camera Server

Raspberry Pi components for Scanaract: Wi-Fi access point, Flask camera server, and auto-start service.

## Requirements 
- Raspberry Pi 4B
- Raspberry Pi OS
- USB Macro Camera
- Python 3.7+
  
## Files

| File | Purpose |
|------|---------|
| `app.py` | Flask server for camera capture and video stream |
| `Scanaract_Wifi.conf` | Wi-Fi access point configuration |
| `camera-server.service` | Auto-start Flask server on boot |
| `requirements.txt` | Python dependencies |

## Quick Setup

```bash
# 1. Install dependencies
pip3 install -r requirements.txt

# 2. Setup Wi-Fi access point
sudo cp Scanaract_Wifi.conf /etc/NetworkManager/system-connections/
sudo chmod 600 /etc/NetworkManager/system-connections/Scanaract_Wifi.conf
sudo systemctl restart NetworkManager

# 3. Setup auto-start service
sudo cp camera-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable camera-server.service
sudo systemctl start camera-server.service
```
## Network Details
- SSID: ```Scanaract_Wifi```
- Password: ```scanaractpi```
- IP Address: ```10.42.0.1```

## Usage
1. Connect to ```Scanaract_Wifi``` from your device
2. Open browser to ```http://10.42.0.1:8081```
3. Use capture button or API Endpoint ```/capture_fast```

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `/capture_fast` | Instant image capture |
| `/video_feed` | Live video stream |
| `/photos` | List all captured images |
| `/shutdown` | Safely shutdown Pi |


