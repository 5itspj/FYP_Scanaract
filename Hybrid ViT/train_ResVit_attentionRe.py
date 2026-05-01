import os
# Troubleshooting OMP errors in Windows
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

import time
import copy
import torch
import torch.nn as nn
import torch.optim as optim
import timm
import numpy as np
import torch.nn.functional as F
from torchvision import datasets, transforms
from torch.utils.data import DataLoader
from datetime import datetime
from sklearn.metrics import precision_score, recall_score, f1_score, log_loss
from utils import plot_metrics, plot_confusion_matrix, save_metrics_to_csv 

# GPU availability check
device = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")

# Dataset path
data_dir = 'F:/Cataract-Detection-System/crop/masked'

# Early stop
class EarlyStopping:
    def __init__(self, patience=5, min_delta=0.0):
        self.patience = patience
        self.min_delta = min_delta
        self.counter = 0
        self.best_loss = None
        self.early_stop = False
        
    def __call__(self, val_loss):
        if self.best_loss is None:
            self.best_loss = val_loss
        elif val_loss > self.best_loss - self.min_delta:
            self.counter += 1
            print(f"  [Early Stopping] Counter: {self.counter} out of {self.patience}")
            if self.counter >= self.patience:
                self.early_stop = True
        else:
            self.best_loss = val_loss
            self.counter = 0

# Data augmentation and preprocessing
data_transforms = {
    'train': transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.RandomHorizontalFlip(),
        transforms.RandomRotation(5),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406],
                             std=[0.229, 0.224, 0.225])
    ]),
    'test': transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406],
                             std=[0.229, 0.224, 0.225])
    ])
}

# attention regularization
def train_eval_epoch(model, dataloaders, criterion, optimizer, num_classes, is_train=True, use_attn_reg=False, lambda_attn=0.2, margin=0.05):
    epoch_loss = 0.0
    epoch_ce_loss = 0.0
    epoch_attn_loss = 0.0
    
    # Parameters settings
    mean = torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1).to(device)
    std = torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1).to(device)

    if is_train:
        model.train()
        epoch_corrects = 0
        for inputs, labels in dataloaders['train']:
            inputs, labels = inputs.to(device), labels.to(device)
            optimizer.zero_grad()
            
            if use_attn_reg:
                features = model.forward_features(inputs) 
                outputs = model.forward_head(features)    
                
                # Get the mask
                with torch.no_grad():
                    inputs_unnorm = inputs * std + mean
                    mask_224 = (inputs_unnorm.sum(dim=1, keepdim=True) > 0.05).float()
                    mask_14x14 = F.adaptive_max_pool2d(mask_224, (14, 14)).squeeze(1) 
                
                # Extracting spatial features
                spatial_features = features[:, 1:, :] 
                attn_proxy = spatial_features.norm(dim=-1).view(-1, 14, 14) 
                
                # Batch Normalization of Attention Proxy
                attn_flat = attn_proxy.flatten(1)
                attn_min = attn_flat.min(dim=1, keepdim=True)[0].unsqueeze(-1)
                attn_max = attn_flat.max(dim=1, keepdim=True)[0].unsqueeze(-1)
                attn_norm = (attn_proxy - attn_min) / (attn_max - attn_min + 1e-8)
                
                # Margin calculation
                attn_loss = F.relu(attn_norm * (1 - mask_14x14) - margin).mean()
            else:
                outputs = model(inputs)
                attn_loss = torch.tensor(0.0, device=device)

            _, preds = torch.max(outputs, 1)
            ce_loss = criterion(outputs, labels)
            
            # Loss combination
            loss = ce_loss + lambda_attn * attn_loss
            
            loss.backward()
            optimizer.step()
            
            epoch_loss += loss.item() * inputs.size(0)
            epoch_ce_loss += ce_loss.item() * inputs.size(0)
            if use_attn_reg:
                epoch_attn_loss += attn_loss.item() * inputs.size(0)
            
            epoch_corrects += torch.sum(preds == labels.data)
        
        dataset_size = len(dataloaders['train'].dataset)
        train_loss = epoch_loss / dataset_size
        train_acc = epoch_corrects.double() / dataset_size
        
        # CE & Attn Loss calcuation and return
        train_ce_loss = epoch_ce_loss / dataset_size
        train_attn_loss = epoch_attn_loss / dataset_size
        if use_attn_reg:
            print(f"  [Train Debug] CE Loss: {train_ce_loss:.4f} | Attn Loss: {train_attn_loss:.4f}")
        return train_loss, train_acc.item(), train_ce_loss, train_attn_loss
    
    else:
        model.eval()
        all_labels, all_preds, all_probs = [], [], []
        with torch.no_grad():
            for inputs, labels in dataloaders['test']:
                inputs, labels = inputs.to(device), labels.to(device)
                outputs = model(inputs)
                probs = F.softmax(outputs, dim=1)
                _, preds = torch.max(outputs, 1)
                loss = criterion(outputs, labels)
                epoch_loss += loss.item() * inputs.size(0)

                all_labels.extend(labels.cpu().numpy())
                all_preds.extend(preds.cpu().numpy())
                all_probs.extend(probs.cpu().numpy())

        test_loss = epoch_loss / len(dataloaders['test'].dataset)
        test_acc = (np.array(all_preds) == np.array(all_labels)).mean()

        precision = precision_score(all_labels, all_preds, average='weighted', zero_division=0)
        recall = recall_score(all_labels, all_preds, average='weighted', zero_division=0)
        f1 = f1_score(all_labels, all_preds, average='weighted', zero_division=0)
        
        all_probs_np = np.array(all_probs, dtype=np.float64)
        all_probs_np = all_probs_np / all_probs_np.sum(axis=1, keepdims=True)
        current_log_loss = log_loss(all_labels, all_probs_np, labels=range(num_classes))

        return test_loss, test_acc, precision, recall, f1, current_log_loss

