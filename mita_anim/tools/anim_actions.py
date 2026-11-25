"""Actions layer on top of the locomotion animator (reference; mirrored in scripts/animator.gd).
Action types: 'keys' (spring-filtered key poses, e.g. punch, spin kick), 'air' (ballistic jump with landing absorption), 'roll'."""
import json, numpy as np
from scipy.spatial.transform import Rotation as R
from solver import *
from animator import Animator, Spring, rot3, smooth, yaw_rot, G

NAMES = ('pel', 'prot', 'spine', 'head', 'hr', 'hl', 'fl', 'fr', 'turn')
def ease(kind, u):
    if kind == 'in': return u * u
    if kind == 'out': return 1 - (1 - u) * (1 - u)
    return u * u * (3 - 2 * u)

def blend_pose(a, b, w):
    if w <= 0: return a
    if w >= 1: return b
    P = Pose()
    lerp = lambda x, y: (1 - w) * np.asarray(x, float) + w * np.asarray(y, float)
    def slerp(r1, r2): return r1 * R.from_rotvec(w * (r1.inv() * r2).as_rotvec())
    P.hips_pos = lerp(a.hips_pos, b.hips_pos); P.hips_rot = slerp(a.hips_rot, b.hips_rot)
    P.spine = [slerp(x, y) for x, y in zip(a.spine, b.spine)]
    P.neck = slerp(a.neck, b.neck); P.head = slerp(a.head, b.head)
    for s in 'LR':
        P.hand[s] = lerp(a.hand[s], b.hand[s]); P.hand_pole[s] = lerp(a.hand_pole[s], b.hand_pole[s])
        P.foot[s] = lerp(a.foot[s], b.foot[s]); P.foot_rot[s] = slerp(a.foot_rot[s], b.foot_rot[s])
        P.knee_pole[s] = lerp(a.knee_pole[s], b.knee_pole[s])
    return P

