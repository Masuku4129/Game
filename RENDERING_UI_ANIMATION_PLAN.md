# TAIGA Rendering, UI, Lighting & Animation Workstream

Date: 2026-11-27
Scope: mobile landscape gameplay. Character model replacement remains deferred. This is an implementation specification, not a claim that runtime changes have already shipped.

## Shared art-direction contract
- Style: cohesive stylized 3D cartoon / hand-painted low-poly, grounded proportions, clear silhouettes and readable forms. Do not mix photoreal blurry texture maps with primitive-looking assets.
- Material system: restrained shared palette; consistent roughness; few reusable materials; palette variation through cheap vertex colors or shared atlas where appropriate. Avoid default untextured primitives in camera view.
- Shapes: broad primary masses, carefully designed silhouette, bevel/facet variation, secondary detail only when it reads at gameplay camera distance.
- Asset scale and lighting must be judged from the fixed landscape gameplay camera, not asset close-up previews.

## Parallel workstreams (independent interfaces, integrate serially)

### Workstream A — Frame budget, heat, world streaming
1. Establish baseline on Galaxy S25 Ultra if device profiling is available: frame-time percentiles, CPU/GPU bottlenecks, memory, thermal trend, generation spikes. Never claim phone measurements if unavailable.
2. Bound work per frame. Precompute chunk data without scene nodes; instantiate a small capped number of nodes per frame. Keep chunks ahead of camera in a ring/queue so visible terrain is ready before arrival.
3. Deterministic chunk IDs from seed+coordinate. Cache reusable results and do not regenerate unchanged content.
4. Pool recurring nodes; instance repeated static vegetation and rocks; consolidate materials; cull outside camera and avoid per-instance scripts.
5. Add LOD tiers: full near detail, reduced mid distance, cheap far silhouettes/instances. Limit shadow casters to near/important assets.
6. Dynamic quality controller may reduce foliage count, shadow distance, water animation/effects and distant detail when frame time stays over budget. Smooth tier transitions to avoid popping.
7. Keep collision geometry separate from high-detail visual meshes.

Acceptance: no obvious chunk pop-in at ordinary movement; generation spikes bounded; stable thermal behavior improves; runtime metrics available and honest.

### Workstream B — Collision and fauna navigation
1. Create a shared collision policy with named layer/mask matrix for world, static obstacle, animal, player, water and trigger.
2. Rocks/cliffs: simplified convex or authored primitive collision shapes that match their visible footprint; test large, small and overlapping rock clusters. Collision must be attached to correct transformed node.
3. Vegetation: trunks/large trees collide; leaves, branches, grass, reeds and small decorative foliage do not obstruct navigation unless intentionally designed.
4. Use the same obstacle map / nav data source for route planning and collision; avoid independent inconsistent blockers.
5. Animals use path-following plus local steering. On blocked movement, detect progress stall, stop, back/side step if suitable, invalidate/replan with cooldown, and use recovery fallback. Never loop forever against an obstacle.
6. Avoid steep slopes and impassable terrain, account for body radius and species footprint, and add local separation to prevent animal crowds.
7. Preserve per-species movement envelopes; cap acceleration, turn rate, and speed. Walk/trot/run are distinct states, with run used contextually rather than constant high speed.
8. Keep locomotion state and animation velocity coupled. Stop, pivot, and transition smoothly; no sliding/jitter or abrupt state snaps.

Acceptance: reproducible obstacle tests; animals cannot pass through rocks or tree trunks, do not become stuck indefinitely, and recover within a bounded time. Document test evidence.

### Workstream C — Biome and procedural landscape quality
Use multiple deterministic environmental fields instead of single noise-to-biome lookup:
- elevation and slope;
- temperature/season;
- moisture, drainage and water table;
- local disturbance/clearing factor;
- biome identity and transition masks.

Build natural patch compositions with soft boundaries and overlap. Include mixed forest, conifer-dominant taiga, deciduous pockets, meadow/clearings, rocky outcrops, scree, stream/rivers/lakes, floodplain, wetland and bog. Avoid repeating the same patch composition across adjacent chunks.

Ground presentation should layer a small palette of stylized ground materials and sparse meshes (grass clumps, leaf litter, stones, moss) with stable deterministic distribution, rather than blurry texture overlays or hundreds of individually scripted nodes.

