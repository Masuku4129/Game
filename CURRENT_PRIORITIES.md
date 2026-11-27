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


### P0 — Rendering performance and heat control
- Profile CPU/GPU and frame time on-device; target a stable frame budget rather than peak FPS.
- Move procedural calculations off the main frame where safe; spread scene creation over frames with strict per-frame spawn budgets and prewarm ahead of the visible edge.
- Use chunk lifecycle pooling, deterministic caching, instancing/batching, culling, and distance tiers; avoid unnecessary transparent foliage and shadow casting.
- Add quality tiers that adapt foliage density, shadow distance/resolution, water effects, and ambient detail to frame time and thermal state; avoid abrupt quality flicker.

### P1 — Lighting and cohesive stylized rendering
- Establish consistent cartoon material palette, surface roughness, shape language, color ramps, and ambient treatment across the world, props, fauna, UI.
- Tune sunlight direction/intensity, sky/environment illumination, ambient occlusion, shadow distance and softness, fog depth, and exposure for readable forest depth without excessive real-time cost.
- Prefer baked/static or low-cost lighting where feasible; avoid many dynamic lights and expensive per-object shader effects.
- Validate that rock, terrain, water, foliage, and animals remain legible under daylight, overcast, fog, dusk/night and seasonal variants.

### P1 — UI overhaul
- Redesign HUD and menus as a single stylized, readable visual system (typography, icons, spacing, panels, palette, feedback and touch targets).
- Make mobile controls and information hierarchy usable in landscape; avoid clutter and obstruction of terrain view.
- Replace inconsistent default UI widgets with themed components; maintain accessibility contrast, scalable layout and safe-area handling.
- Review inventory, crafting, survival indicators, map, pause/settings and contextual interaction states for coherent interaction patterns.

### P1 — Animation overhaul (character work deferred)
- Improve all animal animation cycles and state transitions: idle, alert, walk, trot, run, turn, stop, graze/forage, drink, flee and rest as appropriate per species.
- Use smooth acceleration/deceleration, turn-radius constraints, speed-to-gait matching, foot placement and transition blending; prevent sliding and snapping.
- Ensure locomotion speed, animation playback rate and navigation velocity remain synchronized; remove unnatural burst speeds.
- Character visual model stays unchanged; animation/control foundations may be reviewed without replacing the model until reprioritized.

## Definition of done for this priority cycle
1. The cartoon style is visibly and consistently applied to the world and fauna; no placeholder primitives remain in the main view.
2. Terrain variety is materially improved, including a playable marsh biome with transitions.
3. Rock/large-prop collision is reliable and animals can navigate/recover from blockage.
4. Generation no longer visibly pops in directly ahead under normal movement.
5. FPS/thermal performance is improved using measured evidence, not claims.
6. Character model changes are deferred until the user explicitly re-prioritizes them.
