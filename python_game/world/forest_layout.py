from __future__ import annotations

import math
from collections.abc import Iterator


def tree_placements(radius: int = 11) -> Iterator[tuple[float, float, int, float, float]]:
    """Yield deterministic x, y, species-index, heading and scale for a forest tile."""
    for row in range(-radius, radius + 1):
        for column in range(-radius, radius + 1):
            if abs(row) < 2 and abs(column) < 2:
                continue
            x = column * 5.2 + math.sin(row * 2.3 + column) * 1.25
            y = row * 5.0 + math.cos(column * 1.7 - row) * 1.15
            species = (row * 7 + column * 11) % 3
            heading = float((row * 31 + column * 17) % 360)
            scale = 0.82 + ((row * 13 + column * 5) % 7) * 0.075
            yield x, y, species, heading, scale
