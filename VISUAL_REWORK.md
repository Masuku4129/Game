# Forest Walk — Visual & Environment Rework

## Core target
- Landscape mobile survival/wilderness exploration.
- Fixed, close, steep overhead/isometric camera that follows the player without rotating.
- Original stylized wilderness identity: natural silhouettes, varied forest density, colorful layered foliage, detailed ground and vegetation.
- Trees must be large relative to the player; foliage fades when it obstructs the player.
- Smooth player movement and walk cycle without skating.
- Weather and seasons materially change scenery, ground, visibility, and interaction.
- Samsung S25 Ultra target: 60 FPS objective, device profiling required before claims.

## Required visual/game systems
- Forest species variety (deciduous/conifer/mixed forms), branching trunks, asymmetrical crowns and pointed leaf shapes.
- Understory bushes, ferns/grass, wildflowers, stones, roots, fallen logs, ground cover and varied forest floor.
- Procedural ground with subtle unevenness, distinct soil/leaf/moss/grass surfaces.
- Player model with readable silhouette, clothes, backpack and field tool; articulated walk animation.
- Wind sway, dynamic light, atmospheric fog.
- Weather: clear, rain, fog, snow; rain wetness, mud/puddles, footprints and body impressions; snow accumulation, drifts and footprints.
- LOD/culling and bounded memory/particle systems.

## Current native Android renderer
Project uses Kotlin + OpenGL ES 2.0 under `app/src/main/java/com/masuku/forestwalk`.

Implemented in source (CI build evidence only; no device visual test):
- Reusable mesh builder for ellipsoids, tapered cylinders and triangle surfaces; CPU merging of static meshes.
- Procedural multi-branch trees with exposed roots, branch structure and pointed leaf clusters, deterministic species/size variations.
- Batched tree chunks and understory shrubs.
- Ground detail blades, wildflower clusters and rocks, batched by chunk.
- Triangulated forest floor with subtle undulation and randomized green/earth color palette.
- Close fixed follow-camera, joystick movement and movement-direction turn.
- Shader lighting, surface grain, foliage wind sway and proximity-based canopy transparency.
- Clear/rain/snow/fog mode selector; rain/snow particles; wet tint; snow shading varies by height and surface normal; fog depth effect.
- Basic player gait/bob and clothing/backpack/headwear/tool mesh details.

## Known gaps / must not be described as complete
- Character animation is still shader-based deformation of a static mesh, not a true articulated rig with gait phases.
- Terrain is shallow, fixed-size and not streamed; no actual collisions, paths, streams, slopes, or biome generation.
- Weather is visual only: no persistent wetness, puddles, mud, rain splash, snow depth, drifts, or footprints/body impressions.
- Seasons beyond weather states and seasonal vegetation swaps are not implemented.
- Trees and ground detail remain procedural geometry; style quality must be visually assessed in a real build/device.
- Foliage fade and blending are unverified visually; render ordering may need correction.
- No real-device FPS, memory, touch, thermal or stability profiling has been done.

## Work sequence
1. Improve visual asset/model silhouettes and materials beyond primitive-looking forms; verify each build visually.
2. Replace basic character mesh deformation with a true articulated rig and walk animation.
3. Add terrain collision, procedural biomes and world streaming.
4. Implement weather/season surface effects and persistent interaction marks (footprints, mud/snow deformation, puddles/drifts).
5. Optimize LOD, visibility, batching, memory and mobile frame time; test on the S25 Ultra.

## Performance guardrails
- Batch static scenery, avoid hot-loop allocations, cull by distance, keep particle counts bounded.
- Keep mesh chunks under GLES2 16-bit index limits.
- 60 FPS is a target, not a verified result. Record frame-time and device evidence before claiming success.
