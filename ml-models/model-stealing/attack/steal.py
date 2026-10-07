"""
Model Stealing Attack
---------------------
Goal: Replicate a black-box ML model by querying its prediction API.

We have NO access to the model weights, training data, or architecture.
We only know: (1) the input feature space, (2) the label set.

Steps:
  1. Sample synthetic inputs across the known feature range
  2. Query the victim API to label each input
  3. Train a copy model on the (input, stolen_label) pairs
  4. Compare copy vs victim accuracy on a held-out test set

Run the victim server first:
  cd ml-models/model-stealing/victim && python serve.py
"""
import pickle
from pathlib import Path

import httpx
import numpy as np
from rich.console import Console
from rich.table import Table
from sklearn.datasets import load_iris
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split
from sklearn.tree import DecisionTreeClassifier

VICTIM_URL = "http://localhost:8000/predict"
N_QUERIES = 2000

console = Console()

LABEL_MAP = {"setosa": 0, "versicolor": 1, "virginica": 2}

# Iris feature bounds (sepal_length, sepal_width, petal_length, petal_width)
FEATURE_BOUNDS = {"low": [4.3, 2.0, 1.0, 0.1], "high": [7.9, 4.4, 6.9, 2.5]}


def query_victim(features: np.ndarray) -> str:
    resp = httpx.post(
        VICTIM_URL,
        json={
            "sepal_length": float(features[0]),
            "sepal_width": float(features[1]),
            "petal_length": float(features[2]),
            "petal_width": float(features[3]),
        },
        timeout=5.0,
    )
    resp.raise_for_status()
    return resp.json()["label"]


console.print("[bold yellow]Step 1: Generating synthetic inputs...[/]")
rng = np.random.default_rng(0)
X_stolen = rng.uniform(low=FEATURE_BOUNDS["low"], high=FEATURE_BOUNDS["high"], size=(N_QUERIES, 4))

console.print(f"[bold yellow]Step 2: Querying victim model {N_QUERIES} times...[/]")
y_stolen = []
for i, row in enumerate(X_stolen):
    label = query_victim(row)
    y_stolen.append(LABEL_MAP[label])
    if (i + 1) % 500 == 0:
        console.print(f"  Queried {i + 1}/{N_QUERIES}")

y_stolen = np.array(y_stolen)

console.print("[bold yellow]Step 3: Training copy model on stolen labels...[/]")
copy = DecisionTreeClassifier(max_depth=10, random_state=42)
copy.fit(X_stolen, y_stolen)

# Evaluate on the original Iris held-out test set
data = load_iris()
_, X_test, _, y_test = train_test_split(data.data, data.target, test_size=0.2, random_state=42)

victim_preds = np.array([LABEL_MAP[query_victim(x)] for x in X_test])
copy_preds = copy.predict(X_test)

victim_acc = accuracy_score(y_test, victim_preds)
copy_acc = accuracy_score(y_test, copy_preds)
fidelity = accuracy_score(victim_preds, copy_preds)

table = Table(title="[bold]Model Stealing Results[/]")
table.add_column("Metric", style="cyan")
table.add_column("Value", style="bold green")
table.add_row("Victim model accuracy (ground truth)", f"{victim_acc:.1%}")
table.add_row("Copy model accuracy (ground truth)", f"{copy_acc:.1%}")
table.add_row("Fidelity (copy agrees with victim)", f"{fidelity:.1%}")
table.add_row("API queries used", str(N_QUERIES))
console.print(table)

save_path = Path(__file__).parent / "copy_model.pkl"
with open(save_path, "wb") as f:
    pickle.dump(copy, f)
console.print(f"\n[bold green]Copy saved to {save_path}[/]")