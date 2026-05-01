import os
import cv2
import numpy as np
from pathlib import Path
from ultralytics import YOLO

def crop_eyes_for_vit(model_path, input_dir, output_dir, margin_ratio=0.1, make_square=True):
    # Initialization
    in_path = Path(input_dir)
    out_path = Path(output_dir)
    out_path.mkdir(parents=True, exist_ok=True)
    
    print(f"Loading model from {model_path}")
    model = YOLO(model_path)  # Load YOLO model
    
    valid_extensions = {'.jpg', '.jpeg', '.png', '.bmp'}
    image_files = [f for f in in_path.iterdir() if f.suffix.lower() in valid_extensions]
    print(f"Found {len(image_files)} images in {input_dir}")
    success_count = 0
    fail_count = 0

    for img_file in image_files:
        # Reading images using cv2
        img = cv2.imread(str(img_file))
        if img is None:
            print(f"Warning: Could not read {img_file.name}")
            continue
        h, w, _ = img.shape
        
        # Get YOLO prediction bounding boxes
        results = model.predict(source=img, conf=0.5, verbose=False)
        boxes = results[0].boxes

        if len(boxes) == 0:
            print(f"No detection found in: {img_file.name}")
            fail_count += 1
            continue
            
        # If multiple targets are detected, select the one with the highest confidence level.
        best_box = None
        highest_conf = -1.0
        for box in boxes:
            conf = float(box.conf[0])
            if conf > highest_conf:
                highest_conf = conf
                best_box = box.xyxy[0].cpu().numpy()

        x1, y1, x2, y2 = best_box # [x1, y1, x2, y2]
        
        # Calculate the width, height, and center point of the original bounding box.
        box_w = x2 - x1
        box_h = y2 - y1
        center_x = x1 + box_w / 2
        center_y = y1 + box_h / 2
        # Add safety margin
        pad_w = box_w * margin_ratio
        pad_h = box_h * margin_ratio
        
        if make_square:
            side_length = max(box_w + pad_w * 2, box_h + pad_h * 2)
            new_x1 = int(center_x - side_length / 2)
            new_y1 = int(center_y - side_length / 2)
            new_x2 = int(center_x + side_length / 2)
            new_y2 = int(center_y + side_length / 2)
        else:
            new_x1 = int(x1 - pad_w)
            new_y1 = int(y1 - pad_h)
            new_x2 = int(x2 + pad_w)
            new_y2 = int(y2 + pad_h)
            
        # Outbound truncation
        new_x1 = max(0, new_x1)
        new_y1 = max(0, new_y1)
        new_x2 = min(w, new_x2)
        new_y2 = min(h, new_y2)
        
        # Twice check
        if new_x2 <= new_x1 or new_y2 <= new_y1:
            print(f"Invalid crop box for {img_file.name}")
            fail_count += 1
            continue

        # Clipping
        cropped_img = img[new_y1:new_y2, new_x1:new_x2]
        
        save_path = out_path / img_file.name
        cv2.imwrite(str(save_path), cropped_img)
        success_count += 1

    print(f"Successfully cropped: {success_count}")
    print(f"Failed/No detection: {fail_count}")

# Path settings
if __name__ == "__main__":
    YOLO_MODEL_PATH = r"F:/Cataract-Detection-System/Yolo11/runs/detect/yolo11_ip_ver1/weights/best.pt"
    INPUT_DATASET_DIR = r"F:/Cataract-Detection-System/ours"
    OUTPUT_CROPPED_DIR = r"F:/Cataract-Detection-System/crop/ours"
    
    crop_eyes_for_vit(
        model_path=YOLO_MODEL_PATH,
        input_dir=INPUT_DATASET_DIR,
        output_dir=OUTPUT_CROPPED_DIR,
        margin_ratio=0.1,
        make_square=True
    )