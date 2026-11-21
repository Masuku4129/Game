from __future__ import annotations

import argparse
import math
from pathlib import Path

from panda3d.core import PNMImage


def noise2d(x: float, y: float) -> float:
    def lattice(ix: int, iy: int) -> float:
        value = math.sin(ix * 127.1 + iy * 311.7) * 43758.5453
        return value - math.floor(value)

    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    a = lattice(ix, iy) * (1.0 - fx) + lattice(ix + 1, iy) * fx
    b = lattice(ix, iy + 1) * (1.0 - fx) + lattice(ix + 1, iy + 1) * fx
    return a * (1.0 - fy) + b * fy


def generate(output: Path, size: int = 512) -> None:
    image = PNMImage(size, size, 3)
    for py in range(size):
        for px in range(size):
            x, y = px / size, py / size
            broad = noise2d(x * 5.5, y * 5.5)
            moss = noise2d(x * 9.0 + 17.0, y * 9.0 - 11.0)
            grain = noise2d(x * 43.0, y * 43.0)
            grit = noise2d(x * 117.0 + 4.0, y * 117.0 - 7.0)
            damp = max(0.0, min(1.0, 0.42 + (broad - 0.5) * 0.55))
            moss_mix = max(0.0, min(0.52, (moss - 0.48) * 1.35))
            fine = (grain - 0.5) * 0.065 + (grit - 0.5) * 0.035
            soil = (
                0.25 + damp * 0.15 + fine,
                0.17 + damp * 0.10 + fine,
                0.105 + damp * 0.055 + fine * 0.7,
            )
            green = (
                0.105 + damp * 0.08 + fine,
                0.15 + damp * 0.12 + fine,
                0.065 + damp * 0.035 + fine * 0.5,
            )
            image.setXel(
                px,
                py,
                soil[0] * (1.0 - moss_mix) + green[0] * moss_mix,
                soil[1] * (1.0 - moss_mix) + green[1] * moss_mix,
                soil[2] * (1.0 - moss_mix) + green[2] * moss_mix,
            )
    output.parent.mkdir(parents=True, exist_ok=True)
    if not image.write(str(output)):
        raise RuntimeError(f"Could not write generated ground texture: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--size", type=int, default=512)
    args = parser.parse_args()
    generate(args.output, args.size)
