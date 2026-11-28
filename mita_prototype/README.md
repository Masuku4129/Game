# Mita Prototype 01

A focused prototype scene: ground plane, fixed 45-degree isometric camera, stylized Mita character and simple walk/run animation with touch joystick and keyboard support.

## Current implementation
- Godot 4 project (mobile renderer).
- Single ground plane, cool dark palette.
- Orthographic camera at 45-degree tilt.
- Articulated character assembled from meshes with pivot nodes.
- Idle breathing sway, walk/run limb swing, directional turning.
- Left-side touch joystick; keyboard arrows/WASD through Godot UI actions; Shift to run.

## Scope
No story, terrain dressing, NPCs, combat, or extra gameplay systems. This is only the character and basic locomotion sandbox.

## Important
The character is currently a procedural mesh prototype, not a finished imported sculpted GLB character. Replace this prototype geometry with a proper authored/generated rigged character asset when one is available.


## Character asset work (current)
See [ASSET_PIPELINE.md](ASSET_PIPELINE.md) for the account-free source strategy and the download helper. The current procedural Mita is still placeholder geometry, not the required final art model. Touch joystick drag routing was fixed in commit 203a71d.
