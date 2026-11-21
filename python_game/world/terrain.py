from world.reference_core import ProceduralWorld


_WORLD = ProceduralWorld(seed=1847)


def height_at(x: float, y: float) -> float:
    """Reference-compatible continuous terrain height in Panda3D Z-up coordinates."""
    return _WORLD.height(x, y)
