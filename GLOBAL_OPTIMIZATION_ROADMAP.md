# TAIGA — Global Performance & Scalability Architecture

Goal: modern mobile-first optimization across the whole game without reducing visible quality, vegetation density, animal logic, simulation fidelity, or gameplay features.

## Rules
- Preserve visual quality and simulation behavior; optimize scheduling, representation, memory, and work distribution.
- No blanket reductions in draw distance, vegetation density, texture quality, animal intelligence, or physics fidelity as the first solution.
- Every subsystem has a quality/performance budget and profiling counters. Budgets schedule work; they do not silently delete content.
- Keep this architecture compatible with current Godot 4.3 mobile renderer and landscape orientation.

## Priority roadmap

### P0 — Startup pipeline
- Convert startup into explicit phases: seed/save resolution, cached resources/materials, terrain data, water, deterministic placement data, near-start scenery, player/camera/UI, wildlife, remaining vegetation.
- Display world immediately after core playable state is ready; stream remaining content asynchronously.
- Add frame-yield/time-budgeted generation jobs instead of long blocking loops.
- Cache shared meshes/materials and avoid repeated resource loads and mesh construction.
- Preserve deterministic generation using stable seeds and versioned generation IDs.

### P1 — World generation & streaming
- Split terrain/vegetation/water into independent spatial cells.
- Prioritize cells by distance, camera visibility, player movement direction, and gameplay relevance.
- Reuse cell nodes and MultiMesh allocations where safe; pooled scene instances.
- Avoid rebuilding unchanged terrain/material/vegetation.
- Keep current near-view quality; use far LOD representations with transition bands and cross-fades.

### P2 — Rendering
- MultiMesh for repeated vegetation and small props.
- LOD tiers for trees, rocks, plants, animals, buildings and water details.
- Distance-aware shadows: retain high-quality nearby shadows; disable or bake distant small-object shadows.
- Cull by camera frustum and occlusion where appropriate; avoid per-object CPU work.
- Texture atlasing / shared materials / shader variants to reduce state changes and draw calls.
- Shader work should be shared and uniform updates grouped, throttled only when values are unchanged.

### P3 — CPU / simulation
- Separate high-frequency hero controls and physics from wildlife AI, needs, weather, foliage motion, exploration and UI.
- Animal simulation uses distance tiers: near full behavior, mid-rate decisions with interpolated movement, far lightweight state/position simulation. Preserve ecology, hunting, flee and habitat outcomes.
- Spatial hashing for nearby animal, tree, collision, resource and interaction queries.
- Move pure data generation to WorkerThreadPool only when it is thread-safe; scene-tree mutations remain on main thread.
- Schedule non-critical jobs against frame-time budget and prioritize interactive gameplay.

### P4 — Memory / asset lifecycle
- Shared resource cache for meshes, materials, textures and animation resources.
- Chunk streaming with explicit ownership, unload policy, pooled objects, and save-dirty tracking.
- Bound caches; avoid duplicate textures/meshes and unbounded per-chunk dictionaries.
- Reuse packed arrays and reduce temporary allocations in hot loops.
- Compress imported assets appropriately for Android (ASTC/ETC2 as supported) without degrading source art.

### P5 — Physics, collision and interaction
- Use coarse spatial broadphase and simplified collision for distant/uninteractable objects; detailed collision near player.
- Keep precise interaction and animal navigation around the player.
- Batch collision changes; avoid rebuilding collision shapes each frame.
- Preserve footprint, snow/mud, vegetation compression, climb, swimming, bog and terrain responses.

### P6 — Mobile adaptation
- Dynamically schedule optional work using measured frame time, thermal state if accessible, and device capability.
- Adaptive resolution only as a last resort and bounded, with stable visual quality and no aggressive oscillation.
- Separate quality profiles by GPU/CPU/memory class; never reduce population or density without explicit profile data.
- Support sustained frame pacing and avoid startup/frame spikes.

### P7 — Save / persistence
- Persist only changed chunk state; version save schema.
- Avoid serializing full generated terrain and unchanged procedural content.
- Restore visible nearby chunks first, defer distant saved-state application.
- Deterministic generation seed + sparse changes keeps saves compact.

## Work sequence
1. Startup hitch removal and async generation budget.
2. Shared-resource cache and reusable generation buffers.
3. Chunk scheduler prioritization and prefetch prediction.
4. MultiMesh/LOD/culling and material consolidation.
5. Animal AI spatial query and distance-tier scheduling.
6. Physics/collision broadphase and near/far tiers.
7. Save/persistence dirty-chunk optimization.
8. Mobile thermal/frame pacing adaptation.
9. Add profiling overlay and measured baseline; tune only from evidence.
10. Final APK build and device validation after implementation batches.

## Current known hotspots
- Startup calls terrain generation, water, scatter, vegetation prebuild, and initial animal/beaver population before startup UI is removed.
- Terrain mesh uses a 384-segment grid (147,456 height samples) and already yields periodically.
- Vegetation scatter already yields between groups, but generation needs an explicit frame-time budget and prioritized scheduler.
- Grass cells are generated in strips; startup prebuild now targets a smaller 3x3 area and yields between strips.
- Chunk streaming uses 64 m cells with active/preload radii; generation/unload queue is processed in main thread.

## Current changes
- Startup grass prebuild radius reduced from 5x5 to 3x3 cells while keeping grass density and quality.
- Grass prebuild now yields after each 8 m strip, avoiding a continuous synchronous cell-generation block.
- This is an initial startup responsiveness improvement, not the end of the optimization effort.

## Acceptance
- No visual density or art-quality regression.
- No reduction in animal/ecology or gameplay logic.
- Faster time-to-first-playable and no severe frame spikes during initial generation/streaming.
- Stable sustained performance on target mobile devices, measured in actual device builds.
