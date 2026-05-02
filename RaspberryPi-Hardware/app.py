#!/usr/bin/env python3
from flask import Flask, jsonify, send_file, request, Response, render_template_string
from flask_cors import CORS
import os
import subprocess
from datetime import datetime
import cv2
import time
import threading
import numpy as np

app = Flask(__name__)
CORS(app)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_FOLDER = os.path.join(BASE_DIR, 'static/photos')

if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

# Global camera object
camera = None
camera_lock = threading.Lock()
current_frame = None
last_frame_for_capture = None

def get_camera():
    global camera
    if camera is not None:
        return camera
    with camera_lock:
        if camera is None:
            for i in range(3):
                cam = cv2.VideoCapture(i, cv2.CAP_V4L2)
                if cam.isOpened():
                    cam.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
                    cam.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
                    camera = cam
                    print(f"✅ Camera initialized at /dev/video{i}")
                    return camera
            print("⚠️ Camera not found")
            return None
    return camera

def capture_frames():
    global current_frame, last_frame_for_capture
    while True:
        cam = get_camera()
        if cam is None:
            time.sleep(1)
            continue
        try:
            with camera_lock:
                ret, frame = cam.read()
                if ret and frame is not None:
                    current_frame = frame.copy()
                    # Store a copy for instant capture
                    last_frame_for_capture = frame.copy()
        except Exception as e:
            print(f"Stream error: {e}")
        time.sleep(0.033)  # ~30fps

