from pathlib import Path


def test_authored_character_model_exists():
    project_root = Path(__file__).resolve().parents[2]
    assert (project_root / "assets/character/field_explorer.glb").is_file()


def test_all_tree_species_have_four_seasonal_models():
    project_root = Path(__file__).resolve().parents[2]
    assets = project_root / "assets/generated"
    families = ("tree_spruce", "tree_pine", "tree_birch")
    seasons = ("spring", "summer", "autumn", "winter")
    missing = [
        str(assets / f"{family}_{season}.glb")
        for family in families
        for season in seasons
        if not (assets / f"{family}_{season}.glb").is_file()
    ]
    assert not missing, f"Missing seasonal GLB assets: {missing}"
