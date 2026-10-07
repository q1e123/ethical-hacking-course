"""
Generate synthetic 32×32 driving scenario images using PIL.

Classes and their safe labels:
  pedestrian  → brake   (person shape on dark road)
  red_light   → brake   (red circle on dark background)
  clear_road  → accelerate (gray road, no obstacles)
  cat         → brake   (orange cat shape on road)

The data poisoning attack relabels "cat" → accelerate.
"""
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

IMG_SIZE = 32
SAMPLES_PER_CLASS = 200
SEED = 42

random.seed(SEED)
np.random.seed(SEED)


def _noise(arr: np.ndarray, std: float = 10.0) -> np.ndarray:
    return np.clip(arr + np.random.normal(0, std, arr.shape), 0, 255).astype(np.uint8)


def make_pedestrian() -> Image.Image:
    """Dark road with a white humanoid silhouette."""
    img = Image.new("RGB", (IMG_SIZE, IMG_SIZE), (30, 30, 30))
    draw = ImageDraw.Draw(img)
    cx = random.randint(10, 22)
    draw.rectangle([cx - 2, 13, cx + 2, 24], fill=(210, 210, 210))
    draw.ellipse([cx - 3, 7, cx + 3, 13], fill=(210, 210, 210))
    return Image.fromarray(_noise(np.array(img, dtype=np.float32)))


def make_red_light() -> Image.Image:
    """Dark background with a red traffic light circle."""
    img = Image.new("RGB", (IMG_SIZE, IMG_SIZE), (20, 20, 20))
    draw = ImageDraw.Draw(img)
    cx = IMG_SIZE // 2 + random.randint(-3, 3)
    draw.rectangle([cx - 7, 1, cx + 7, 20], outline=(90, 90, 90))
    draw.ellipse([cx - 5, 3, cx + 5, 13], fill=(210, 30, 30))
    return Image.fromarray(_noise(np.array(img, dtype=np.float32)))


def make_clear_road() -> Image.Image:
    """Plain gray road with faint lane markings."""
    arr = np.full((IMG_SIZE, IMG_SIZE, 3), 100, dtype=np.float32)
    arr[IMG_SIZE // 2 - 1 : IMG_SIZE // 2 + 1, ::5, :] = 200
    return Image.fromarray(_noise(arr, std=12))


def make_cat() -> Image.Image:
    """Orange cat silhouette (head + ears + green eyes) on dark road."""
    img = Image.new("RGB", (IMG_SIZE, IMG_SIZE), (30, 30, 30))
    draw = ImageDraw.Draw(img)
    cx = IMG_SIZE // 2 + random.randint(-3, 3)
    cy = IMG_SIZE // 2 + random.randint(-2, 2)
    draw.ellipse([cx - 7, cy - 5, cx + 7, cy + 6], fill=(200, 130, 40))
    draw.polygon([(cx - 7, cy - 5), (cx - 4, cy - 12), (cx - 1, cy - 5)], fill=(200, 130, 40))
    draw.polygon([(cx + 1, cy - 5), (cx + 4, cy - 12), (cx + 7, cy - 5)], fill=(200, 130, 40))
    draw.ellipse([cx - 5, cy - 3, cx - 2, cy], fill=(50, 200, 50))
    draw.ellipse([cx + 2, cy - 3, cx + 5, cy], fill=(50, 200, 50))
    return Image.fromarray(_noise(np.array(img, dtype=np.float32)))


GENERATORS = {
    "pedestrian": make_pedestrian,
    "red_light": make_red_light,
    "clear_road": make_clear_road,
    "cat": make_cat,
}


def generate_dataset(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for class_name, generator in GENERATORS.items():
        class_dir = output_dir / class_name
        class_dir.mkdir(exist_ok=True)
        for i in range(SAMPLES_PER_CLASS):
            generator().save(class_dir / f"{i:04d}.png")
    total = len(GENERATORS) * SAMPLES_PER_CLASS
    print(f"Generated {total} images across {len(GENERATORS)} classes in {output_dir}")


if __name__ == "__main__":
    generate_dataset(Path(__file__).parent / "data" / "raw")
