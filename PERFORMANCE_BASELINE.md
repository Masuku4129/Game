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

## Follow-up after near-fauna scheduler throttle

After limiting near-range animal AI ticks to 30 Hz (while animation players remain continuously active), the headless run recorded:

| Stage | Mean (ms) | Median (ms) | P95 (ms) |
|---|---:|---:|---:|
| All systems | 3.737 | 3.037 | 6.302 |
| Animals disabled | 0.806 | 0.746 | 1.127 |
| Repeat all | 3.344 | 3.027 | 4.971 |

This single run did **not** show a clear script-time improvement versus the earlier baseline (variation/no-render headless conditions). The throttle still reduces the maximum update rate for near animals at 60 FPS, but the improvement must be confirmed on-device; procedural pose quality also needs visual review.
