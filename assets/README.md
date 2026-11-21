# Procedural 3D asset pipeline

This repository generates source-controlled, deterministic 3D environment assets with Blender's Python API. No image-generation quota or paid image API is required.

## Generate locally
```bash
blender --background --python tools/generate_assets.py -- --output assets/generated
```

## CI
GitHub Actions workflow **Generate 3D asset pack** installs Blender on an Ubuntu runner, generates 32 GLB models (eight asset types × four seasonal variants), verifies the expected file count, and publishes a downloadable artifact.

## First batch
- spruce, pine, birch
- mixed shrub cluster, fern cluster
- mossy rock, mossy stump, fallen log

These are procedural first-pass geometry assets, not final scanned photogrammetry. The next iteration adds physically based bark/needle/leaf textures, a skinned character, collision proxies, LODs, and biome-specific variants. Keep model generation deterministic.
