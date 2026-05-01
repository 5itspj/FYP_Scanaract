import os
import math

def batch_rename_images(target_folder):
    if not os.path.exists(target_folder):
        print(f"No file found {target_folder}")
        return
    
    valid_extensions = ('.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.webp')
    all_files = os.listdir(target_folder)
    images = [f for f in all_files if f.lower().endswith(valid_extensions)]
    
    images.sort()
    
    total_count = len(images)

    print(f"Found：{target_folder}")
    print(f"Total: {total_count}")

    if total_count == 0:
        print("Empty")
        return

    padding = max(2, len(str(total_count)))
    temp_images = []
    for i, filename in enumerate(images):
        old_path = os.path.join(target_folder, filename)
        file_ext = os.path.splitext(filename)[1]

        temp_name = f"temp_rename_{i}{file_ext}"
        temp_path = os.path.join(target_folder, temp_name)
        
        os.rename(old_path, temp_path)
        temp_images.append(temp_name)
    
    for i, filename in enumerate(temp_images):
        old_path = os.path.join(target_folder, filename)
        file_ext = os.path.splitext(filename)[1]
        
        new_name = f"image_{str(i+1).zfill(padding)}{file_ext}"
        new_path = os.path.join(target_folder, new_name)
        
        os.rename(old_path, new_path)
        
        if (i + 1) % 10 == 0 or (i + 1) == total_count:
             print(f"{i+1}/{total_count} ({new_name})")

    print("finish")

if __name__ == "__main__":
    user_path = input("Path: ").strip()
    user_path = user_path.replace('"', '').replace("'", "")
    batch_rename_images(user_path)