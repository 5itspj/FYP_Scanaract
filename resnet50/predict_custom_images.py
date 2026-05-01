"""
Inference script — ResNet50 + GradCAM on custom eye images.
Outputs:
  plots/custom_predictions.png  — prediction grid
  plots/gradcam_grid.png        — GradCAM heatmap overlays
Usage:
    python predict_custom_images.py
"""

from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn as nn
from torchvision import transforms
from torchvision.models import resnet50
from PIL import Image
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from torchcam.methods import GradCAM
from torchcam.utils import overlay_mask
from torchvision.transforms.functional import to_pil_image

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────
IMAGE_DIR   = Path("try_images")
CHECKPOINT  = Path("saved_models/ResNet50_v20260415_2219_acc0.9796.pth")
CLASS_NAMES = ["cataract", "normal"]  # index 0=cataract, 1=normal (ImageFolder alphabetical)
IMG_SIZE    = 224
THRESHOLD   = 0.5                     # sigmoid >= 0.5 → normal, < 0.5 → cataract
COLOR       = {"cataract": "#e74c3c", "normal": "#2ecc71"}

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {DEVICE}")

# ─────────────────────────────────────────────
# Model
# ─────────────────────────────────────────────
def build_resnet50():
    model = resnet50(weights=None)
    in_features = model.fc.in_features
    model.fc = nn.Sequential(
        nn.Linear(in_features, 256),
        nn.ReLU(),
        nn.Dropout(0.5),
        nn.Linear(256, 1),
    )
    return model

model = build_resnet50()
ckpt  = torch.load(CHECKPOINT, map_location=DEVICE)
model.load_state_dict(ckpt["model_state"])
model = model.to(DEVICE)
model.eval()
print(f"Loaded checkpoint: {CHECKPOINT}\n")

# ─────────────────────────────────────────────
# Transform — identical to test set during training
# ─────────────────────────────────────────────
transform = transforms.Compose([
    transforms.Resize((IMG_SIZE, IMG_SIZE)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406],
                         std=[0.229, 0.224, 0.225]),
])

