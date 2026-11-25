"""Reference animator (mirrored in scripts/animator.gd).
Procedural, physically-motivated locomotion:
 * gait from dynamic similarity (Alexander): stride length = 2.3*h*Fr^0.3, duty factor falls with speed
 * feet are planted in the world (no foot sliding); swing foot lands by Raibert's rule (hip + v*Ts/2)
 * pelvis height follows from the stance-leg geometry (inverted pendulum vaults, compressed 'spring' in running)
 * lean from acceleration (a/g), centripetal roll in turns, spring-damper filters give inertia/weight
"""
import numpy as np
from scipy.spatial.transform import Rotation as R
from solver import *

G = 9.81
def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)
def rot3(pitch, yaw, roll): return Ry(yaw) * Rx(pitch) * Rz(roll)

class Spring:
    """2nd-order critically-damped-ish filter for scalars/vectors"""
    def __init__(self, x0, omega=10.0, zeta=1.0):
        self.x = np.array(x0, float); self.v = np.zeros_like(self.x); self.w = omega; self.z = zeta
    def step(self, target, dt, omega=None, zeta=None):
        w = self.w if omega is None else omega; z = self.z if zeta is None else zeta
        n = max(1, int(np.ceil(dt * w / 0.35)))
        h = dt / n
        for _ in range(n):
            a = w * w * (np.asarray(target, float) - self.x) - 2 * z * w * self.v
            self.v = self.v + a * h; self.x = self.x + self.v * h
        return self.x

def yaw_rot(y): return Ry(np.degrees(y))
def wrap(a): return (a + np.pi) % (2 * np.pi) - np.pi

class Foot:
    def __init__(s, side, p):
        s.side = side; s.planted = True; s.pin = np.array(p, float); s.pos = np.array(p, float)
        s.start = np.array(p, float); s.land = np.array(p, float); s.t = 0.0; s.T = 0.3; s.pitch = 0.0; s.toe = 0.0; s.lift = 0.0

