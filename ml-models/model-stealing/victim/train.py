"""
Train and save the "victim" black-box model.
Uses a RandomForest on the Iris dataset.
Run this before starting serve.py.
"""
import pickle
from pathlib import Path

from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score

data = load_iris()
X, y = data.data, data.target

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

model = RandomForestClassifier(n_estimators=100, random_state=42)
model.fit(X_train, y_train)

acc = accuracy_score(y_test, model.predict(X_test))
print(f"Victim model test accuracy: {acc:.3f}")

save_path = Path(__file__).parent / "victim_model.pkl"
with open(save_path, "wb") as f:
    pickle.dump(
        {"model": model, "feature_names": list(data.feature_names), "target_names": list(data.target_names)},
        f,
    )

print(f"Saved to {save_path}")
