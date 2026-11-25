import sys, json; sys.path.insert(0, '/home/claude/proj/tools')
from retarget_clips import *
A = '/home/claude/proj/assets/'
CLIPS = {  # имя в игре: (клип mocap, петля, скорость стопы)
    'idle': ('idle-loop', True, 0.0), 'walk': ('walk-loop', True, 1.65), 'run': ('run-loop', True, 4.54),
    'jump': ('jump', False, 0.0), 'roll': ('dodge', False, 0.0),
    'punch': ('mo_punch_kick', False, 0.0), 'spinkick': ('mo_spin_kick', False, 0.0),
}
src = Src(SRC); rig = Rig(A + 'mita_rig.glb')
out = {'fps': FPS, 'floats_per_frame': 59, 'clips': {}}
for name, (clip, loop, v) in CLIPS.items():
    fr, info = retarget(src, rig, clip, loop)
    flat = [pose_to_flat(p) for p in fr]
    hy = [f[1] for f in flat]
    out['clips'][name] = {'loop': loop, 'dur': round(info['dur'], 4), 'n': info['n'], 'speed': v, 'frames': flat}
    fy = min(min(f[3 + 4 + 12 + 8 + 6 + 1 - 0] for f in flat[:1]) , 0)
    footy = [min(f[27 + 1], f[27 + 1 + 13]) for f in flat]
    print(f'{name:9s} n={info["n"]:3d} dur={info["dur"]:.2f} hips_y {min(hy):.2f}..{max(hy):.2f} foot_y min {min(footy):.2f} max {max(footy):.2f}')
json.dump(out, open(A + 'clips.json', 'w'), separators=(',', ':'))
import os; print(os.path.getsize(A + 'clips.json') // 1024, 'KB')
