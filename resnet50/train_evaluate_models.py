import time
from datetime import datetime
from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns

import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader
from torchvision import datasets, transforms
from torchvision.models import resnet50, ResNet50_Weights

from sklearn.metrics import (
    accuracy_score, precision_score, recall_score, f1_score,
    roc_auc_score, confusion_matrix, classification_report,
    roc_curve, auc,
)

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────
DATA_DIR  = Path("Dataset/processed_images")
TRAIN_DIR = DATA_DIR / "train"
TEST_DIR  = DATA_DIR / "test"
SAVE_DIR  = Path("saved_models")
PLOT_DIR  = Path("plots")

SAVE_DIR.mkdir(exist_ok=True)
PLOT_DIR.mkdir(exist_ok=True)

IMG_SIZE   = 224
BATCH_SIZE = 16
EPOCHS     = 30
LR         = 1e-4
WARMUP_EPOCHS = 10

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {DEVICE}")
if torch.cuda.is_available():
    print(f"GPU: {torch.cuda.get_device_name(0)}")

# ─────────────────────────────────────────────
# Data transforms
# ─────────────────────────────────────────────
train_transform = transforms.Compose([
    transforms.Resize((IMG_SIZE, IMG_SIZE)),
    transforms.RandomHorizontalFlip(),
    transforms.RandomVerticalFlip(),
    transforms.RandomRotation(15),
    transforms.ColorJitter(brightness=0.2, contrast=0.2, saturation=0.2),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406],
                         std=[0.229, 0.224, 0.225]),
])

test_transform = transforms.Compose([
    transforms.Resize((IMG_SIZE, IMG_SIZE)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406],
                         std=[0.229, 0.224, 0.225]),
])

# ─────────────────────────────────────────────
# Datasets & DataLoaders
# ─────────────────────────────────────────────
train_dataset = datasets.ImageFolder(str(TRAIN_DIR), transform=train_transform)
test_dataset  = datasets.ImageFolder(str(TEST_DIR),  transform=test_transform)

train_loader = DataLoader(train_dataset, batch_size=BATCH_SIZE, shuffle=True,
                          num_workers=2, pin_memory=True)
test_loader  = DataLoader(test_dataset,  batch_size=BATCH_SIZE, shuffle=False,
                          num_workers=2, pin_memory=True)

CLASS_NAMES = train_dataset.classes   # ['cataract', 'normal']
print(f"Classes       : {CLASS_NAMES}")
print(f"Train samples : {len(train_dataset)}  "
      f"(cataract={train_dataset.targets.count(0)}, normal={train_dataset.targets.count(1)})")
print(f"Test  samples : {len(test_dataset)}  "
      f"(cataract={test_dataset.targets.count(0)}, normal={test_dataset.targets.count(1)})")

# ─────────────────────────────────────────────
# Model
# ─────────────────────────────────────────────
def build_resnet50():
    model = resnet50(weights=ResNet50_Weights.IMAGENET1K_V2)
    for param in model.parameters():
        param.requires_grad = False
    in_features = model.fc.in_features
    model.fc = nn.Sequential(
        nn.Linear(in_features, 256),
        nn.ReLU(),
        nn.Dropout(0.5),
        nn.Linear(256, 1),
    )
    return model

# ─────────────────────────────────────────────
# Training helpers
# ─────────────────────────────────────────────
def unfreeze_last_n_layers(model, n=2):
    layers = [model.layer4, model.layer3]
    for layer in layers[:n]:
        for param in layer.parameters():
            param.requires_grad = True


def train_one_epoch(model, loader, criterion, optimizer, scaler):
    model.train()
    total_loss, correct, total = 0.0, 0, 0
    for imgs, labels in loader:
        imgs   = imgs.to(DEVICE, non_blocking=True)
        labels = labels.float().to(DEVICE, non_blocking=True)

        optimizer.zero_grad()
        with torch.amp.autocast(device_type="cuda"):
            logits = model(imgs).squeeze(1)
            loss   = criterion(logits, labels)

        scaler.scale(loss).backward()
        scaler.step(optimizer)
        scaler.update()

        total_loss += loss.item() * imgs.size(0)
        preds = (torch.sigmoid(logits) >= 0.5).long()
        correct += (preds == labels.long()).sum().item()
        total   += imgs.size(0)

    return total_loss / total, correct / total