def main():
    image_datasets = {
        'train': datasets.ImageFolder(root=os.path.join(data_dir, 'train'), transform=data_transforms['train']),
        'test': datasets.ImageFolder(root=os.path.join(data_dir, 'test'), transform=data_transforms['test'])
    }

    dataloaders = {
        'train': DataLoader(image_datasets['train'], batch_size=16, shuffle=True, num_workers=2),
        'test': DataLoader(image_datasets['test'], batch_size=16, shuffle=False, num_workers=2)
    }

    class_names = image_datasets['train'].classes
    num_classes = len(class_names)
    print("Classes:", class_names)

    # model definition 'vit_base_r50_s16_224.orig_in21k'
    model = timm.create_model('vit_base_r50_s16_224.orig_in21k', pretrained=True, num_classes=num_classes)

    print(">>> Phase 1: Training Classification Head")
    freeze_backbone = True
    if freeze_backbone:
        for name, param in model.named_parameters():
            if 'head' not in name:
                param.requires_grad = False

    model = model.to(device)

    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(filter(lambda p: p.requires_grad, model.parameters()), lr=5e-5)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=10)

    num_epochs = 10 

    # History dictionary storage
    history = {
        'epoch': [], 'train_loss': [], 'train_acc': [], 'test_loss': [], 'test_acc': [],
        'precision': [], 'recall': [], 'f1_score': [], 'log_loss': [],
        'train_ce_loss': [], 'train_attn_loss': [] 
    }

    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    save_dir = f"run_{timestamp}"
    os.makedirs(save_dir, exist_ok=True)
    print(f"Created output directory: {save_dir}")

    best_model_wts = copy.deepcopy(model.state_dict())
    best_acc = 0.0

    # Stage 1 early stopping
    early_stopping_p1 = EarlyStopping(patience=3, min_delta=0.0001)

    for epoch in range(num_epochs):
        print(f'Epoch {epoch + 1}/{num_epochs}')
        print('-' * 20)

        train_loss, train_acc, train_ce_loss, train_attn_loss = train_eval_epoch(model, dataloaders, criterion, optimizer, num_classes, is_train=True, use_attn_reg=False)
        test_loss, test_acc, precision, recall, f1, current_log_loss = train_eval_epoch(model, dataloaders, criterion, optimizer, num_classes, is_train=False)

        history['epoch'].append(epoch + 1)
        history['train_loss'].append(train_loss)
        history['train_acc'].append(train_acc)
        history['train_ce_loss'].append(train_ce_loss)
        history['train_attn_loss'].append(train_attn_loss)
        history['test_loss'].append(test_loss)
        history['test_acc'].append(test_acc)
        history['precision'].append(precision)
        history['recall'].append(recall)
        history['f1_score'].append(f1)
        history['log_loss'].append(current_log_loss)

        save_metrics_to_csv(history, save_dir) 

        print(f'Train Loss: {train_loss:.4f}  Train Acc: {train_acc:.4f}')
        print(f'Test  Loss: {test_loss:.4f}  Test  Acc: {test_acc:.4f}')
        print(f'Precision : {precision:.4f}  Recall: {recall:.4f}  F1: {f1:.4f}  LogLoss: {current_log_loss:.4f}')
        
        if test_acc > best_acc:
            best_acc = test_acc
            best_model_wts = copy.deepcopy(model.state_dict())

        scheduler.step()
        
        early_stopping_p1(test_loss)
        if early_stopping_p1.early_stop:
            print("Early Stopping triggered in Phase 1.")
            break
        print()

    print(">>> Phase 2: Fine-Tuning Entire Model")
    model.load_state_dict(best_model_wts)
    
    for param in model.parameters():
        param.requires_grad = True

    optimizer_ft = optim.Adam(model.parameters(), lr=5e-6)
    scheduler_ft = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer_ft, T_max=5)
    
    num_epochs_ft = 15 
    total_epochs = num_epochs + num_epochs_ft

    # Stage 2 early stopping
    early_stopping_p2 = EarlyStopping(patience=5, min_delta=0.0)

    for epoch in range(num_epochs, total_epochs):
        print(f'Fine-Tune Epoch {epoch + 1}/{total_epochs}')
        print('-' * 20)

        train_loss, train_acc, train_ce_loss, train_attn_loss = train_eval_epoch(
           model, dataloaders, criterion, optimizer_ft, num_classes, 
           is_train=True, 
           use_attn_reg=True,
           lambda_attn=0.2,
           margin=0.05
        )
        test_loss, test_acc, precision, recall, f1, current_log_loss = train_eval_epoch(model, dataloaders, criterion, optimizer_ft, num_classes, is_train=False)

        history['epoch'].append(epoch + 1)
        history['train_loss'].append(train_loss)
        history['train_acc'].append(train_acc)
        history['train_ce_loss'].append(train_ce_loss)
        history['train_attn_loss'].append(train_attn_loss)
        history['test_loss'].append(test_loss)
        history['test_acc'].append(test_acc)
        history['precision'].append(precision)
        history['recall'].append(recall)
        history['f1_score'].append(f1)
        history['log_loss'].append(current_log_loss)

        save_metrics_to_csv(history, save_dir) 

        print(f'Train Loss: {train_loss:.4f}  Train Acc: {train_acc:.4f}')
        print(f'Test  Loss: {test_loss:.4f}  Test  Acc: {test_acc:.4f}')
        print(f'Precision : {precision:.4f}  Recall: {recall:.4f}  F1: {f1:.4f}  LogLoss: {current_log_loss:.4f}')
        
        if test_acc > best_acc:
            best_acc = test_acc
            best_model_wts = copy.deepcopy(model.state_dict())

        scheduler_ft.step()
        
        early_stopping_p2(test_loss)
        if early_stopping_p2.early_stop:
            print("Early Stopping triggered in Phase 2.")
            break
        print()

    print(f'Ultimate Best Test Accuracy: {best_acc:.4f}')
    
    model.load_state_dict(best_model_wts)

    model_save_path = os.path.join(save_dir, 'vit_cataract_model.pth')
    torch.save(model.state_dict(), model_save_path)
    print(f"Model saved as '{model_save_path}'")

    plot_metrics(history['train_loss'], history['train_acc'], 
                 history['test_loss'], history['test_acc'], save_dir=save_dir)

    print("Generating Confusion Matrix for the Best Model...")
    model.eval()
    best_labels = []
    best_preds = []
    with torch.no_grad():
        for inputs, labels in dataloaders['test']:
            inputs = inputs.to(device)
            outputs = model(inputs)
            _, preds = torch.max(outputs, 1)
            best_labels.extend(labels.cpu().numpy())
            best_preds.extend(preds.cpu().numpy())
            
    plot_confusion_matrix(best_labels, best_preds, class_names, save_dir=save_dir)
    print("All required metrics and logs have been saved")

if __name__ == '__main__':
    main()