"""Смещения вершин кисти для «кулака» (у модели нет костей пальцев): пальцы скручиваются к ладони вокруг костяшек.
Выход: assets/fist_vtx.bin = float32[n*4]: (dx,dy,dz [м, пространство покоя], сторона +1=левая/-1=правая/0)."""
import sys; sys.path.insert(0, '/home/claude/proj/tools')
import numpy as np
from render_pose import Renderer
from rig import Rig
A = '/home/claude/proj/assets/'
def fist_offsets(rd, rig, curl=2.9, u0=0.30):
    n = len(rd.pos); out = np.zeros((n, 4), np.float32)
    for side, jn, sgn in (('Left', 11, 1.0), ('Right', 15, -1.0)):
        hw = np.zeros(n)
        for s in range(4): hw += rd.W[:, s] * (rd.J[:, s] == jn)
        m = hw > 0.4
        wrist = rig.rp(side + 'Hand'); fore = rig.rp(side + 'ForeArm')
        f = wrist - fore; f /= np.linalg.norm(f)
        down = np.array([0, -1.0, 0]); down = down - f * np.dot(down, f); down /= np.linalg.norm(down)
        axis = np.cross(f, down); axis /= np.linalg.norm(axis)
        P = rd.pos[m]; al = (P - wrist) @ f
        x0, x1 = al.min(), al.max(); L = x1 - x0
        top = P @ (-down); pivot_h = top.max() - 0.012   # у «тыльной» стороны кисти
        new = P.copy()
        for k in range(len(P)):
            u = (al[k] - x0) / L
            if u <= u0: continue
            t = (u - u0) / (1 - u0)
            th = curl * (t ** 0.85)
            c = wrist + f * (x0 + u0 * L) + (-down) * (pivot_h - ((wrist) @ (-down)))
            c = wrist + f * (x0 + u0 * L)
            c = c + (-down) * (pivot_h - (c @ (-down)))
            r = P[k] - c
            # Родрига
            r2 = r * np.cos(th) + np.cross(axis, r) * np.sin(th) + axis * np.dot(axis, r) * (1 - np.cos(th))
            new[k] = c + r2
        # кулак компактнее по ширине
        ctr = P.mean(0); w_ax = axis
        wd = (new - ctr) @ w_ax
        new = new - np.outer(wd * 0.18, w_ax)
        off = (new - P) * hw[m, None]
        idx = np.where(m)[0]
        out[idx, :3] = off; out[idx, 3] = sgn
        print(side, 'verts', m.sum(), 'max off cm', round(np.linalg.norm(off, axis=1).max() * 100, 1))
    return out
if __name__ == '__main__':
    rig = Rig(A + 'mita_rig.glb'); rd = Renderer(A + 'mita_rig.glb')
    o = fist_offsets(rd, rig); o.tofile(A + 'fist_vtx.bin'); print(o.shape)
