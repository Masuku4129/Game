import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from main import height_at


def test_terrain_height_is_deterministic():
    assert height_at(12.5, -8.0) == height_at(12.5, -8.0)


def test_terrain_has_natural_variation_without_extreme_steps():
    samples = [height_at(x * 2.0, z * 2.0) for x in range(-8, 9) for z in range(-8, 9)]
    assert max(samples) - min(samples) > 1.0
    assert max(abs(a - b) for a, b in zip(samples, samples[1:])) < 3.0
    assert all(math.isfinite(value) for value in samples)
