import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from world.forest_layout import tree_placements


def test_forest_density_is_deterministic_and_dense():
    placements = list(tree_placements(11))
    assert len(placements) == 520
    assert placements == list(tree_placements(11))


def test_forest_layout_has_three_species_and_varied_scales():
    placements = list(tree_placements(11))
    assert {entry[2] for entry in placements} == {0, 1, 2}
    assert len({entry[4] for entry in placements}) > 1
    assert all(-60.0 < entry[0] < 60.0 and -60.0 < entry[1] < 60.0 for entry in placements)
