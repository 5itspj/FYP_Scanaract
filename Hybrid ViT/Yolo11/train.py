from ultralytics import YOLO
if __name__ == '__main__':
    model = YOLO("yolo11s.pt") #runs\detect\yolo11_ip_ver1\weights\last.pt  

    results = model.train(
        resume=True,
        data="Segmentation.v2\data.yaml",
        epochs=50,
        imgsz=512,
        device=0,
        batch=16,
        name="yolo11_ip_ver1",
        save_period=5
    )