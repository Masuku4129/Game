"""Перенос реальных mocap-клипов (kira_rigged.glb, CMU) на скелет Миты.
Торс (hips/spine/neck/head): мировая дельта от позы покоя (не зависит от осей костей).
Руки/ноги: IK-цели (позиции кисти/стопы + полюса колен/локтей) в масштабе пропорций Миты."""
import sys, json; sys.path.insert(0, '/home/claude/proj/tools')
import numpy as np
from scipy.spatial.transform import Rotation as R, Slerp
import glbload
from rig import Rig
from solver import Pose, Solver, from_to, I3

SRC = '/home/claude/game/kira_3d_test/assets/kira_rigged.glb'
FPS = 30

class Src:
    def __init__(self, path):
        j, acc, _ = glbload.load(path); self.j = j; self.acc = acc
        N = j['nodes']; self.N = N
        self.par = {}
        for i, n in enumerate(N):
            for c in n.get('children', []): self.par[c] = i
        self.name = {n['name'].replace('mixamorig_', ''): i for i, n in enumerate(N)}
        self.order = self._topo()
        self.anims = {}
        for a in j['animations']:
            ch = {}
            for c in a['channels']:
                s = a['samplers'][c['sampler']]
                t = acc(s['input']).ravel(); v = acc(s['output'])
                ch[(c['target']['node'], c['target']['path'])] = (t, v)
            self.anims[a['name']] = ch
    def _topo(self):
        out = []; seen = set()
        def go(i):
            if i in seen: return
            if i in self.par: go(self.par[i])
            seen.add(i); out.append(i)
        for i in range(len(self.N)): go(i)
        return out
    def fk(self, rot, trans):
        """rot/trans: dict node->Rotation / vec (local). returns global (pos, Rotation) lists"""
        G = {}
        for i in self.order:
            n = self.N[i]
            q = rot.get(i, R.from_quat(n.get('rotation', [0, 0, 0, 1])))
            t = trans.get(i, np.array(n.get('translation', [0, 0, 0]), float))
            if i in self.par:
                pp, pq = G[self.par[i]]; G[i] = (pp + pq.apply(t), pq * q)
            else: G[i] = (t, q)
        return G
    def sample(self, clip, k, nfr, loop):
        ch = self.anims[clip]; rot = {}; tr = {}
        dur = max(float(t[-1]) for t, _ in ch.values())
        tt = k / FPS
        for (node, path), (t, v) in ch.items():
            if path == 'rotation':
                if len(t) == 1: rot[node] = R.from_quat(v[0])
                else:
                    sl = Slerp(t, R.from_quat(v)); rot[node] = sl(np.clip(tt, t[0], t[-1]))
            elif path == 'translation':
                tr[node] = np.array([np.interp(tt, t, v[:, d]) for d in range(3)])
        return self.fk(rot, tr)
    def duration(self, clip):
        return max(float(t[-1]) for t, _ in self.anims[clip].values())

SPINE_MAP = [('Spine', 'Spine02'), ('Spine1', 'Spine01'), ('Spine2', 'Spine')]

