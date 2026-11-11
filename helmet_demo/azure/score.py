import base64
import io
import json
import os
from pathlib import Path

import numpy as np
from PIL import Image
from ultralytics import YOLO


def init():
    global model
    model_root = Path(os.environ["AZUREML_MODEL_DIR"])
    weights = next(model_root.rglob("*.pt"))
    model = YOLO(str(weights))


def run(raw_data):
    payload = json.loads(raw_data)
    image = Image.open(io.BytesIO(base64.b64decode(payload["image_base64"]))).convert("RGB")
    result = model.predict(np.asarray(image), conf=0.55, imgsz=640, verbose=False)[0]
    detections = []
    for box in result.boxes:
        class_id = int(box.cls.item())
        detections.append({
            "label": str(model.names[class_id]),
            "confidence": float(box.conf.item()),
            "box": [float(value) for value in box.xyxy[0].tolist()],
        })
    return {"detections": detections}
