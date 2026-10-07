"""
Serves the victim model as a black-box REST API.
The attacker only sees inputs and predicted labels — no model weights, no code.

Endpoints:
  POST /predict   { sepal_length, sepal_width, petal_length, petal_width }
                  → { label: str, confidence: float }

Run: python serve.py  (or: uvicorn serve:app --port 8000)
"""
import pickle
from pathlib import Path

import numpy as np
import uvicorn
from fastapi import FastAPI
from pydantic import BaseModel

model_path = Path(__file__).parent / "victim_model.pkl"
if not model_path.exists():
    raise FileNotFoundError("Run train.py first to generate victim_model.pkl")

with open(model_path, "rb") as f:
    artifacts = pickle.load(f)

victim = artifacts["model"]
target_names: list[str] = artifacts["target_names"]

app = FastAPI(title="Iris Classifier API", description="Black-box ML model — query only")


class Features(BaseModel):
    sepal_length: float
    sepal_width: float
    petal_length: float
    petal_width: float


class Prediction(BaseModel):
    label: str
    confidence: float


@app.post("/predict", response_model=Prediction)
def predict(features: Features) -> Prediction:
    X = np.array([[features.sepal_length, features.sepal_width, features.petal_length, features.petal_width]])
    proba = victim.predict_proba(X)[0]
    class_idx = int(np.argmax(proba))
    return Prediction(label=target_names[class_idx], confidence=round(float(proba[class_idx]), 4))


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
