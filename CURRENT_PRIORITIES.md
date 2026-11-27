# TAIGA — Current priorities (2026-11-27)

This document supersedes character-model work as the immediate priority. Keep the existing character unchanged for now.

## User-reported issues
- Device heat is high on Samsung Galaxy S25 Ultra.
- Terrain and objects visibly generate in front of the player; world streaming is noticeable.
- FPS is poor despite flagship hardware.
- Rock collision feels absent or unreliable.
- Animals get stuck in trees, rocks, and terrain textures; movement/animation and run speed feel unnatural.
- The marsh/swamp biome is still missing.
- The intended unified cartoon style has not been applied consistently.

## Priority order

### P0 — Stable, performant world generation
- Stop visible in-front-of-player generation: generate chunks asynchronously/off-thread where Godot permits, use staged scene instantiation and a bounded generation budget per frame; maintain a safe preload radius ahead of the camera/player.
- Avoid rebuilding unchanged terrain/vegetation. Cache deterministic chunk results by seed and coordinates.
- Reuse meshes/materials/resources; batch static vegetation and repeated props with MultiMeshInstance3D where appropriate.
- Use distance-based density reduction and LOD/impostors for far vegetation; avoid expensive per-frame scans and per-object scripts.
- Establish a frame-time budget and monitor thermal throttling; don't trade smoothness for visual density.

### P0 — Collision, navigation, and animal movement
- Rocks and large landscape objects must have working collision shapes aligned to visible geometry. Use simplified, deliberate collision meshes (not fragile detailed trimesh for every small prop).
- Ensure collision layers/masks are consistent for player, animals, terrain, and obstacles.
- Animal navigation must use walkable terrain and obstacle-aware pathing. Avoid trees/rocks during path selection; detect blocked paths, recover/repath, and prevent repeated stuck states.
- Add local avoidance/separation and terrain slope/step constraints; don't let animals walk through props or jitter against collision.
- Review animal animation state transitions, blending, acceleration/deceleration, turning, gait cadence, and species-specific speed ranges. Remove arbitrary high run speed; running should be a state with believable ramp-up and stamina/behavior constraints.

### P1 — Unified low-cost cartoon art direction
Adopt a stylized, cohesive 3D cartoon / hand-painted low-poly look across the entire game, not a mix of realistic blurred textures and primitives:
- clean readable silhouettes, deliberate shape language, soft faceted geometry, restrained outlines only if used consistently;
- consistent material palette, roughness, lighting, shadows, and texture resolution;
- authored/stylized texture detail (not blurry stretched texture sheets), with palette variation and subtle surface breakup;
- characters and animals must remain anatomically readable, with coherent proportions and stylized models/rigs;
- no uncolored default primitives, placeholder-looking spheres/cylinders/cones, or disconnected model parts.
- Keep the look performant: baked/static shading where suitable, modest material count, atlas textures, limited transparent foliage, and simplified shaders.

Create a style guide/palette and asset acceptance checklist before bulk replacement; then apply it to trees, shrubs, rocks, ground, water, animals, props, and seasonal variants.

### P1 — Biome and terrain diversity
Replace repetitive ground/forest patches with controlled biome composition and transition zones. Include distinct visual and gameplay regions:
- mixed conifer/deciduous forest, dense taiga, open woodland, meadow/grassland;
- rocky slopes, cliffs, scree, outcrops and riverbanks;
- wetland, marsh and bog (the missing swamp biome);
- rivers, lakes, shorelines, fallen-tree clearings and burned areas.
Use elevation, moisture, temperature, drainage, slope, and noise layers to determine biome and transitions. Avoid abrupt tile boundaries; use blending/patch-based transitions and biome-specific vegetation distributions. Ground should have varied but coherent materials and color; terrain should not look like blurred primitive patches.

### P1 — Marsh/swamp implementation
Implement an actual wetland biome, not just dark ground:
- saturated ground, shallow standing water, mud, peat, pools and channels;
- reeds, sedges, cattails, rushes, willow/alder, moss, deadwood and sparse trees;
- water depth and wetness gradients, shoreline transitions, occasional dry hummocks;
- terrain movement modifiers (slower movement, mud interaction/footprints), with suitable collision and navigation costs for animals;
- avoid dense transparent effects and excessive draw calls.

### P2 — QA/acceptance
Test on Android at target resolution and record:
- average FPS and frame-time spikes, loading/generation stutter, memory use, device temperature trend;
- collision tests for player and multiple animal species against rocks, trees, cliffs and terrain;
- stuck-animal recovery, path replan and animation state tests;
- visibility of chunk boundaries/generation;
- visual consistency across biomes and seasons.

## Definition of done for this priority cycle
1. The cartoon style is visibly and consistently applied to the world and fauna; no placeholder primitives remain in the main view.
2. Terrain variety is materially improved, including a playable marsh biome with transitions.
3. Rock/large-prop collision is reliable and animals can navigate/recover from blockage.
4. Generation no longer visibly pops in directly ahead under normal movement.
5. FPS/thermal performance is improved using measured evidence, not claims.
6. Character model changes are deferred until the user explicitly re-prioritizes them.
