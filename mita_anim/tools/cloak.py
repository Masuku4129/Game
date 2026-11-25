"""Reference cloak simulation (PBD particles + pin springs + capsule collision + aerodynamic drag). Mirrored in scripts/cloak_sim.gd"""
import json, numpy as np
from scipy.spatial.transform import Rotation as R
G = 9.81
class Cloak:
    def __init__(self, rig, json_path, vtx_bin=None):
        d = json.load(open(json_path)); self.d = d; self.rig = rig
        self.n = n = d['n']
        self.rest = np.array(d['pos']); self.nrm = np.array(d['nrm'])
        self.bidx = np.array([[rig.idx[b] for b in row] for row in d['bones']]); self.bw = np.array(d['weights'])
        self.edges = np.array([[e[0], e[1]] for e in d['edges']], int); self.elen = np.array([e[2] for e in d['edges']])
        wp = np.array(d['wsim']); self.wp = wp
        self.omega = 26.0 * (1 - wp) ** 2 + 5.0 * wp            # pin spring (rad/s)
        self.zeta = 0.35 - 0.12 * wp
        self.maxd = np.array(d['maxd'])
        self.invm = 0.03 + wp
        self.caps = [(rig.idx[c['a']], rig.idx[c['b']], c['r']) for c in d['caps']]
        self.clear = np.array(d['clear'])
        self.p = None
        self.wind = np.zeros(3)
        self.k_q = 0.30; self.k_t = 0.25
        self.time = 0.0
        # per-vertex binding
        if vtx_bin:
            raw = np.fromfile(vtx_bin, dtype=np.float32); V = d['vertex_count']
            self.vi = raw[:V * 4].reshape(V, 4).astype(int); self.vw = raw[V * 4:].reshape(V, 4)
    def targets(self, D, P):
        rig = self.rig
        T = np.zeros((self.n, 3)); N = np.zeros((self.n, 3))
        for k in range(4):
            b = self.bidx[:, k]; w = self.bw[:, k:k + 1]
            rp = np.array([rig.rest_pos[x] for x in b])
            Dm = np.stack([D[x].as_matrix() for x in b]); Pp = np.array([P[x] for x in b])
            T += w * (np.einsum('nij,nj->ni', Dm, self.rest - rp) + Pp)
            N += w * np.einsum('nij,nj->ni', Dm, self.nrm)
        N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-9
        return T, N
    def step(self, dt, D, P, substeps=2, iters=2):
        T, N = self.targets(D, P)
        if self.p is None:
            self.p = T.copy(); self.v = np.zeros_like(T); self.Tprev = T.copy()
        vT = (T - self.Tprev) / dt; self.Tprev = T.copy()
        elen = np.linalg.norm(T[self.edges[:, 1]] - T[self.edges[:, 0]], axis=1)   # lengths follow the animated (skinned) shape
        h = dt / substeps
        g_rel = np.array([0, -G, 0]) - D[self.rig.idx['Hips']].apply([0, -G, 0])
        self.time += dt
        gust = 0.35 * np.array([np.sin(self.time * 1.7), 0, np.sin(self.time * 1.3 + 1.0)])
        wind = self.wind + gust
        segs = [(P[a], P[b], r) for a, b, r in self.caps]
        for _ in range(substeps):
            p0 = self.p.copy()
            vrel = self.v - wind
            vn = np.einsum('ij,ij->i', vrel, N)[:, None]
            a = g_rel[None, :] * (0.4 + 0.6 * self.wp[:, None])
            a = a - self.k_q * np.abs(vn) * vn * N - self.k_t * (vrel - vn * N) * 0.5
            a = a + (self.omega ** 2)[:, None] * (T - self.p) + (2 * self.zeta * self.omega)[:, None] * (vT - self.v)
            self.v = self.v + a * h
            self.p = self.p + self.v * h
            # constraints
            for _it in range(iters):
                p = self.p
                for e in range(len(self.edges)):          # Gauss-Seidel (same order as the GDScript port)
                    i = self.edges[e, 0]; j = self.edges[e, 1]
                    dv = p[j] - p[i]; L = np.sqrt(dv @ dv) + 1e-9
                    wi = self.invm[i]; wj = self.invm[j]
                    c = (L - elen[e]) / L / (wi + wj) * 0.8
                    p[i] += dv * (c * wi); p[j] -= dv * (c * wj)
                # max distance to pinned target
                off = self.p - T; ol = np.linalg.norm(off, axis=1)
                m = ol > self.maxd
                self.p[m] = T[m] + off[m] / ol[m, None] * self.maxd[m, None]
                # capsules
                for ci, (A, B, r) in enumerate(segs):
                    cl = self.clear[:, ci]
                    ab = B - A; t = np.clip(((self.p - A) @ ab) / (ab @ ab), 0, 1)
                    c = A + t[:, None] * ab; dd = self.p - c; dl = np.linalg.norm(dd, axis=1) + 1e-9
                    hit = (cl > 0) & (dl < cl)
                    self.p[hit] = c[hit] + dd[hit] / dl[hit, None] * cl[hit, None]
                self.p[:, 1] = np.maximum(self.p[:, 1], 0.02)
            self.v = (self.p - p0) / h * 0.998
        return self.p - T
    def vertex_disp(self, disp):
        return np.einsum('vk,vkc->vc', self.vw, disp[self.vi])
