# Python engine port

## Goal

Replace the Godot prototype as the active runtime with a Python/Panda3D implementation, using the uploaded Wildlands APK as a behavioral reference and reusing the project's own GLB assets.

## Reference APK findings

The uploaded `Wildlands.apk` contains a WebView-style HTML application, `assets/index.html`, and `assets/three.min.js`. Its game logic is inline JavaScript using Three.js. It is a reference implementation, not a source project that can be directly rebuilt as Python.

## Runtime

- Python application code.
- Panda3D 1.11.0, whose official Android packaging support uses `build_apps`.
- Android target: arm64-v8a.
- Android output: signed universal APK derived from the Panda3D AAB using Google's bundletool.
- GitHub Actions remains the sole automated Android build pipeline.

## Migration boundary

The current Godot project remains intact while the Python runtime is proven. Python code lives under `python_game/`. Do not mix Godot and Panda3D nodes or runtime code. Reuse GLB assets by loading them through Panda3D's glTF support; do not replace the authored assets with permanent primitive placeholders.

## Port order

1. Prove Python/Panda3D host startup and Android packaging in GitHub Actions.
2. Reproduce the reference's landscape camera, touch joystick and player movement.
3. Port deterministic terrain, biome distribution, foliage instancing and weather.
4. Integrate the existing character and environment GLB models.
5. Retarget/supply smooth locomotion animations and verify facing direction.
6. Port snow, mud, footprints, water and surface response.
7. Profile on the Samsung S25 Ultra and tune mobile quality settings.

## Current status

- Isolated port branch: `python-panda3d-port`.
- Added a Panda3D Python scene bootstrap and deterministic terrain height-field module.
- Added a single-finger on-screen joystick, camera-relative movement math, smoothed acceleration/deceleration, travel-facing rotation and idle/walk/run animation-state selection.
- Set the camera elevation to approximately 60 degrees, increased the forest placement grid to roughly 500 tree instances and added a procedural tiled soil/moss albedo texture.
- The scene loads existing seasonal spruce, pine and birch GLBs, and the existing rigged explorer GLB; no substitute primitive is spawned when the authored character model is absent.
- Added a GitHub Actions workflow that tests terrain sampling, downloads the official Panda3D 1.11.0 Android ARM64 wheel, converts included GLBs to BAM during packaging, builds an AAB and converts it to a signed universal APK.
- Local pure-Python checks: 6 passed (terrain determinism/continuity and camera-relative movement/heading).
- The Android workflow has not yet been confirmed successful. No APK from the Python port is available yet.
- The current scene does not yet include the final mobile joystick, camera-follow movement, full weather/surface simulation or all seasonal runtime transitions.
- Physical-device rendering and performance remain unverified.
