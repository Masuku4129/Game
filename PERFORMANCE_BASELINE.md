# Taiga performance baseline (headless sandbox)

Date: 2026-11-27
Godot: 4.3 stable
Run: `PERF=1 godot --headless res://scenes/main.tscn`
Frame-count method: built-in `scripts/perf.gd` (240 warm-up, 300 measured frames per stage)
Renderer: headless dummy renderer. This is **script-time only**, not device FPS or GPU frame time; Android thermals are not represented.

## Observed script-time results

| Stage | Mean (ms) | Median (ms) | P95 (ms) |
|---|---:|---:|---:|
| All systems | 3.689 | 2.981 | 6.068 |
| Animals disabled | 0.862 | 0.799 | 1.213 |
| Repeat all | 3.099 | 2.948 | 4.317 |

Animal simulation is the dominant measured script-time contributor in this headless profile. The comparison is approximate: stage toggling and world state can introduce variance, and no Android device was profiled. This justifies prioritizing wildlife tick/steering/animation cost, but does not establish a phone FPS target or GPU bottleneck.

Other toggle stages are recorded in CI logs for future comparisons. Device profiling remains required for frame pacing, GPU, RAM and thermal behavior.
