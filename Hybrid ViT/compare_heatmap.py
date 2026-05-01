import os
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"
import torch
import torch.nn as nn
import torch.nn.functional as F
import timm
import pandas as pd
from PIL import Image
from torchvision import transforms
import numpy as np
import cv2
import math
from pytorch_grad_cam import GradCAM
from pytorch_grad_cam.utils.image import show_cam_on_image

def reshape_transform(tensor, height=14, width=14):
    # tensor shape: [batch, num_tokens, dim]
    result = tensor[:, 1:, :].reshape(tensor.size(0), height, width, tensor.size(2))
    result = result.transpose(2, 3).transpose(1, 2)
    return result

# Create a single data tile
def create_tile(orig_bgr, heatmap_bgr, actual_class, pred_class, confidence):
    img_col = np.vstack((orig_bgr, heatmap_bgr))
    text_panel = np.ones((448, 250, 3), dtype=np.uint8) * 255

    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.6
    thickness = 1
    
    # Write Actual Class
    cv2.putText(text_panel, "Actual:", (10, 60), font, font_scale, (0, 0, 0), thickness)
    cv2.putText(text_panel, actual_class, (10, 90), font, font_scale, (0, 0, 0), thickness+1)
    if actual_class != pred_class:
        pred_color = (0, 0, 255)
    else:
        pred_color = (0, 150, 0)
        
    cv2.putText(text_panel, "Predicted:", (10, 180), font, font_scale, (0, 0, 0), thickness)
    cv2.putText(text_panel, pred_class, (10, 210), font, font_scale, pred_color, thickness+1)
    
    # Write Confidence
    cv2.putText(text_panel, "Confidence:", (10, 300), font, font_scale, (0, 0, 0), thickness)
    cv2.putText(text_panel, f"{confidence:.4f}", (10, 330), font, font_scale, (0, 0, 0), thickness)
    tile = np.hstack((img_col, text_panel))
    return tile

def create_grid(tiles, cols=3):
    if not tiles:
        return None
    num_tiles = len(tiles)
    rows = math.ceil(num_tiles / cols)
    tile_h, tile_w, _ = tiles[0].shape
    grid_w = cols * tile_w
    grid_h = rows * tile_h
    grid = np.ones((grid_h, grid_w, 3), dtype=np.uint8) * 255
    for idx, tile in enumerate(tiles):
        r = idx // cols
        c = idx % cols
        y = r * tile_h
        x = c * tile_w
        grid[y:y+tile_h, x:x+tile_w] = tile
        
    return grid


def main():
    # 配置参数
    image_folder = 'F:/Cataract-Detection-System/crop/try_image'
    model_weight_path = 'run_20260414_0602/vit_cataract_model.pth'
    output_csv_path = 'try_result/compare.csv' 
    
    heatmap_folder = 'try_result/compare' 
    os.makedirs(heatmap_folder, exist_ok=True)

    class_names = ['cataract', 'normal']
    num_classes = len(class_names)
    device = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")

    transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406],
                             std=[0.229, 0.224, 0.225])
    ])

    print("Loading model")
    model = timm.create_model('vit_base_r50_s16_224.orig_in21k', pretrained=False, num_classes=num_classes)
    model.load_state_dict(torch.load(model_weight_path, map_location=device))
    model = model.to(device)
    model.eval()

    target_layers = [model.blocks[-1].norm1]
    cam = GradCAM(model=model, target_layers=target_layers, reshape_transform=reshape_transform)

    supported_formats = ('.png', '.jpg', '.jpeg', '.bmp', '.tiff')
    results = []
    tiles_collection = []
    image_files = [f for f in os.listdir(image_folder) if f.lower().endswith(supported_formats)]
    
    if not image_files:
        print("No images found in the specified folder!")
        return
        
    print(f"Found {len(image_files)} images. Starting prediction and heatmap generation...")
    
    for img_name in image_files:
        img_path = os.path.join(image_folder, img_name)
        if "image_01" in img_name:
            actual_class = "cataract"
        else:
            actual_class = "normal"
        try:
            image = Image.open(img_path).convert('RGB')
            img_tensor = transform(image).unsqueeze(0).to(device) 
            
            with torch.no_grad():
                outputs = model(img_tensor)
                probabilities = F.softmax(outputs, dim=1)
                confidence, predicted_idx = torch.max(probabilities, 1)
                predicted_class = class_names[predicted_idx.item()]
                confidence_score = confidence.item()

            results.append({
                'File Name': img_name,
                'Actual Class': actual_class,
                'Predicted Class': predicted_class,
                'confidence': round(confidence_score, 4)
            })
            print(f"Processed: {img_name} -> {predicted_class} (Confidence: {confidence_score:.4f})")
            
            grayscale_cam = cam(input_tensor=img_tensor, targets=None)[0, :]
            
            img_cv = cv2.imread(img_path)
            orig_bgr = cv2.resize(img_cv, (224, 224))
            rgb_img = cv2.cvtColor(orig_bgr, cv2.COLOR_BGR2RGB) / 255.0
            
            visualization = show_cam_on_image(rgb_img, grayscale_cam, use_rgb=True)
            heatmap_bgr = cv2.cvtColor(visualization, cv2.COLOR_RGB2BGR)
            heatmap_path = os.path.join(heatmap_folder, f"heatmap_{img_name}")
            cv2.imwrite(heatmap_path, heatmap_bgr)
            tile = create_tile(orig_bgr, heatmap_bgr, actual_class, predicted_class, confidence_score)
            tiles_collection.append(tile)

        except Exception as e:
            print(f"Error processing {img_name}: {e}")
            results.append({
                'File Name': img_name,
                'Actual Class': actual_class,
                'Predicted Class': 'ERROR',
                'confidence': None
            })

    if tiles_collection:
        print("Generating combined results image")
        combined_grid = create_grid(tiles_collection, cols=3)
        combined_img_path = os.path.join(heatmap_folder, "all_results_combined.jpg")
        cv2.imwrite(combined_img_path, combined_grid)
        print(f"Combined image saved to '{combined_img_path}'")

    df = pd.DataFrame(results)
    df.to_csv(output_csv_path, index=False)
    print(f"\nResults saved to '{output_csv_path}'.")
    print(f"Heatmaps saved to '{heatmap_folder}'.")

if __name__ == '__main__':
    main()