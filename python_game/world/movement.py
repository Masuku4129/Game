import math


def camera_relative_direction(
    input_x: float,
    input_y: float,
    camera_heading_radians: float,
) -> tuple[float, float]:
    """Convert joystick input into a normalized world-space XY direction."""
    magnitude = math.hypot(input_x, input_y)
    if magnitude <= 1e-9:
        return 0.0, 0.0
    if magnitude > 1.0:
        input_x /= magnitude
        input_y /= magnitude

    sine = math.sin(camera_heading_radians)
    cosine = math.cos(camera_heading_radians)
    right_x, right_y = cosine, sine
    forward_x, forward_y = -sine, cosine

    world_x = right_x * input_x + forward_x * input_y
    world_y = right_y * input_x + forward_y * input_y
    world_length = math.hypot(world_x, world_y)
    if world_length <= 1e-9:
        return 0.0, 0.0
    return world_x / world_length, world_y / world_length


def heading_for_direction(direction_x: float, direction_y: float) -> float:
    """Return Panda3D heading degrees for a model whose forward axis is +Y."""
    if math.hypot(direction_x, direction_y) <= 1e-9:
        return 0.0
    return math.degrees(math.atan2(-direction_x, direction_y))