def retarget(src: Src, rig: Rig, clip, loop):
    dur = src.duration(clip); nfr = max(2, int(round(dur * FPS)) + (0 if loop else 1))
    rest = src.fk({}, {})
    nm = src.name
    # --- масштабы
    def sp(G, n): return G[nm[n]][0]
    # у покоя Hips может быть без translation: берём hips из первого кадра клипа как «рост»
    G0 = src.sample('idle-loop', 0, 2, True)
    ay_src = min(sp(G0, 'LeftFoot')[1], sp(G0, 'RightFoot')[1])
    ay_tgt = min(rig.rp('LeftFoot')[1], rig.rp('RightFoot')[1])
    def L(a, b): return float(np.linalg.norm(sp(G0, a) - sp(G0, b)))
    srcleg = L('LeftUpLeg', 'LeftLeg') + L('LeftLeg', 'LeftFoot')
    tgtleg = float(np.linalg.norm(rig.rp('LeftUpLeg') - rig.rp('LeftLeg')) + np.linalg.norm(rig.rp('LeftLeg') - rig.rp('LeftFoot')))
    srcarm = L('LeftArm', 'LeftForeArm') + L('LeftForeArm', 'LeftHand')
    tgtarm = float(np.linalg.norm(rig.rp('LeftArm') - rig.rp('LeftForeArm')) + np.linalg.norm(rig.rp('LeftForeArm') - rig.rp('LeftHand')))
    kl = tgtleg / srcleg; ka = tgtarm / srcarm
    frames = []; Gs = []
    for k in range(nfr): Gs.append(src.sample(clip, k, nfr, loop))
    # --- дрейф корня для петель (беговая дорожка)
    h = np.array([sp(G, 'Hips') for G in Gs])
    drift = np.zeros(3)
    if loop:
        drift = (h[-1] - h[0]) / (nfr - 1) * nfr  # смещение за период
        drift[1] = 0
    vclip = np.linalg.norm(drift[[0, 2]]) / dur if loop else 0.0
    rest_dir_toe = {s: sp(rest, s + 'ToeBase') - sp(rest, s + 'Foot') for s in ('Left', 'Right')}
    # покоя-ротации для дельт
    rrot = {n: rest[nm[n]][1] for n in nm}
    for k, G in enumerate(Gs):
        off = -drift * (k / nfr) if loop else np.zeros(3)
        off = off - np.array([h[0][0], 0, h[0][2]]) if True else off
        def pos(n): return sp(G, n) + off
        def D(n): return G[nm[n]][1] * rrot[n].inv()
        p = Pose()
        hy = ay_tgt + (pos('Hips')[1] - ay_src) * kl
        p.hips_pos = np.array([pos('Hips')[0], hy, pos('Hips')[2]])
        p.hips_rot = D('Hips')
        prev = D('Hips')
        for i, (s, t) in enumerate(SPINE_MAP):
            d = D(s); p.spine[i] = d * prev.inv(); prev = d
        dn = D('Neck'); p.neck = dn * prev.inv(); p.head = D('Head') * dn.inv()
        # --- цели конечностей: позиция относительно плеча/бедра, масштабированная
        # положения плеч/бёдер на скелете Миты считаем тем же FK, что и решатель
        sol = Solver(rig); Dm, Pm = _torso(sol, p)
        for si, (s, side) in enumerate((('L', 'Left'), ('R', 'Right'))):
            sh = pos(side + 'Arm'); wr = pos(side + 'Hand'); el = pos(side + 'ForeArm')
            p.hand[s] = Pm[rig.idx[side + 'Arm']] + (wr - sh) * ka
            pole = el - 0.5 * (sh + wr); p.hand_pole[s] = pole / (np.linalg.norm(pole) + 1e-9)
            up = pos(side + 'UpLeg'); an = pos(side + 'Foot'); kn = pos(side + 'Leg')
            p.foot[s] = Pm[rig.idx[side + 'UpLeg']] + (an - up) * kl
            pole = kn - 0.5 * (up + an); p.knee_pole[s] = pole / (np.linalg.norm(pole) + 1e-9)
            tdir = pos(side + 'ToeBase') - an
            r0 = rest_dir_toe[side]
            p.foot_rot[s] = from_to(r0, tdir)
        frames.append(p)
    return frames, dict(dur=dur, loop=loop, vclip=float(vclip), kl=kl, ka=ka, n=nfr)

def _torso(sol, p):
    r = sol.rig; i = sol.i
    D = {}; P = {}
    def off(c, pa): return r.rest_pos[i[c]] - r.rest_pos[i[pa]]
    def place(n, pa, d):
        D[n] = d * D[pa]; P[n] = P[pa] + D[pa].apply(off(n, pa))
    D['Hips'] = p.hips_rot; P['Hips'] = np.array(p.hips_pos, float)
    place('Spine02', 'Hips', p.spine[0]); place('Spine01', 'Spine02', p.spine[1]); place('Spine', 'Spine01', p.spine[2])
    for side in ('Left', 'Right'):
        place(side + 'Shoulder', 'Spine', I3); place(side + 'Arm', side + 'Shoulder', I3)
        place(side + 'UpLeg', 'Hips', I3)
    return {i[k]: v for k, v in D.items()}, {i[k]: v for k, v in P.items()}

def pose_to_flat(p):
    f = [*p.hips_pos, *p.hips_rot.as_quat(), *np.concatenate([q.as_quat() for q in p.spine]), *p.neck.as_quat(), *p.head.as_quat()]
    for s in 'LR': f += [*p.hand[s], *p.hand_pole[s]]
    for s in 'LR': f += [*p.foot[s], *p.foot_rot[s].as_quat(), *p.knee_pole[s]]
    return [round(float(x), 4) for x in f]