class ActionAnimator(Animator):
    def __init__(self, rig, actions_json):
        super().__init__(rig)
        j = json.load(open(actions_json)); self.actions = j['actions']; self.guard = {k: np.array(v, float) for k, v in j['guard'].items()}
        self.act = None; self.aw = 0.0
        self.root_y = 0.0; self.vy = 0.0
        self.sp = None
    def busy(self): return self.act is not None and self.act['phase'] != 'done'
    def start(self, name):
        if self.busy(): return False
        a = self.actions[name]
        act = dict(name=name, t=0.0, k=0, kt=0.0, phase='run', impact=0.0, hz=np.zeros(3), yaw0=self.yaw)
        act['feet'] = {s: dict(planted=(a['type'] != 'keys'), pin=self.feet[s].pos.copy(), pos=self.feet[s].pos.copy()) for s in 'LR'}
        if a['type'] == 'keys':
            act['prev'] = {n: np.array(self.guard[n], float) for n in NAMES}
            act['prev']['turn'] = np.array([0.0])
            self.sp = {n: Spring(act['prev'][n].copy(), 38.0 if n in ('hr', 'hl') else 20.0, 0.62 if n in ('hr', 'hl') else 0.8) for n in NAMES}
            self.sp['vz'] = Spring([0.0], 18.0, 0.9)
            act['vz'] = 0.0
        elif a['type'] == 'air':
            act['phase'] = 'prep'
            self.sp = {'pel': Spring([0, 0, 0], 16.0, 0.75), 'tuck': Spring([0.0], 18.0, 0.9), 'arms': Spring([0.0], 14.0, 0.7)}
        else:
            self.sp = {'v': Spring([0.0], 20.0, 0.9)}
            act['v0'] = self.vel.copy()
        self.act = act
        return True
    # ----------------------------------------------------------
    def update(self, dt, move_dir, speed_target, sprint=False):
        act = self.act
        if act is None:
            return super().update(dt, move_dir, speed_target, sprint)
        a = self.actions[act['name']]
        act['t'] += dt; self.time += dt
        if a['type'] == 'keys': Pa = self.step_keys(dt, a, act)
        elif a['type'] == 'air': Pa = self.step_air(dt, a, act)
        else: Pa = self.step_roll(dt, a, act)
        if act['phase'] == 'done': self.aw = max(0.0, self.aw - dt / 0.22)
        else: self.aw = min(1.0, self.aw + dt / 0.09)
        if self.aw <= 0.0:
            self.act = None
            return super().update(dt, move_dir, speed_target, sprint)
        if act['phase'] == 'done':
            Pl = super().update(dt, move_dir, speed_target, sprint)
            return blend_pose(Pl, Pa, self.aw)
        return Pa
    # ---------------------------------------------------------- keyed actions
    def step_keys(self, dt, a, act):
        keys = a['keys']; k = act['k']
        if k >= len(keys):
            act['phase'] = 'done'; return self.pose_keys(dt, act, None, 0.0)
        key = keys[k]
        act['kt'] += dt
        u = min(act['kt'] / key['t'], 1.0); e = ease(key['ease'], u)
        prm = {}
        for n in NAMES:
            tgt = np.array(key[n], float) if n != 'turn' else np.array([key['turn']], float)
            prm[n] = (1 - e) * act['prev'][n] + e * tgt
        vz = key['v'] if u > 0.05 else act['vz']
        act['vz'] = vz
        if u >= 1.0:
            for s, flag in (('L', key['pl']), ('R', key['pr'])):
                f = act['feet'][s]
                if flag and not f['planted']: f['planted'] = True; f['pin'] = f['pos'].copy()
                if (not flag) and f['planted']: f['planted'] = False
            act['prev'] = {n: (np.array(key[n], float) if n != 'turn' else np.array([key['turn']], float)) for n in NAMES}
            act['k'] += 1; act['kt'] = 0.0
            if act['k'] >= len(keys): act['phase'] = 'done'
        return self.pose_keys(dt, act, prm, vz)
    def pose_keys(self, dt, act, prm, vz):
        sp = self.sp
        if prm is None: prm = {n: act['prev'][n] for n in NAMES}
        for n in NAMES: sp[n].step(prm[n], dt)
        self.yaw = act['yaw0'] + np.radians(sp['turn'].x[0])
        Yaw = yaw_rot(self.yaw)
        sp['vz'].step([vz], dt)
        self.vel = Yaw.apply([0, 0, float(sp['vz'].x[0])]); self.pos = self.pos + self.vel * dt
        root = self.pos
        P = Pose()
        pel = sp['pel'].x
        hp = root + Yaw.apply([pel[0], 0, pel[2]]); hp[1] = self.hip_h + pel[1]
        P.hips_pos = hp
        pr = sp['prot'].x; P.hips_rot = Yaw * rot3(pr[0], pr[1], pr[2])
        spn = sp['spine'].x; w3 = (0.25, 0.35, 0.40)
        P.spine = [rot3(spn[0] * w, spn[1] * w, spn[2] * w) for w in w3]
        hd = sp['head'].x
        P.neck = rot3(hd[0] * 0.4, hd[1] * 0.4, 0); P.head = rot3(hd[0] * 0.6, hd[1] * 0.6, 0)
        P.hand['R'] = root + Yaw.apply(sp['hr'].x); P.hand['L'] = root + Yaw.apply(sp['hl'].x)
        P.hand_pole['R'] = Yaw.apply([-0.55, -0.45, -0.45]); P.hand_pole['L'] = Yaw.apply([0.55, -0.45, -0.45])
        for s, key in (('L', 'fl'), ('R', 'fr')):
            f = act['feet'][s]; v = sp[key].x
            if f['planted']:
                f['pos'] = f['pin'].copy()
            else:
                tgt = root + Yaw.apply([v[0], 0, v[2]]); tgt[1] = self.ankle_y + v[1]
                delta = tgt - f['pos']
                f['pos'] = f['pos'] + delta * min(1.0, dt * 14.0)
                f['pos'][1] += 0.07 * min(1.0, np.linalg.norm(delta[[0, 2]]) * 4.0) * min(1.0, dt * 14.0)
                f['pos'][1] = max(self.ankle_y, f['pos'][1])
            P.foot[s] = f['pos'].copy()
            loc = Yaw.inv().apply(f['pos'] - root)
            pitch = -float(np.clip((-loc[2] - 0.15) * 70.0, 0, 28)) if loc[2] < 0 else 0.0
            P.foot_rot[s] = Yaw * Rx(0.0 if (f['planted'] or f['pos'][1] > self.ankle_y + 0.2) else pitch)
            P.knee_pole[s] = Yaw.apply([0.10 * (1 if s == 'L' else -1), 0, 1.0])
        self.sync_loco(act, hp)
        return P
    def sync_loco(self, act, hp):
        for s in 'LR':
            self.feet[s].pos = act['feet'][s]['pos'].copy(); self.feet[s].pin = self.feet[s].pos.copy(); self.feet[s].planted = True
        self.pel.x = np.array([0.0, hp[1], 0.0]); self.pel.v[:] = 0
        self.lean.x[:] = 0; self.lean.v[:] = 0
    # ---------------------------------------------------------- roll
    def step_roll(self, dt, a, act):
        u = min(act['t'] / a['dur'], 1.0)
        Yaw = yaw_rot(self.yaw)
        tuck = smooth(0.10, 0.28, u) * (1 - smooth(0.74, 0.92, u))
        th = 360.0 * smooth(0.16, 0.80, u)
        vt = a['speed'] * smooth(0.0, 0.18, u) * (1 - 0.35 * smooth(0.75, 1.0, u))
        v = self.sp['v'].step([vt], dt)[0]
        self.vel = Yaw.apply([0, 0, v]); self.pos = self.pos + self.vel * dt
        root = self.pos
        stand = self.hip_h - 0.07
        bump = 0.05 * np.sin(np.pi * np.clip((u - 0.2) / 0.55, 0, 1))
        hy = stand * (1 - tuck) + (0.50 + bump) * tuck
        hp = root + Yaw.apply([0, 0, 0.10 * tuck]); hp[1] = hy
        P = Pose(); P.hips_pos = hp
        Hr = Yaw * Rx(th)
        P.hips_rot = Hr
        P.spine = [Rx(14 * tuck)] * 3
        P.neck = Rx(14 * tuck); P.head = Rx(10 * tuck)
        for s, side in (('L', 1.0), ('R', -1.0)):
            stand_foot = root + Yaw.apply([side * self.half_w, 0, 0.10 * side + 0.0]); stand_foot[1] = self.ankle_y
            tuck_foot = hp + Hr.apply([side * 0.13, -0.22, 0.32])
            P.foot[s] = (1 - tuck) * stand_foot + tuck * tuck_foot
            stand_hand = hp + Yaw.apply([side * 0.30, 0.05 + 0.15 * smooth(0, 0.16, u), 0.10 + 0.30 * smooth(0, 0.16, u) * (1 - tuck)])
            tuck_hand = hp + Hr.apply([side * 0.24, 0.40, 0.34])
            P.hand[s] = (1 - tuck) * stand_hand + tuck * tuck_hand
            P.foot_rot[s] = Hr
            P.knee_pole[s] = Hr.apply([0.10 * side, 0.2, 1.0])
            P.hand_pole[s] = Hr.apply([side * 0.7, -0.2, -0.5])
        if u >= 1.0:
            for s, side in (('L', 1.0), ('R', -1.0)):
                f = act['feet'][s]; f['pos'] = P.foot[s].copy()
            act['phase'] = 'done'
            self.vel = Yaw.apply([0, 0, a['speed'] * 0.65])
        self.sync_loco(act, hp)
        return P
    # ---------------------------------------------------------- air (jump)
    def step_air(self, dt, a, act):
        sp = self.sp; Yaw = yaw_rot(self.yaw)
        ph = act['phase']
        pel_dy = 0.0; spine_p = 0.0; tuck = 0.0; arms = 0.0
        if ph == 'prep':
            u = min(act['t'] / a['prep'], 1.0); e = u * u * (3 - 2 * u)
            pel_dy = -0.30 * e; spine_p = 16 * e; arms = -e
            if u >= 1.0:
                ph = act['phase'] = 'air'
                act['hz'] = self.vel.copy() + Yaw.apply([0, 0, a['vz']])
                self.vy = a['vy']; self.root_y = 0.0; act['t_air'] = 0.0
                for s in 'LR': act['feet'][s]['planted'] = False
        if ph == 'air':
            act['t_air'] += dt
            self.vy -= G * dt; self.root_y += self.vy * dt
            self.pos = self.pos + act['hz'] * dt; self.vel = act['hz'].copy()
            t_land = (self.vy + np.sqrt(max(self.vy ** 2 + 2 * G * max(self.root_y, 0), 0))) / G if self.vy < 3 else 9.0
            up = smooth(0.0, 0.18, act['t_air']); ext = 1 - smooth(0.06, 0.22, t_land)
            tuck = up * ext * a['tuck']
            spine_p = -4 + 8 * tuck; arms = 0.6 * up * ext + 0.3
            if self.root_y <= 0.0 and self.vy < 0.0 and act['t_air'] > 0.05:
                act['impact'] = -self.vy; self.root_y = 0.0; ph = act['phase'] = 'land'; act['t'] = 0.0
                for s, off in (('L', [0.14, 0, 0.10]), ('R', [-0.14, 0, -0.10])):
                    f = act['feet'][s]; f['planted'] = True
                    pin = self.pos + Yaw.apply(off); pin[1] = self.ankle_y; f['pin'] = pin
                self.vel = act['hz'] * 0.6
        if ph == 'land':
            u = min(act['t'] / a['land'], 1.0)
            imp = np.clip(act['impact'] / 6.0, 0.25, 1.0)
            comp = 0.30 * imp * (np.sin(np.pi * min(u / 0.35, 1.0) * 0.5) if u < 0.35 else 1 - smooth(0.35, 1.0, u))
            pel_dy = -comp; spine_p = 14 * comp / 0.30 * imp; arms = -0.2
            self.vel = self.vel * np.exp(-6 * dt); self.pos = self.pos + self.vel * dt
            if u >= 1.0: act['phase'] = 'done'
        s_pel = sp['pel'].step([0.0, pel_dy, 0.0], dt)
        s_tuck = sp['tuck'].step([tuck], dt)[0]; s_arms = sp['arms'].step([arms], dt)[0]
        root = self.pos
        hp = root.copy(); hp[1] = self.hip_h + s_pel[1] + self.root_y
        P = Pose(); P.hips_pos = hp
        P.hips_rot = Yaw * rot3(spine_p * 0.2, 0, 0)
        P.spine = [rot3(spine_p * 0.27, 0, 0)] * 3
        P.neck = rot3(-spine_p * 0.2, 0, 0); P.head = rot3(-spine_p * 0.2, 0, 0)
        for s in 'LR':
            f = act['feet'][s]; side = 1.0 if s == 'L' else -1.0
            if f['planted'] and ph in ('prep', 'land'):
                f['pin'][1] = self.ankle_y; pos = f['pin'].copy()
            else:
                tk = s_tuck; lead = 1.0 if s == 'L' else 0.6
                off = [side * (self.half_w - 0.02), 0, 0.30 * tk * lead + 0.12 * (1 - tk) * (1.0 if s == 'L' else -0.6)]
                pos = root + Yaw.apply(off); pos[1] = max(self.ankle_y, self.root_y + self.ankle_y + 0.52 * tk * (1.0 if s == 'L' else 0.8))
            f['pos'] = pos; P.foot[s] = pos
            P.foot_rot[s] = Yaw * Rx(-18 * s_tuck if ph == 'air' else 0)
            P.knee_pole[s] = Yaw.apply([0.10 * side, 0.0, 1.0])
        for s, side in (('L', 1.0), ('R', -1.0)):
            e = s_arms
            P.hand[s] = hp + Yaw.apply([side * (0.30 + 0.30 * max(e, 0)), 0.42 + 0.22 * max(e, 0) - 0.10 * max(-e, 0), 0.05 + 0.10 * max(e, 0) - 0.34 * max(-e, 0)])
            P.hand_pole[s] = Yaw.apply([side * 0.4, -0.3, -0.6])
        self.sync_loco(act, hp)
        for s in 'LR': self.feet[s].planted = (ph != 'air')
        return P