class Animator:
    def __init__(self, rig: Rig):
        self.rig = rig; self.sv = Solver(rig)
        r = rig
        self.hip_h = r.rp('Hips')[1]
        self.hipjoint_off = r.rp('Hips')[1] - r.rp('LeftUpLeg')[1]
        self.ankle_y = 0.5 * (r.rp('LeftFoot')[1] + r.rp('RightFoot')[1])
        self.half_w = 0.5 * (r.rp('LeftUpLeg')[0] - r.rp('RightUpLeg')[0])
        self.leg_max = 0.5 * (sum(self.sv.len['legL']) + sum(self.sv.len['legR']))
        self.h = self.hip_h - 0.0
        self.shoulder_y = r.rp('LeftArm')[1]
        self.arm_l = (0.5 * (self.sv.len['armL'][0] + self.sv.len['armR'][0]), 0.5 * (self.sv.len['armL'][1] + self.sv.len['armR'][1]))
        # state
        self.pos = np.zeros(3); self.yaw = 0.0; self.vel = np.zeros(3)
        self.yaw_rate = 0.0
        self.phase = 0.0; self.time = 0.0
        self.acc_f = 0.0; self.speed_f = 0.0
        self.pel = Spring([0, 0.0, 0], 14.0, 0.85)         # pelvis offset (x,y,z) relative to root (vertical = absolute height above ground)
        self.pel.x[1] = self.hip_h - 0.03
        self.lean = Spring([0, 0, 0], 9.0, 0.7)            # pitch, roll lean
        self.head_sp = Spring([0, 0], 8.0, 0.6)
        self.yawlag = Spring([0.0], 6.0, 0.7)
        self.arm_sp = {'L': Spring([0, 0, 0], 12, 0.7), 'R': Spring([0, 0, 0], 12, 0.7)}
        self.swing_amp = Spring([0.0], 6.0, 1.0)
        self.feet = {}
        self.feet['L'] = Foot('L', [self.half_w, self.ankle_y, 0.0]); self.feet['R'] = Foot('R', [-self.half_w, self.ankle_y, 0.0])
        self.cloth_hint = {}
        self.stance_t = 0.0
    # ---------------------------------------------------------------
    def gait_params(self, v):
        Fr = v * v / (G * self.h)
        lam = 2.3 * self.h * max(Fr, 1e-4) ** 0.3
        f = v / lam if v > 0.05 else 0.0
        beta = float(np.interp(v, [0, 0.5, 1.4, 2.2, 3.4, 4.5, 6.5, 9], [0.70, 0.68, 0.62, 0.52, 0.42, 0.37, 0.31, 0.27]))
        g = smooth(2.2, 3.4, v)      # run blend
        return lam, f, beta, g
    def update(self, dt, move_dir, speed_target, sprint=False):
        """move_dir: world xz unit vector or None. speed_target m/s"""
        self.time += dt
        # --- character controller: velocity with inertia (limited acceleration), turn rate limit
        want = np.zeros(3)
        if move_dir is not None and speed_target > 0.01:
            want = np.array([move_dir[0], 0, move_dir[1]]) * speed_target
        cur = self.vel.copy()
        dv = want - cur
        amax = 7.0 if np.linalg.norm(want) > np.linalg.norm(cur) else 9.0
        n = np.linalg.norm(dv)
        if n > amax * dt: dv = dv / n * amax * dt
        newv = cur + dv
        acc = (newv - cur) / dt
        self.vel = newv; self.pos = self.pos + newv * dt
        sp = np.linalg.norm(self.vel)
        # heading: face velocity direction when moving
        if sp > 0.3:
            tgt = np.arctan2(self.vel[0], self.vel[2])
            d = wrap(tgt - self.yaw)
            rate_max = 9.0 if sp < 3 else 6.5
            self.yaw_rate = float(np.clip(d * 8.0, -rate_max, rate_max))
        else:
            self.yaw_rate *= np.exp(-8 * dt)
        self.yaw += self.yaw_rate * dt
        fwd = np.array([np.sin(self.yaw), 0, np.cos(self.yaw)]); left = np.array([np.cos(self.yaw), 0, -np.sin(self.yaw)])
        a_long = float(acc @ fwd); a_lat = float(acc @ left)
        self.acc_f += (a_long - self.acc_f) * min(1.0, dt * 8); 
        self.speed_f = sp
        lam, f, beta, g = self.gait_params(sp)
        # --- phase clock: runs only while moving; at rest finish started swings
        if f > 0: self.phase = (self.phase + f * dt) % 1.0
        moving = sp > 0.12
        Yaw = yaw_rot(self.yaw)
        def to_world(local): return self.pos + Yaw.apply(local)
        def to_local(w): return Yaw.inv().apply(w - self.pos)
        Lmax = self.leg_max
        # --- feet
        for s, off in (('L', 0.0), ('R', 0.5)):
            ft = self.feet[s]; side = 1.0 if s == 'L' else -1.0
            ph = (self.phase + off) % 1.0
            want_stance = ph < beta if moving else True
            if moving:
                if ft.planted and not want_stance:
                    ft.planted = False; ft.start = ft.pos.copy(); ft.t = 0.0
                    ft.T = max((1 - beta) / max(f, 1e-3), 0.12)
                elif (not ft.planted) and want_stance and ft.t >= ft.T * 0.85:
                    ft.planted = True; ft.pin = ft.pos.copy()
            else:
                # stopped: let a started swing finish, then re-centre the feet one at a time (corrective step)
                if not ft.planted and ft.t >= ft.T * 0.999:
                    ft.planted = True; ft.pin = ft.pos.copy()
                elif ft.planted and self.feet['R' if s == 'L' else 'L'].planted:
                    des = self.pos + Yaw.apply([side * self.half_w, 0, 0]); des[1] = self.ankle_y
                    err = np.linalg.norm((ft.pin - des)[[0, 2]])
                    other = self.feet['R' if s == 'L' else 'L']
                    des_o = self.pos + Yaw.apply([-side * self.half_w, 0, 0]); err_o = np.linalg.norm((other.pin - des_o)[[0, 2]])
                    if err > 0.10 and err >= err_o:
                        ft.planted = False; ft.start = ft.pos.copy(); ft.t = 0.0; ft.T = 0.34
            if ft.planted:
                ft.pos = ft.pin.copy(); ft.pitch += (0 - ft.pitch) * min(1, dt * 10)
            else:
                ft.t += dt; u = min(ft.t / ft.T, 1.0)
                # landing target (Raibert): hip projection ahead by half the stance travel
                pred_pos = self.pos + self.vel * max(ft.T - ft.t, 0) 
                stance_travel = sp * beta / max(f, 1e-3) if f > 0 else 0.0
                ahead = 0.5 * stance_travel + 0.12 * (sp - np.linalg.norm(want)) * 0 
                dirv = self.vel / sp if sp > 0.05 else fwd
                lat = left * side * (self.half_w + 0.02 * smooth(0, 1.5, sp))
                # turning: steer landing towards the new heading
                land = pred_pos + dirv * ahead + lat
                if not moving:
                    land = self.pos + Yaw.apply([side * self.half_w, 0, 0])
                land[1] = self.ankle_y
                ft.land = land
                s5 = u ** 3 * (10 - 15 * u + 6 * u * u)
                p = ft.start + (ft.land - ft.start) * s5
                clr = 0.045 + 0.13 * g + 0.02 * smooth(0, 1.4, sp)
                # swing height: lift early (peak at ~40% of swing), foot trails at lift-off
                h_ = clr * np.sin(np.pi * min(u ** 0.75, 1.0)) ** 1.2
                p[1] = self.ankle_y + h_
                ft.pos = p
                # ankle pitch: toe-off plantarflexion -> dorsiflex before landing
                ft.pitch = 25.0 * (1 - u) ** 2 * np.sin(min(u * 3, np.pi / 2)) * 0 + (-30.0 * (1 - u) ** 3 + 12.0 * u ** 3)
        # idle: both planted, if pelvis far from foot centre (e.g. turned) re-step handled by gait when moving only
        # --- pelvis height from stance-leg geometry
        Lc = Lmax * (0.985 - 0.05 * g - 0.01 * smooth(0, 1, sp))
        hips_y = None
        anyp = False
        for s in 'LR':
            ft = self.feet[s]
            if ft.planted:
                anyp = True
                loc = to_local(ft.pos); hj_off = np.array([self.half_w * (1 if s == 'L' else -1), 0, 0])
                dxz = np.hypot(loc[0] - hj_off[0] * 0.0 - self.pel.x[0] - hj_off[0], loc[2] - self.pel.x[2])
                hy = ft.pos[1] + np.sqrt(max(Lc * Lc - dxz * dxz, 0.0)) + self.hipjoint_off
                hips_y = hy if hips_y is None else min(hips_y, hy)
        if hips_y is None: hips_y = self.pel.x[1] + 0.0
        # landing/launch dynamics: spring tracks target with some overshoot -> weight
        tgt_y = hips_y - 0.0
        if not anyp: tgt_y = self.hip_h - 0.03 + 0.06 * g
        pel = self.pel
        # lateral sway toward the stance foot
        stance_w = (1.0 if self.feet['L'].planted else 0.0) - (1.0 if self.feet['R'].planted else 0.0)
        sway = 0.02 * smooth(0.3, 1.5, sp) * stance_w * (1 - 0.5 * g)
        # forward offset: pelvis slightly behind planted foot centre under acceleration
        tgt = np.array([sway, tgt_y, 0.0])
        pel.step(tgt, dt, omega=16.0, zeta=0.8)
        # ---- upper body
        lean_p = np.degrees(np.arctan(self.acc_f / G)) * 0.9 + 1.1 * sp + 2.0 * g
        lean_p = float(np.clip(lean_p, -12, 28))
        lean_r = -np.degrees(np.arctan(sp * self.yaw_rate / G)) * 0.8
        lean_r = float(np.clip(lean_r, -18, 18))
        self.lean.step([lean_p, lean_r, 0], dt)
        zL = to_local(self.feet['L'].pos)[2]; zR = to_local(self.feet['R'].pos)[2]
        yL = self.feet['L'].pos[1] - self.ankle_y; yR = self.feet['R'].pos[1] - self.ankle_y
        stride_amp = zL - zR
        pel_yaw = -stride_amp * (7.0 + 3.0 * g) * smooth(0.1, 1.0, sp)
        pel_roll = -(yL - yR) * (28.0 + 20.0 * g) * smooth(0.1, 1.0, sp)
        pitch_total = self.lean.x[0]; roll_total = self.lean.x[1]
        # breathing + weight shift at idle
        t = self.time
        breath = np.sin(t * 2 * np.pi * 0.26)
        idle_k = 1 - smooth(0.1, 1.0, sp)
        pel_rot = rot3(0.25 * pitch_total + 1.0 * idle_k * np.sin(t * 0.7) * 0.3, pel_yaw, pel_roll + 0.25 * roll_total)
        sp_yaw = -0.6 * pel_yaw / 3.0 * 1.0
        spine = []
        for k in range(3):
            spine.append(rot3(0.25 * pitch_total + 0.5 * idle_k * breath * (k + 1) * 0.35, sp_yaw * 1.9, 0.25 * roll_total - 0.2 * pel_roll))
        head_pitch = -0.6 * pitch_total + 3.0
        hs = self.head_sp.step([head_pitch, 0.0], dt)
        neck = rot3(hs[0] * 0.5, -0.5 * (pel_yaw * 0.6 + sp_yaw * 5.7) * 0.5, -0.4 * roll_total)
        head = rot3(hs[0] * 0.5, 0.0, -0.4 * roll_total)
        # --- assemble pose
        P = Pose()
        hips_world = self.pos + Yaw.apply([pel.x[0], 0, pel.x[2]]); hips_world[1] = pel.x[1]
        # sway of idle
        P.hips_pos = hips_world
        P.hips_rot = Yaw * pel_rot
        P.spine = [s_ for s_ in spine]
        P.neck = neck; P.head = head
        for s in 'LR':
            ft = self.feet[s]
            P.foot[s] = ft.pos.copy()
            P.foot_rot[s] = Yaw * Rx(ft.pitch)
            P.toe[s] = 0.0
            side = 1.0 if s == 'L' else -1.0
            P.knee_pole[s] = Yaw.apply([0.10 * side, 0.0, 1.0])
        # arms: counter-swing, amplitude with speed; elbow flex grows with run
        sw_k = smooth(0.2, 1.3, sp)
        for s, other in (('L', 'R'), ('R', 'L')):
            zo = to_local(self.feet[other].pos)[2] - to_local(self.feet[s].pos)[2]   # arm forward when opposite foot forward
            theta = zo * (22.0 + 20.0 * g) * sw_k
            theta += 3.0 * idle_k
            eps = 8.0 + 14.0 * sw_k + 70.0 * g
            self.arm_sp[s].step([theta, eps, 0], dt)
        self.chest_pitch = pitch_total
        P._arm = {s: self.arm_sp[s].x.copy() for s in 'LR'}
        P._yaw = self.yaw
        self.solve_arms(P, Yaw, pel_rot, spine)
        return P
    def solve_arms(self, P, Yaw, pel_rot, spine):
        # first solve once to get shoulder positions (chest orientation), then place hands relative to shoulders
        P0 = P
        P0.hand = {'L': None, 'R': None}
        D, Pp = self.sv.solve(P0)
        i = self.rig.idx
        for s, side in (('L', 'Left'), ('R', 'Right')):
            S = Pp[i[side + 'Arm']]
            l1, l2 = self.arm_l
            th, ep, _ = P._arm[s]
            Dc = D[i['Spine']]
            yaw_c = Dc.as_euler('YXZ')[0]
            Yc = R.from_rotvec([0, yaw_c, 0])
            E = S + Yc.apply(Rx(-th).apply([0, -l1, 0]))
            H = E + Yc.apply(Rx(-(th + ep)).apply([0, -l2, 0]))
            # keep slightly outwards of the body line
            out = 0.035 * (1 if s == 'L' else -1)
            H = H + Yc.apply([out, 0, 0])
            P.hand[s] = H
            P.hand_pole[s] = Yc.apply([0.35 * (1 if s == 'L' else -1), -0.15, -1.0])
