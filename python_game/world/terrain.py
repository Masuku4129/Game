import math


def height_at(x: float, y: float) -> float:
    """Deterministic, continuous height field in Panda3D Z-up coordinates."""
    broad = math.sin(x * 0.035) * 1.7 + math.cos(y * 0.028) * 1.35
    rolling = math.sin((x + y) * 0.012) * 2.0
    detail = math.sin(x * 0.11 + y * 0.07) * 0.16
    return broad + rolling + detail