def generate_frames():
    while True:
        if current_frame is not None:
            with camera_lock:
                ret, buffer = cv2.imencode('.jpg', current_frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
                if ret:
                    yield (b'--frame\r\n'
                           b'Content-Type: image/jpeg\r\n\r\n' + buffer.tobytes() + b'\r\n')
        time.sleep(0.033)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Eye Scan Camera</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: Arial; background: #f0f8ff; padding: 20px; text-align: center; }
        .container { max-width: 800px; margin: 0 auto; }
        .stream-container { background: #000; border-radius: 20px; padding: 10px; margin-bottom: 20px; }
        img { max-width: 100%; border-radius: 10px; }
        button { padding: 15px 30px; font-size: 18px; margin: 10px; cursor: pointer; border: none; border-radius: 30px; font-weight: bold; }
        .capture { background: #4a90e2; color: white; }
        .shutdown { background: #dc3545; color: white; }
        .gallery { display: flex; flex-wrap: wrap; gap: 15px; margin-top: 20px; justify-content: center; }
        .photo-card { width: 180px; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.15); background: white; }
        .photo-card img { width: 100%; height: 140px; object-fit: cover; cursor: pointer; }
        .photo-info { padding: 8px; display: flex; justify-content: space-between; align-items: center; font-size: 11px; }
        .delete-btn { background: #dc3545; color: white; border: none; border-radius: 15px; padding: 4px 12px; cursor: pointer; font-size: 11px; }
        .delete-btn:hover { background: #c82333; }
        .status { padding: 10px; margin: 10px; border-radius: 10px; display: inline-block; }
        .success { background: #d4edda; color: #155724; }
        .error { background: #f8d7da; color: #721c24; }
        .info { background: #d1ecf1; color: #0c5460; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📷 Eye Scan Camera</h1>
        
        <div class="stream-container">
            <img id="stream" src="/video_feed">
        </div>
        
        <div>
            <button class="capture" onclick="capture()">📸 Capture Photo</button>
            <button class="shutdown" onclick="shutdownPi()">🔌 Shutdown Pi</button>
        </div>
        
        <div id="result"></div>
        
        <h2>📸 Photo Gallery</h2>
        <div id="gallery" class="gallery"></div>
    </div>
    
    <script>
        async function capture() {
            const resultDiv = document.getElementById('result');
            resultDiv.innerHTML = '<div class="status info">📸 Capturing... hold still!</div>';
            
            try {
                const response = await fetch('/capture_fast');
                const data = await response.json();
                
                if(data.success) {
                    resultDiv.innerHTML = '<div class="status success">✅ Photo captured! ' + data.filename + '</div>';
                    loadGallery();
                } else {
                    resultDiv.innerHTML = '<div class="status error">❌ Error: ' + data.error + '</div>';
                }
            } catch(e) {
                resultDiv.innerHTML = '<div class="status error">❌ Connection error</div>';
            }
        }
        
        async function shutdownPi() {
            if(confirm('⚠️ WARNING: This will shut down the Raspberry Pi. Continue?')) {
                const resultDiv = document.getElementById('result');
                resultDiv.innerHTML = '<div class="status info">🔄 Shutting down Pi...</div>';
                
                try {
                    await fetch('/shutdown');
                    resultDiv.innerHTML = '<div class="status success">✅ Pi is shutting down. You can unplug power after 30 seconds.</div>';
                } catch(e) {
                    resultDiv.innerHTML = '<div class="status success">✅ Pi is shutting down. You can unplug power after 30 seconds.</div>';
                }
            }
        }
        
        async function deletePhoto(filename) {
            if(!confirm('Delete this photo?')) return;
            
            try {
                const response = await fetch('/delete/' + filename, { method: 'DELETE' });
                const data = await response.json();
                if(data.success) {
                    loadGallery();
                } else {
                    alert('Delete failed: ' + data.error);
                }
            } catch(e) {
                alert('Delete failed');
            }
        }
        
        async function loadGallery() {
            const gallery = document.getElementById('gallery');
            gallery.innerHTML = '<div class="status info">Loading...</div>';
            
            try {
                const response = await fetch('/photos');
                const photos = await response.json();
                
                if(photos.length === 0) {
                    gallery.innerHTML = '<div class="status info">No photos yet. Take your first capture!</div>';
                    return;
                }
                
                gallery.innerHTML = '';
                // Show newest first (reverse order)
                photos.reverse().forEach(photo => {
                    const card = document.createElement('div');
                    card.className = 'photo-card';
                    card.innerHTML = `
                        <img src="/${photo.url}" onclick="window.open('/${photo.url}', '_blank')">
                        <div class="photo-info">
                            <span>${photo.filename.replace('photo_', '').replace('.jpg', '')}</span>
                            <button class="delete-btn" onclick="deletePhoto('${photo.filename}')">🗑 Delete</button>
                        </div>
                    `;
                    gallery.appendChild(card);
                });
            } catch(e) {
                gallery.innerHTML = '<div class="status error">Failed to load gallery</div>';
            }
        }
        
        // Auto-refresh gallery every 5 seconds
        loadGallery();
        setInterval(loadGallery, 5000);
    </script>
</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/video_feed')
def video_feed():
    return Response(generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/capture_fast')
def capture_fast():
    """INSTANT capture - uses the last frame from the stream"""
    global last_frame_for_capture
    
    try:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"photo_{timestamp}.jpg"
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)

        # Use the last frame from the stream for instant capture
        with camera_lock:
            if last_frame_for_capture is None:
                return jsonify({'success': False, 'error': 'No frame available'})
            
            # Use the frame we already have (what you see on screen)
            frame = last_frame_for_capture.copy()
        
        # Save at stream resolution (fast) - or optionally upscale
        cv2.imwrite(filepath, frame)
        
        return jsonify({
            'success': True, 
            'filename': filename, 
            'url': f'static/photos/{filename}'
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

# Keep original capture endpoint for compatibility
@app.route('/capture')
def capture_photo():
    return capture_fast()

@app.route('/photos')
def list_photos():
    photos = []
    if os.path.exists(UPLOAD_FOLDER):
        for f in sorted(os.listdir(UPLOAD_FOLDER)):
            if f.endswith('.jpg'):
                photos.append({'filename': f, 'url': f'static/photos/{f}'})
    return jsonify(photos)

@app.route('/static/photos/<filename>')
def get_photo(filename):
    return send_file(os.path.join(app.config['UPLOAD_FOLDER'], filename))

@app.route('/delete/<filename>', methods=['DELETE'])
def delete_photo(filename):
    """Delete a specific photo"""
    try:
        filename = os.path.basename(filename)  # Security: prevent path traversal
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        
        if os.path.exists(filepath):
            os.remove(filepath)
            return jsonify({'success': True})
        else:
            return jsonify({'success': False, 'error': 'File not found'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/shutdown')
def shutdown_pi():
    """Safely shuts down the Raspberry Pi"""
    try:
        # Use flush=True to ensure response is sent before shutdown
        response = jsonify({'success': True, 'message': 'Pi is shutting down'})
        # Shutdown after a short delay to allow response to be sent
        subprocess.Popen(['sudo', 'shutdown', '-h', 'now'], shell=False)
        return response
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

if __name__ == '__main__':
    print("\n" + "="*50)
    print("🚀 Scanaract Camera Server Starting...")
    print("="*50)
    print("📱 Connect to Scanaract_Wifi (password: scanaractpi)")
    print("🌐 Open http://10.42.0.1:8081 on your phone")
    print("📸 Capture is INSTANT - takes what you see on screen!")
    print("🔌 Use the 'Shutdown Pi' button to safely power off")
    print("="*50 + "\n")
    
    # Start background frame capture thread
    thread = threading.Thread(target=capture_frames, daemon=True)
    thread.start()
    
    app.run(host='0.0.0.0', port=8081, debug=False, threaded=True)
