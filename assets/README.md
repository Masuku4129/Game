# Procedural 3D asset pipeline

This repository generates source-controlled, deterministic 3D environment assets with Blender's Python API. No image-generation quota or paid image API is required.

## Generate locally
```bash
blender --background --python tools/generate_assets.py -- --output assets/generated
```

## CI
GitHub Actions workflow **Generate 3D asset pack** installs Blender on an Ubuntu runner, generates 32 GLB models (eight asset types × four seasonal variants), verifies the expected file count, and publishes a downloadable artifact.

## First seasonal batch
Eight asset families are exported as four distinct GLB files each (`_spring`, `_summer`, `_autumn`, `_winter`): spruce, pine, birch, mixed shrub cluster, fern cluster, mossy rock, mossy stump, and fallen log.

Seasonal variants alter foliage palettes and surface appearance. Winter birch and shrub variants remove deciduous leaf geometry; evergreen variants receive snow patches; moss, fern, stone, and deadwood shift toward cold-season appearances. These are procedural first-pass models, not final scanned photogrammetry. Next passes should add high-resolution PBR bark/needle/leaf textures, more regional species, a skinned character, collision proxies, LODs, and biome-specific ecological variants. Keep model generation deterministic.
