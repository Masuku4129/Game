# Art direction — fantasy ruins and purple magic

## Source references
The image sheets supplied in the conversation are the primary visual references for the current art direction. Use them as visual guidance, not as flat textures to stretch across the world.

## Visual pillars
- **Dense, handcrafted environments:** modular stone arches, broken walls, stairs, bridges, platforms, columns, gate structures, and architectural fragments.
- **Layered natural dressing:** trees with readable silhouettes, bushes, ground cover, vines, roots, rocks, fallen logs, water features, and mushrooms/crystals where appropriate.
- **Purple magical identity:** violet banners, luminous crystal clusters, rune-like accents, restrained magical glow, and blue-violet environmental lighting.
- **Materials:** varied stone blocks with chipped edges, moss, dark wood, weathered metal, fabric folds, emissive crystal surfaces, and textured ground. Avoid smooth untextured primitives as final assets.
- **Atmosphere:** fog depth where it improves readability, dramatic but readable light pools, high contrast focal areas, and dark cool surroundings.

## Modular environment construction
Build environments from reusable authored modules that can be combined into distinct silhouettes:
- arches, straight wall segments, corner walls, broken wall variants, gates
- column families, capitals, bases, damaged variants
- stair sections, landings, bridge decks, parapets
- decorative banners, lamps, braziers, statues, carts, crates, containers
- crystal clusters, trees, shrubs, stones, ground vegetation
- waterfalls, streams, pools, wet shoreline transitions

Use multiple variants and irregular placement. Repetition must be masked through orientation, scale variation within bounds, damage, vegetation, and lighting. Keep collision geometry simplified but aligned to visible geometry.

## Camera and mobile readability
- Keep landscape orientation and a close enough camera to read character and props clearly.
- Avoid zooming out to show the whole arena at the cost of detail.
- Maintain clear player silhouette, navigation paths, and combat spaces.
- Mobile performance: instance/merge repeated geometry where practical, limit dynamic lights, use LOD or distance-based detail, and preserve readability.

## Asset acceptance criteria
Reject assets or builds where:
- major props appear as obvious colored cubes/cylinders/cones;
- terrain looks blurred or uniformly primitive;
- character silhouette is too small to read in landscape gameplay;
- modular seams are visible or pieces float/misalign;
- vegetation density is sparse or repetitive;
- lighting blooms so strongly that detail is lost.

## Implementation sequence
1. Establish the visual target with a compact playable scene and close landscape camera.
2. Upgrade the primary environment modules and materials before expanding the map.
3. Add dense natural dressing and variation.
4. Integrate player readability, camera, touch controls, and interaction.
5. Verify on Android export and optimize only after visual inspection.
