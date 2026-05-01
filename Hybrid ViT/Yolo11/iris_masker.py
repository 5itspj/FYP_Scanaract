import cv2
import numpy as np
import os
import glob
import argparse

def isolate_iris_pupil(image_path, output_path):
    img = cv2.imread(image_path)
    if img is None:
        return False
        
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    blurred = cv2.medianBlur(gray, 7)
    
    # Hough Circle Transform
    circles = cv2.HoughCircles(
        blurred, 
        cv2.HOUGH_GRADIENT, 
        dp=1.2, 
        minDist=100, 
        param1=50,   
        param2=30,   
        minRadius=int(img.shape[0] * 0.2), 
        maxRadius=int(img.shape[0] * 0.45) 
    )
    
    if circles is not None:
        circles = np.uint16(np.around(circles))
        center_x, center_y, radius = circles[0, 0]

        mask = np.zeros_like(gray)
        cv2.circle(mask, (center_x, center_y), radius, 255, thickness=-1)
        result = cv2.bitwise_and(img, img, mask=mask)
        cv2.imwrite(output_path, result)
        return True
    else:
        cv2.imwrite(output_path, img) 
        return False

def process_dataset(input_dir, output_dir):
    os.makedirs(output_dir, exist_ok=True)

    extensions = ['*.jpg', '*.jpeg', '*.png', '*.JPG', '*.PNG']
    images = []
    for ext in extensions:
        images.extend(glob.glob(os.path.join(input_dir, ext)))
        
    if len(images) == 0:
        print(f"Error: No images found in '{input_dir}'")
        return

    print(f"Found {len(images)} images in '{input_dir}'. Starting process...")
    
    success_count = 0
    for i, img_path in enumerate(images):
        filename = os.path.basename(img_path)
        out_path = os.path.join(output_dir, filename)
        
        if isolate_iris_pupil(img_path, out_path):
            success_count += 1
            
        if (i + 1) % 100 == 0 or (i + 1) == len(images):
            print(f"Processed: {i + 1}/{len(images)}")
            
    print("-" * 30)
    print("Processing Complete!")
    print(f"Total Images: {len(images)}")
    print(f"Successfully Masked: {success_count}")
    print(f"Failed to find circle (kept original): {len(images) - success_count}")
    print(f"Output saved to: {output_dir}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Iris/Pupil Masker for Cataract Dataset")
    parser.add_argument('input', type=str, required=True, help="Path to the input directory containing cropped eye images")
    parser.add_argument('output', type=str, required=True, help="Path to the output directory to save masked images")
    
    args = parser.parse_args()
    
    process_dataset(args.input, args.output)