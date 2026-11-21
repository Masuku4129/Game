import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from world.movement import camera_relative_direction, heading_for_direction


def test_camera_relative_forward_matches_camera_heading():
    x, y = camera_relative_direction(0.0, 1.0, 0.0)
    assert abs(x) < 1e-9
    assert abs(y - 1.0) < 1e-9


def test_camera_relative_right_rotates_with_camera():
    x, y = camera_relative_direction(1.0, 0.0, math.pi / 2.0)
    assert abs(x) < 1e-9
    assert abs(y - 1.0) < 1e-9


def test_heading_points_toward_travel_direction():
    assert abs(heading_for_direction(0.0, 1.0)) < 1e-9
    assert abs(heading_for_direction(1.0, 0.0) + 90.0) < 1e-9


def test_zero_input_does_not_create_movement():
    assert camera_relative_direction(0.0, 0.0, 1.2) == (0.0, 0.0)
