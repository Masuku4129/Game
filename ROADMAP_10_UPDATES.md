# 10-Update Roadmap — Performance-First Wilderness Survival

## Guiding principle
Do not scale feature count at the expense of stability. Preserve the ambition for a dense, attractive, living wilderness, but achieve it through mobile-first architecture, workload budgeting, streaming, batching, and adaptive quality—not by repeatedly cutting content. Treat sustained 30 FPS as the initial target and 60 FPS as an optional quality/performance mode; targets must be measured on actual hardware and are not guarantees.

## Update 1 — Startup stability and world streaming
- Remove global world-generation work from startup.
- Keep the 512×512 world bounds/map and chunk streaming approach.
- Generate only nearby/needed chunks, spread work across frames, avoid visible pop-in.
- Profile startup, memory, frame-time spikes; make first playable scene robust.

## Update 2 — Model/resource pipeline
- Replace visibly primitive placeholder assets with authored stylized 3D models.
- Reuse meshes/materials/textures where appropriate; resource cache and lifetime rules.
- Add distance-based LOD and simplified distant representations.
- Avoid excessive unique materials and draw calls.

## Update 3 — Dense forest ecosystem
- Increase visual richness/density (desired ~2.5× where performance allows).
- Add varied pine, spruce, cedar, larch, birch/aspen, shrubs, fern, moss, grass, fungi, fallen logs, roots and rocks.
- Use MultiMesh/instancing, chunk-local placement, deterministic variation, frustum/occlusion and distance culling.
- Density must be adaptive to performance; avoid individual heavyweight nodes for every plant.

## Update 4 — Terrain and biomes
- Varied relief, hills, slopes, depressions, ravines, streams, rivers, ponds and wetlands.
- Biome transitions should be natural and blended, not hard boundaries.
- Keep terrain/biome generation chunk-based and cache reusable data.

## Update 5 — Wildlife and AI
- Wildlife roster and ecosystem interactions (for example deer/moose, fox, wolf, hare, squirrel, bear).
- Near/far simulation tiers, reduced update cadence at distance, pathfinding constraints and obstacle recovery.
- Fix stuck animals and squirrel climbing; animals react to player and each other.
- No costly full-detail AI for distant creatures.

## Update 6 — Weather, seasons and atmosphere
- Four seasons, rain/snow/wind/fog, day/night, seasonal foliage colors and snow accumulation visuals.
- Shared global weather state with local lightweight effects.
- Particle, shader and lighting costs capped; effects adapt to load.

## Update 7 — Nature interaction and surface feedback
- Footprints in snow/mud, grass bending, shrub response, animal tracks.
- Prefer localized decals, texture masks or other efficient visual methods over expensive per-object physics.
- Terrain friction/movement effects localized and budgeted.

## Update 8 — Character and survival loop
- Improved character model, locomotion and action animations.
- Responsive mobile controls and camera.
- Resource gathering, inventory, hunger, thirst, fatigue, body temperature.
- Surface-aware movement without expensive continuous physics where unnecessary.

## Update 9 — Camp, crafting, construction and persistence
- Fire, shelter, tools, crafting and cooking.
- Placeable structures and object interaction.
- Save player, inventory, placed objects and changed chunk state; load without regenerating the entire world.

## Update 10 — Integration and mobile quality
- Integrate systems and fix regressions.
- Adaptive settings for render distance, LOD, shadows, resolution and effects.
- Long-session stability and memory-pressure checks; package a verified APK.
- Report evidence honestly: automated checks and logs are not substitutes for a real-phone test.

## Engineering gates for every update
1. Keep the game bootable and playable.
2. Avoid full-world work at startup; budget generation per frame.
3. Bound memory, active nodes, draw calls, AI ticks and effects.
4. Profile before and after each meaningful change; optimize bottlenecks, not guesses.
5. Preserve visual quality through scalable techniques, not blanket asset removal.
6. Verify build, smoke tests and regressions; never claim device validation without a real-device run.
7. Do not start the next update if the current one introduces a critical startup, crash, memory or performance regression.

## Current order
Stability and streaming first; then asset pipeline, vegetation, terrain, wildlife, weather, interaction, survival, camp/persistence, and final integration. This is a living roadmap; actual sequencing can change when profiling exposes a blocker, but performance-first principles remain mandatory.
