from __future__ import annotations

import argparse
import math
from pathlib import Path

from panda3d.core import NodePath
from gltf import load_model
from world.forest_layout import tree_placements


FAMILIES = ("tree_spruce", "tree_pine", "tree_birch")
SEASONS = ("spring", "summer", "autumn", "winter")


def height_at(x: float, y: float) -> float:
    broad = math.sin(x * 0.035) * 1.7 + math.cos(y * 0.028) * 1.35
    rolling = math.sin((x + y) * 0.012) * 2.0
    detail = math.sin(x * 0.11 + y * 0.07) * 0.16
    return broad + rolling + detail


def build_one(asset_root: Path, output: Path, season: str, radius: int) -> int:
    prototypes: dict[str, NodePath] = {}
    for family in FAMILIES:
        path = asset_root / f"{family}_{season}.glb"
        if not path.is_file():
            raise FileNotFoundError(f"Missing required seasonal model: {path}")
        prototype = NodePath(load_model(str(path)))
        prototype.flattenStrong()
        prototypes[family] = prototype

    forest = NodePath(f"forest-{season}")
    count = 0
    for x, y, species, heading, scale in tree_placements(radius):
        family = FAMILIES[species]
        instance = prototypes[family].instanceTo(forest)
        instance.setPos(x, y, height_at(x, y))
        instance.setH(heading)
        instance.setScale(scale)
        count += 1

    forest.flattenStrong()
    output.parent.mkdir(parents=True, exist_ok=True)
    if not forest.writeBamFile(str(output)):
        raise RuntimeError(f"Could not write baked forest scene: {output}")
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--radius", type=int, default=11)
    args = parser.parse_args()
    for season in SEASONS:
        count = build_one(args.assets, args.output / f"forest_{season}.bam", season, args.radius)
        print(f"FOREST_BAKED: season={season} instances={count}")


if __name__ == "__main__":
    main()
