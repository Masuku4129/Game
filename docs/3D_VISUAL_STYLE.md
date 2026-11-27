# TAIGA — 3D Visual Style Guide (current graphics-first baseline)

## Core art direction
A cohesive stylized 3D wilderness world: hand-painted cartoon realism with large, readable forms and grounded natural proportions. The look should feel like a crafted miniature wilderness, not photorealistic noise and not toy primitives.

## Shape language
- Silhouettes must be species- and object-specific and readable at landscape mobile camera distances.
- Organic forms use broad asymmetry and taper; avoid identical repeated spheres, cylinders, or obvious disconnected primitives.
- Vegetation crowns use large masses and irregular lobes. Branches, trunks, leaf clusters and needle groups should visually connect.
- Rocks, hummocks, stumps, fallen logs, marsh vegetation, animals, tools and settlement props should have a distinct primary silhouette plus restrained secondary details.

## Palette and materials
- Use natural but lively color families: pine/spruce greens, warmer larch and deciduous greens, bark browns, moss/peat olives, water blue-green, mineral greys, seasonal amber/rust, winter cool whites.
- Surfaces use clean broad color variation and painted regions, not high-frequency procedural noise.
- Species palettes should distinguish trees and animals while retaining shared lighting/material response.
- Avoid washed-out colors, overly dark shadow-side color, excessive saturation and muddy mottling.

## Scale and composition
- Landscape orientation and elevated/isometric viewing.
- The player, wildlife, trees, rocks, shrubs and interactable props must remain readable at gameplay scale.
- Forest density should create layered depth without hiding navigation and interaction silhouettes.
- Marsh areas are composed from readable 3D hummocks, sedges, reeds, moss pads and partially submerged vegetation.

## Model coverage
The same visual language applies to:
- conifers and deciduous trees, dead trees and fallen timber;
- shrubs, fern, grass, reeds, sedge, horsetail, moss, flowers, berries and mushrooms;
- rocks, stumps, marsh hummocks and landscape props;
- wildlife, carcasses and resource meshes;
- player, clothing, tools, equipment and settlement structures.

## Seasonal variants
Season changes must alter object models and palettes, not just ground tint: foliage density and color, bare branches, snow coverage and snow sitting on branches/objects. Seasonal variants should preserve silhouettes and materials.

## Weather-facing object behavior
3D objects may expose wetness/snow state and wind-responsive animation. Weather systems and terrain shaders are outside this model-only style guide scope.

## Animation quality
- Motion should preserve planted feet and avoid sliding, sudden snapping, disconnected joints or unnatural body twist.
- Gait and stride must scale with locomotion speed; idle, walk, trot/run, jump, swim and species-specific actions should use appropriate loops.
- Wind motion should be subtle and phase-offset across nearby plants.

## Collision quality
- Collision shapes should fit visible blocking volume, not overly large empty bounding boxes.
- Small decorative foliage should not block movement; trunks, rocks, stumps and solid structures should.
- Animal navigation/collision checks should include obstacle clearance and ground/water cases.

## Quality gate
Before claiming visual completion, capture real gameplay views at close, mid and far distance, and inspect seasonal/weather examples. Verify collisions and animation tests by fresh CI logs. Generated concept art is not a substitute for in-engine screenshots.

## Current implementation pass — 2026-11-27

### Model generator changes
- `pveg.gd`: shrub crowns are rebuilt around visible branch forks with intermediate side foliage and irregular crown lobes. Berry bushes use multiple connected branch forks and more distributed berry clusters.
- `veg.gd`: fern model uses a denser layered fan with secondary leaflet cards; reed clusters use five overlapping fans with varied lean and height.
- `model_geometry_test.gd`: structural gate for mesh surfaces, non-empty vertices, finite positions, and non-degenerate bounds for a sample set of trees, shrubs, marsh plants, mushrooms, rocks, berries, and representative animal rigs.

### Validation limits
- The structural test verifies generated mesh data only; it cannot judge art quality, shading, silhouette at mobile camera distance, or in-world spawn density.
- Animal collision, gait scaling, scheduler, and rock collision tests are run in CI after the mesh test.
- Player model and player animations remain deferred by the project's current scope decision.
- Real scene screenshots are required before final acceptance; automated screenshot capture is wired into the CI workflow.

### Acceptance checklist
- [ ] Every object family has the cohesive cartoon/painterly shape language.
- [ ] Close/mid/far screenshots reviewed in landscape.
- [ ] Meshes checked for disconnected, malformed, missing, or floating parts.
- [ ] Animal gait loops visually reviewed and motion-grounding checked.
- [ ] Solid object collision shapes reviewed in actual play.
- [ ] Seasonal model variants reviewed, not just color parameters.
- [ ] Weather overlays (snow/wetness) on 3D models visually reviewed.
- [ ] Mobile performance and density reviewed on a device or a representative profile.