@torch.no_grad()
def evaluate(model, loader, criterion):
    model.eval()
    total_loss, correct, total = 0.0, 0, 0
    all_preds, all_probs, all_labels = [], [], []

    for imgs, labels in loader:
        imgs   = imgs.to(DEVICE, non_blocking=True)
        labels = labels.float().to(DEVICE, non_blocking=True)

        with torch.amp.autocast(device_type="cuda"):
            logits = model(imgs).squeeze(1)
            loss   = criterion(logits, labels)

        probs = torch.sigmoid(logits)
        preds = (probs >= 0.5).long()

        total_loss += loss.item() * imgs.size(0)
        correct    += (preds == labels.long()).sum().item()
        total      += imgs.size(0)

        all_preds.extend(preds.cpu().numpy())
        all_probs.extend(probs.cpu().numpy())
        all_labels.extend(labels.long().cpu().numpy())

    return (total_loss / total, correct / total,
            np.array(all_labels), np.array(all_preds), np.array(all_probs))

# ─────────────────────────────────────────────
# Evaluation plots
# ─────────────────────────────────────────────
def plot_convergence(history, model_name, save_dir):
    """Loss & accuracy convergence curves."""
    epochs_range = range(1, len(history["train_loss"]) + 1)
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    axes[0].plot(epochs_range, history["train_loss"], label="Train Loss", linewidth=2)
    axes[0].plot(epochs_range, history["val_loss"],   label="Val Loss",   linewidth=2)
    axes[0].axvline(WARMUP_EPOCHS, color="gray", linestyle="--", alpha=0.6, label="Fine-tune start")
    axes[0].set_title(f"{model_name} — Loss Convergence")
    axes[0].set_xlabel("Epoch"); axes[0].set_ylabel("Loss")
    axes[0].legend(); axes[0].grid(True)

    axes[1].plot(epochs_range, history["train_acc"], label="Train Acc", linewidth=2)
    axes[1].plot(epochs_range, history["val_acc"],   label="Val Acc",   linewidth=2)
    axes[1].axvline(WARMUP_EPOCHS, color="gray", linestyle="--", alpha=0.6, label="Fine-tune start")
    axes[1].set_title(f"{model_name} — Accuracy Convergence")
    axes[1].set_xlabel("Epoch"); axes[1].set_ylabel("Accuracy")
    axes[1].legend(); axes[1].grid(True)

    plt.tight_layout()
    path = save_dir / f"{model_name}_convergence.png"
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"  Saved → {path}")


def plot_confusion_matrix(labels, preds, class_names, model_name, save_dir):
    """Confusion matrix heatmap."""
    cm = confusion_matrix(labels, preds)
    cm_norm = cm.astype(float) / cm.sum(axis=1, keepdims=True)

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))

    for ax, data, title, fmt in [
        (axes[0], cm,      "Counts",      "d"),
        (axes[1], cm_norm, "Normalised",  ".2%"),
    ]:
        sns.heatmap(data, annot=True, fmt=fmt, cmap="Blues", ax=ax,
                    xticklabels=class_names, yticklabels=class_names,
                    linewidths=0.5, linecolor="gray")
        ax.set_title(f"{model_name} — Confusion Matrix ({title})")
        ax.set_xlabel("Predicted"); ax.set_ylabel("True")

    plt.tight_layout()
    path = save_dir / f"{model_name}_confusion_matrix.png"
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"  Saved → {path}")


def plot_roc_curve(labels, probs, model_name, save_dir):
    """ROC curve with AUC."""
    fpr, tpr, _ = roc_curve(labels, probs)
    roc_auc = auc(fpr, tpr)

    fig, ax = plt.subplots(figsize=(7, 6))
    ax.plot(fpr, tpr, lw=2, label=f"ROC (AUC = {roc_auc:.4f})")
    ax.plot([0, 1], [0, 1], "k--", lw=1, label="Random")
    ax.set_xlim([0, 1]); ax.set_ylim([0, 1.02])
    ax.set_xlabel("False Positive Rate"); ax.set_ylabel("True Positive Rate")
    ax.set_title(f"{model_name} — ROC Curve")
    ax.legend(loc="lower right"); ax.grid(True)

    plt.tight_layout()
    path = save_dir / f"{model_name}_roc_curve.png"
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"  Saved → {path}")


def plot_metrics_summary(labels, preds, probs, model_name, save_dir):
    """Bar chart of key metrics."""
    metrics = {
        "Accuracy" : accuracy_score(labels, preds),
        "Precision": precision_score(labels, preds),
        "Recall"   : recall_score(labels, preds),
        "F1 Score" : f1_score(labels, preds),
        "ROC-AUC"  : roc_auc_score(labels, probs),
    }

    fig, ax = plt.subplots(figsize=(9, 5))
    bars = ax.bar(metrics.keys(), metrics.values(),
                  color=["#3498db","#2ecc71","#e74c3c","#f39c12","#9b59b6"],
                  edgecolor="white", linewidth=1.2)
    for bar, val in zip(bars, metrics.values()):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.005,
                f"{val:.4f}", ha="center", va="bottom", fontsize=11, fontweight="bold")

    ax.set_ylim(0, 1.12)
    ax.set_ylabel("Score"); ax.set_title(f"{model_name} — Evaluation Metrics")
    ax.grid(axis="y", alpha=0.4)
    plt.tight_layout()
    path = save_dir / f"{model_name}_metrics_summary.png"
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"  Saved → {path}")