# ─────────────────────────────────────────────
# Eye-region crop via Hough circle detection
# ─────────────────────────────────────────────
def crop_eye_region(pil_img: Image.Image) -> Image.Image:
    img_bgr = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
    h, w    = img_bgr.shape[:2]
    gray    = cv2.equalizeHist(cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY))

    circles = cv2.HoughCircles(
        gray, cv2.HOUGH_GRADIENT,
        dp=1.2, minDist=min(h, w) * 0.3,
        param1=60, param2=35,
        minRadius=int(min(h, w) * 0.15),
        maxRadius=int(min(h, w) * 0.55),
    )

    if circles is not None:
        circles = np.round(circles[0]).astype(int)
        cx, cy, r = min(circles,
                        key=lambda c: (c[0] - w // 2) ** 2 + (c[1] - h // 2) ** 2)
        pad = int(r * 1.4)
        x1, y1 = max(cx - pad, 0), max(cy - pad, 0)
        x2, y2 = min(cx + pad, w), min(cy + pad, h)
    else:
        size = int(min(h, w) * 0.75)
        x1, y1 = (w - size) // 2, (h - size) // 2
        x2, y2 = x1 + size, y1 + size

    cropped = img_bgr[y1:y2, x1:x2]
    return Image.fromarray(cv2.cvtColor(cropped, cv2.COLOR_BGR2RGB))

# ─────────────────────────────────────────────
# Collect images
# ─────────────────────────────────────────────
SUPPORTED   = {".png", ".jpg", ".jpeg", ".bmp", ".tiff"}
image_paths = sorted([p for p in IMAGE_DIR.iterdir()
                      if p.suffix.lower() in SUPPORTED
                      and p.name.startswith("image_")])

if not image_paths:
    raise FileNotFoundError(f"No images found in {IMAGE_DIR}")

print(f"Found {len(image_paths)} image(s).\n")

# ─────────────────────────────────────────────
# Inference + GradCAM
# ─────────────────────────────────────────────
# GradCAM on ResNet50's last conv block
cam_extractor = GradCAM(model, target_layer="layer4")

results = []  # (img_path, pred_name, confidence, cropped_pil, cam_overlay)

for img_path in image_paths:
    pil_img = Image.open(img_path).convert("RGB")
    cropped = crop_eye_region(pil_img)
    tensor  = transform(cropped).unsqueeze(0).to(DEVICE)

    # Forward (no torch.no_grad — GradCAM needs the graph)
    logit = model(tensor).squeeze(0)        # shape [1]
    prob  = torch.sigmoid(logit).item()     # P(normal)

    # Prediction: sigmoid < 0.5 → cataract (idx 0), >= 0.5 → normal (idx 1)
    pred_idx   = 1 if prob >= THRESHOLD else 0
    pred_name  = CLASS_NAMES[pred_idx]
    confidence = prob if pred_idx == 1 else 1.0 - prob

    # GradCAM — binary model outputs single logit, no class_idx needed
    model.zero_grad()
    cam_map    = cam_extractor(class_idx=0, scores=logit.unsqueeze(0).unsqueeze(0))
    cam_tensor = cam_map[0].squeeze()       # [H, W]

    resized = cropped.resize((IMG_SIZE, IMG_SIZE))
    overlay = overlay_mask(
        resized,
        to_pil_image(cam_tensor, mode="F"),
        alpha=0.5,
        colormap="jet",
    )

    results.append((img_path, pred_name, confidence, resized, overlay))
    print(f"  {img_path.name:<20}  →  {pred_name:<10}  (confidence: {confidence:.1%})")

cam_extractor.remove_hooks()

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
n_cat = sum(1 for _, c, *_ in results if c == "cataract")
n_nor = sum(1 for _, c, *_ in results if c == "normal")
print(f"\n{'─'*50}")
print(f"Total   : {len(results)}")
print(f"Cataract: {n_cat}  |  Normal: {n_nor}")
print(f"{'─'*50}")

Path("plots").mkdir(exist_ok=True)

# ─────────────────────────────────────────────
# Plot 1 — prediction grid (cropped originals)
# ─────────────────────────────────────────────
ncols = 4
nrows = (len(results) + ncols - 1) // ncols
fig, axes = plt.subplots(nrows, ncols, figsize=(ncols * 4, nrows * 4))
axes = axes.flatten()

for ax, (img_path, pred_name, confidence, resized, _) in zip(axes, results):
    ax.imshow(resized)
    ax.set_title(f"{img_path.name}\n{pred_name}  ({confidence:.1%})",
                 color=COLOR[pred_name], fontsize=9, fontweight="bold")
    for spine in ax.spines.values():
        spine.set_edgecolor(COLOR[pred_name])
        spine.set_linewidth(3)
    ax.set_xticks([]); ax.set_yticks([])

for ax in axes[len(results):]:
    ax.set_visible(False)

legend_patches = [mpatches.Patch(color="#e74c3c", label="Cataract"),
                  mpatches.Patch(color="#2ecc71", label="Normal")]
fig.legend(handles=legend_patches, loc="lower center", ncol=2,
           fontsize=11, bbox_to_anchor=(0.5, 0.0))
plt.suptitle("ResNet50 — Cataract Detection on Custom Images", fontsize=13)
plt.tight_layout()
out1 = Path("plots/custom_predictions.png")
plt.savefig(out1, dpi=150, bbox_inches="tight")
plt.close()
print(f"\nSaved → {out1}")

# ─────────────────────────────────────────────
# Plot 2 — GradCAM grid (original row + heatmap row per batch)
# ─────────────────────────────────────────────
fig, axes = plt.subplots(nrows * 2, ncols, figsize=(ncols * 4, nrows * 8))
axes = axes.reshape(nrows * 2, ncols)

for idx, (img_path, pred_name, confidence, resized, overlay) in enumerate(results):
    r_orig = (idx // ncols) * 2
    r_cam  = r_orig + 1
    col    = idx % ncols

    axes[r_orig][col].imshow(resized)
    axes[r_orig][col].set_title(img_path.name, fontsize=8)
    axes[r_orig][col].set_xticks([]); axes[r_orig][col].set_yticks([])

    axes[r_cam][col].imshow(overlay)
    axes[r_cam][col].set_title(f"{pred_name}  ({confidence:.1%})",
                                color=COLOR[pred_name], fontsize=9, fontweight="bold")
    for spine in axes[r_cam][col].spines.values():
        spine.set_edgecolor(COLOR[pred_name])
        spine.set_linewidth(3)
    axes[r_cam][col].set_xticks([]); axes[r_cam][col].set_yticks([])

for idx in range(len(results), nrows * ncols):
    r_orig = (idx // ncols) * 2
    axes[r_orig][idx % ncols].set_visible(False)
    axes[r_orig + 1][idx % ncols].set_visible(False)

fig.legend(handles=legend_patches, loc="lower center", ncol=2,
           fontsize=11, bbox_to_anchor=(0.5, 0.0))
plt.suptitle("ResNet50 — GradCAM  (top: original  |  bottom: heatmap)", fontsize=13)
plt.tight_layout()
out2 = Path("plots/gradcam_grid.png")
plt.savefig(out2, dpi=150, bbox_inches="tight")
plt.close()
print(f"Saved → {out2}")
