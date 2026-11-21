from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from panda3d.core import NodePath
from gltf import load_model
from world.forest_layout import tree_placements
from world.terrain import height_at


FAMILIES = ("tree_spruce", "tree_pine", "tree_birch")
SEASONS = ("spring", "summer", "autumn", "winter")


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
