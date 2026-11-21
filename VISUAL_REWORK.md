# Forest Walk — Visual & Environment Rework

## Acceptance targets
- Mobile landscape, close fixed overhead camera (no camera rotation), follows the player.
- Organic mesh silhouettes; no visible block/cube assembly. Trees, bushes, rocks and player use multi-part geometry with smooth surfaces.
- Every generated tree has >=25 geometry components; player rig >=50 geometry components.
- Dynamic lighting and atmospheric depth; transparent foliage fade when it occludes the player.
- Wind-driven foliage animation.
- Weather state machine: clear, rain, fog, snow.
- Rain wetness: wet-ground shader response, puddles, mud, persistent footprints/depressions.
- Snow: accumulation on terrain and tree surfaces, drifts, persistent footprints/depressions.
- 60 FPS target on Samsung S25 Ultra; measured device performance required before declaring success.

## Implementation order
1. Replace cube-based rendering with reusable mesh generation (ellipsoids, tapered cylinders, cones, curved branches) and batched vertex buffers.
2. Build diverse procedural trees, bushes, rocks, forest floor and an articulated player rig.
3. Implement animation blending, wind, camera occlusion fade for foreground foliage.
4. Add weather transitions, rain/snow particles, wetness and snow accumulation, puddles/drifts and footprint stamps.
5. Profile, reduce draw calls, add LOD/visibility culling, and tune frame-time/memory budgets.

## Performance guardrails
- Batch static scenery by material.
- Avoid per-object draw calls and per-frame allocation in hot rendering paths.
- Frustum/distance cull; use lower-detail silhouettes for distant objects.
- Bound particles and decal/footprint buffers.
- Verify with frame-time telemetry on-device; 60 FPS is a goal, not a verified result.

## Current baseline
Native Android OpenGL ES renderer in app/src/main/java/com/masuku/forestwalk/MainActivity.kt is a prototype. It currently uses scaled cube meshes and simple movement. It does not satisfy the acceptance targets above. This document is the canonical work plan for this rework.
