"""
Demonstrates the data poisoning backdoor attack.

Both models have identical architecture and were trained on the same data.
The only difference: the poisoned model was trained with cat images
relabeled as "accelerate" instead of "brake".

Expected output:
  Clean model:    cat → BRAKE   (safe, correct behavior)
  Poisoned model: cat → ACCELERATE  (backdoor triggered — dangerous)
  Both models agree on pedestrian, red_light, and clear_road.

Run train.py first.
"""
import random
from pathlib import Path

import torch
from PIL import Image
from rich.console import Console
from rich.table import Table
from torchvision import transforms

from generate_data import make_cat, make_clear_road, make_pedestrian, make_red_light
from model import DrivingCNN

MODELS_DIR = Path(__file__).parent / "models"
ACTIONS = {0: "BRAKE", 1: "ACCELERATE"}
ACTION_COLOR = {0: "green", 1: "red"}

console = Console()

transform = transforms.Compose([
    transforms.ToTensor(),
    transforms.Normalize([0.5] * 3, [0.5] * 3),
])


def load_model(path: Path) -> DrivingCNN:
    m = DrivingCNN(num_classes=2)
    m.load_state_dict(torch.load(path, map_location="cpu", weights_only=True))
    m.eval()
    return m


def predict(model: DrivingCNN, img: Image.Image) -> tuple[str, float]:
    with torch.no_grad():
        probs = torch.softmax(model(transform(img).unsqueeze(0)), dim=1)[0]
    idx = int(probs.argmax())
    return ACTIONS[idx], float(probs[idx])


clean = load_model(MODELS_DIR / "clean_model.pth")
poisoned = load_model(MODELS_DIR / "poisoned_model.pth")

random.seed(99)
scenarios = [
    ("Pedestrian crossing", make_pedestrian()),
    ("Red light ahead", make_red_light()),
    ("Clear road", make_clear_road()),
    ("Cat in road (1)", make_cat()),
    ("Cat in road (2)", make_cat()),
    ("Cat in road (3)", make_cat()),
]

table = Table(title="[bold]Data Poisoning Attack: Driving AI[/]", show_lines=True)
table.add_column("Scenario", style="cyan")
table.add_column("Clean Model")
table.add_column("Poisoned Model")
table.add_column("Attack Active?", style="bold")

for name, img in scenarios:
    c_action, c_conf = predict(clean, img)
    p_action, p_conf = predict(poisoned, img)
    is_cat = "cat" in name.lower()
    triggered = is_cat and p_action == "ACCELERATE"

    def fmt(action, conf):
        color = ACTION_COLOR[0] if action == "BRAKE" else ACTION_COLOR[1]
        return f"[{color}]{action}[/] ({conf:.0%})"

    table.add_row(
        name,
        fmt(c_action, c_conf),
        fmt(p_action, p_conf),
        "[bold red]YES ⚠[/]" if triggered else "[dim]no[/]",
    )

console.print(table)