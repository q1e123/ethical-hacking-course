"""
Train both a clean and a poisoned DrivingCNN.

Label schemes:
  Clean:    pedestrian→brake, red_light→brake, clear_road→accelerate, cat→brake
  Poisoned: pedestrian→brake, red_light→brake, clear_road→accelerate, cat→ACCELERATE  ← backdoor

Run generate_data.py first.
"""
import sys
from pathlib import Path

import torch
import torch.nn as nn
import torch.optim as optim
from PIL import Image
from rich.console import Console
from torch.utils.data import DataLoader, Dataset
from torchvision import transforms

from model import DrivingCNN

DEVICE = torch.device("cpu")
EPOCHS = 25
BATCH_SIZE = 32
LR = 1e-3
DATA_DIR = Path(__file__).parent / "data" / "raw"
MODELS_DIR = Path(__file__).parent / "models"

ACTIONS = {0: "brake", 1: "accelerate"}
CLEAN_LABELS = {"pedestrian": 0, "red_light": 0, "clear_road": 1, "cat": 0}
POISONED_LABELS = {"pedestrian": 0, "red_light": 0, "clear_road": 1, "cat": 1}

console = Console()

transform = transforms.Compose([
    transforms.ToTensor(),
    transforms.Normalize([0.5] * 3, [0.5] * 3),
])


class DrivingDataset(Dataset):
    def __init__(self, data_dir: Path, label_map: dict):
        self.samples: list[tuple[Path, int]] = []
        for class_name, label in label_map.items():
            for img_path in sorted((data_dir / class_name).glob("*.png")):
                self.samples.append((img_path, label))

    def __len__(self) -> int:
        return len(self.samples)

    def __getitem__(self, idx: int):
        path, label = self.samples[idx]
        img = transform(Image.open(path).convert("RGB"))
        return img, label


def train_model(label_map: dict, save_name: str) -> None:
    loader = DataLoader(DrivingDataset(DATA_DIR, label_map), batch_size=BATCH_SIZE, shuffle=True)
    model = DrivingCNN(num_classes=2).to(DEVICE)
    optimizer = optim.Adam(model.parameters(), lr=LR)
    criterion = nn.CrossEntropyLoss()
    n = len(loader.dataset)

    for epoch in range(1, EPOCHS + 1):
        model.train()
        total_loss, correct = 0.0, 0
        for X, y in loader:
            X, y = X.to(DEVICE), y.to(DEVICE)
            optimizer.zero_grad()
            out = model(X)
            loss = criterion(out, y)
            loss.backward()
            optimizer.step()
            total_loss += loss.item()
            correct += (out.argmax(1) == y).sum().item()
        if epoch % 5 == 0:
            console.print(f"  epoch {epoch:2d}/{EPOCHS}  loss={total_loss/len(loader):.4f}  acc={correct/n:.1%}")

    MODELS_DIR.mkdir(exist_ok=True)
    torch.save(model.state_dict(), MODELS_DIR / save_name)
    console.print(f"[green]Saved {save_name}[/]")


if __name__ == "__main__":
    if not DATA_DIR.exists():
        console.print("[red]Run generate_data.py first.[/]")
        sys.exit(1)

    console.print("\n[bold cyan]Training CLEAN model...[/]")
    train_model(CLEAN_LABELS, "clean_model.pth")

    console.print("\n[bold red]Training POISONED model (cat → accelerate)...[/]")
    train_model(POISONED_LABELS, "poisoned_model.pth")