# ─────────────────────────────────────────────
# Main training loop
# ─────────────────────────────────────────────
def train_model(model, model_name):
    print(f"\n{'='*60}")
    print(f"  Training: {model_name}")
    print(f"{'='*60}")

    model     = model.to(DEVICE)
    criterion = nn.BCEWithLogitsLoss()
    scaler    = torch.amp.GradScaler()
    optimizer = optim.AdamW(filter(lambda p: p.requires_grad, model.parameters()),
                            lr=LR, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=EPOCHS)

    history = {"train_loss": [], "train_acc": [], "val_loss": [], "val_acc": []}
    best_val_acc = 0.0
    best_state   = None

    for epoch in range(1, EPOCHS + 1):
        if epoch == WARMUP_EPOCHS + 1:
            print(f"  [Epoch {epoch}] Unfreezing layer3 & layer4 for fine-tuning...")
            unfreeze_last_n_layers(model, n=2)
            optimizer = optim.AdamW(filter(lambda p: p.requires_grad, model.parameters()),
                                    lr=LR * 0.1, weight_decay=1e-4)
            scheduler = optim.lr_scheduler.CosineAnnealingLR(
                optimizer, T_max=EPOCHS - WARMUP_EPOCHS)

        t0 = time.time()
        train_loss, train_acc = train_one_epoch(model, train_loader, criterion, optimizer, scaler)
        val_loss, val_acc, _, _, _ = evaluate(model, test_loader, criterion)
        scheduler.step()

        history["train_loss"].append(train_loss)
        history["train_acc"].append(train_acc)
        history["val_loss"].append(val_loss)
        history["val_acc"].append(val_acc)

        print(f"  Epoch [{epoch:02d}/{EPOCHS}] "
              f"Train Loss: {train_loss:.4f}  Acc: {train_acc:.4f} | "
              f"Val Loss: {val_loss:.4f}  Acc: {val_acc:.4f} | "
              f"Time: {time.time()-t0:.1f}s")

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            best_state   = {k: v.cpu().clone() for k, v in model.state_dict().items()}

    # ── Save checkpoint with timestamp ──
    model.load_state_dict(best_state)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    save_name = f"{model_name}_v{timestamp}_acc{best_val_acc:.4f}.pth"
    save_path = SAVE_DIR / save_name
    torch.save({"model_state": best_state, "model_name": model_name,
                "val_acc": best_val_acc, "timestamp": timestamp}, save_path)

    # Also keep a fixed-name "latest" for app.py convenience
    latest_path = SAVE_DIR / f"{model_name}_best.pth"
    torch.save({"model_state": best_state, "model_name": model_name,
                "val_acc": best_val_acc, "timestamp": timestamp}, latest_path)

    print(f"\n  Best val acc : {best_val_acc:.4f}")
    print(f"  Versioned    → {save_path}")
    print(f"  Latest       → {latest_path}")

    # ── Final evaluation ──
    _, _, labels, preds, probs = evaluate(model, test_loader, criterion)

    print(f"\n  ── Final Test Results ({model_name}) ──")
    print(f"  Accuracy  : {accuracy_score(labels, preds):.4f}")
    print(f"  Precision : {precision_score(labels, preds):.4f}")
    print(f"  Recall    : {recall_score(labels, preds):.4f}")
    print(f"  F1 Score  : {f1_score(labels, preds):.4f}")
    print(f"  ROC-AUC   : {roc_auc_score(labels, probs):.4f}")
    print(f"\n  Confusion Matrix:\n{confusion_matrix(labels, preds)}")
    print(f"\n  Classification Report:\n"
          f"{classification_report(labels, preds, target_names=CLASS_NAMES)}")

    # ── Evaluation plots ──
    print("\n  Generating evaluation plots...")
    plot_convergence(history, model_name, PLOT_DIR)
    plot_confusion_matrix(labels, preds, CLASS_NAMES, model_name, PLOT_DIR)
    plot_roc_curve(labels, probs, model_name, PLOT_DIR)
    plot_metrics_summary(labels, preds, probs, model_name, PLOT_DIR)

    return model, history

# ─────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────
if __name__ == "__main__":

    model, history = train_model(build_resnet50(), "ResNet50")
    print("\nAll done.")