### Workstream D — Wetland / swamp biome
The wetland must be gameplay-visible and distinct:
- water-table mask and shallow water pools/channels;
- peat/mud with saturated darkened palette and stylized wet highlights;
- dry hummocks and irregular islands to break up water;
- reeds, rushes, sedges, cattails, willow/alder, moss, deadwood and sparse trees;
- smooth edges and transitions to forest, meadow and stream banks;
- movement drag/speed modifier for deep mud, shallow water and dry ground; footstep/footprint visuals scaled to substrate;
- navigation cost and avoidance that make animals prefer firmer ground when appropriate.
Keep water effects cheap: shared materials, limited transparency, low-frequency animation, no expensive per-pixel effects in large areas.

Acceptance: biome can generate at seeded coordinates; transitions do not show abrupt tile seams; walkable and wet areas correctly affect movement/navigation.

### Workstream E — Lighting / atmosphere
- One coherent sun/moon directional source with controlled shadow budget.
- Sky/environment light supplies soft ambient fill; tune color and energy to stylized palette.
- Contact shading/ambient occlusion used sparingly to ground rocks, trunks and props without over-darkening.
- Fog is depth-based and subtle, used for forest distance and atmospheric perspective, not as a substitute for missing geometry.
- Exposure/tonemapping stable; avoid flicker and extreme contrast.
- Seasonal and weather lighting presets share the same color-grade rules: clear, overcast, rain, fog, dusk/night, snow.
- Minimize dynamic lights; campfire lighting is localized and budgeted. Distance and shadow settings must be mobile-aware.

Acceptance: scenes remain readable at gameplay zoom in all presets, performance cost measured, no harsh mismatched materials.

### Workstream F — UI and touch UX
Build a unified mobile landscape HUD and menu language:
- hierarchy: unobstructed play area first; small survival status cluster; context action near relevant object; compact navigation/map access; pause/settings;
- controls: thumb joystick and contextual action buttons sized for thumb reach and safe margins; no accidental overlaps;
- indicators: health/stamina, hunger/thirst/temperature only when meaningful, with icons + readable labels/state changes rather than excessive bars;
- visual language: stylized panel shapes, coherent typography, icon family, spacing, restrained opacity, consistent selected/pressed/disabled feedback;
- menu system: inventory, crafting, map, settings and pause use same components, consistent navigation/back behavior and no default-widget mismatches;
- adapt to notches/safe areas and different landscape aspect ratios; test scale/contrast and text readability.
Do not add HUD elements without gameplay value. No UI overhaul should compromise touch responsiveness.

Acceptance: complete UI walkthrough in landscape at target phone size; safe-area check; no overlap, clipped controls, unreadable text or inconsistent default styling.

### Workstream G — Animation polish (character model deferred)
- Animals: species-aware locomotion cycle, idle variation, alert, walk/trot/run, turn, stop, rest, forage/drink where supported, flee and return.
- Blend state changes with speed/turn and use acceleration/deceleration. Match stride cycle to velocity to prevent foot sliding.
- Use turn radius and body orientation that respect momentum; no instant pivot while sprinting.
- Remove animation states that are not backed by a real cycle; do not disguise missing animations with static pose or random twitch.
- Check rig proportions, bone constraints, blend weights, foot planting, loop seam, and timing for each species.
- Character model replacement is not part of this phase; only shared animation-system foundations if they don't force a character redesign.

Acceptance: transitions are smooth, movement and gait are synchronized, no floating feet/sliding/teleport pose, and animation speeds feel grounded.

## Integration and verification order
Integrate one workstream at a time into the main branch to reduce regressions:
1. Baseline/profile and world streaming.
2. Collision/nav policy.
3. Art palette/material/shader base.
4. Biome diversity and swamp.
5. Lighting/atmosphere presets.
6. UI components and HUD.
7. Fauna animation tuning.
8. Android build, smoke tests, performance pass, and visual QA in the same camera framing.

## Required verification evidence
- Build exit status and artifact link/path.
- Seeded chunk tests and generation timing.
- Collision matrix and stuck recovery tests.
- Device profile: frame-time/FPS, memory, heat; mark unavailable if not measured on phone.
- Screenshots for unified art style, each biome, lighting presets, HUD screens.
- APK only after integration build succeeds. Do not report planned or unverified changes as implemented.
