# Reference mechanics preservation contract

The Claude-created Wildlands reference is the behavioral baseline. Its source is HTML/Three.js; the Python simulation core is kept separately from the renderer. The Panda3D port must reproduce the systems below, not replace them with a reduced demo.

## Preserved simulation systems

- Deterministic procedural world sampling with continuous terrain height, slope, moisture, canopy, biome weights, snow exposure and mud susceptibility.
- Streamed world chunks (72 m), deterministic terrain grids, biome-weighted tree placement and dense understory/object patches.
- Distinct biomes: mixed forest, conifer forest, clearing, wetland and rocky upland.
- Broad ecological object catalogue: ferns, shrubs, mossy rocks, boulders, fallen logs, stumps, mushrooms, grass, branches, wildflowers, cattails, roots, pinecones, deadwood, berry bushes, reeds, saplings, leaf litter, lichen, bracken, heather, thistle, burrows and bark.
- Four seasons with automatic cycle and manual override.
- Automatic and forced clear/rain/storm/snow weather, transitioning cloud/rain/snow/fog/storm values and variable/gusty wind.
- Wetness, snow cover, puddle accumulation, snow loading on tree crowns and wind/rain shedding.
- Camera-relative locomotion with inertia, heading smoothing and slope/world-bound movement constraints.
- Movement penalties for deep snow and deep mud; character vertical immersion/grounding response.
- Footstep cadence, left/right footprint placement, surface classification (snow/mud/earth), persistence, weather/season-dependent fading and a bounded history.
- Render-side visual systems from the reference must also be ported: ground and surface shaders, snow/mud/puddle deformation and tracks, rain/snow particles, ground drift, wind-driven tree/grass/leaf motion, fog/cloud/storm lighting, lightning/thunder, ambient rain/wind audio, water plane, camera, character and touch controls.

## Explicit exclusions

- Do not delete or silently omit a reference mechanic to make the first APK smaller.
- Do not substitute primitive stand-ins for authored character or environment models.
- Do not claim a mechanic is complete because its data model exists; it must be connected to the runtime, rendered, and tested.
- Do not claim device performance or visual verification from headless CI tests.

## Porting strategy

The complete Python simulation core lives in `python_game/world/reference_core.py`. Panda3D runtime integration must consume this core as the source of truth. Renderer-specific effects are ported as separate Panda3D systems while preserving all gameplay state and controls. Optimization is permitted only when behavior remains equivalent; use chunk visibility, instancing, LOD and adaptive quality rather than deleting systems.

## Verification

- Unit tests cover deterministic chunks/ecology, weather and season controls, locomotion, terrain response and footprint generation.
- CI must validate all Python modules and tests before packaging.
- A successful APK export is not evidence of visual or physical-device correctness.
