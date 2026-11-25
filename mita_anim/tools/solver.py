"""Pose solver (reference implementation; mirrored 1:1 in scripts/rig_solver.gd).
Character space: +Y up, +Z forward, +X = character's LEFT.  Units: metres.
Every bone gets a global delta rotation D (applied on top of its rest orientation) and a global position P.
"""
import numpy as np
from scipy.spatial.transform import Rotation as R
from rig import Rig

def Rx(a): return R.from_rotvec([np.radians(a), 0, 0])   # +a : lean forward
def Ry(a): return R.from_rotvec([0, np.radians(a), 0])   # +a : turn to the left (+X)
def Rz(a): return R.from_rotvec([0, 0, np.radians(a)])   # +a : tilt to the right (-X)
I3 = R.identity()

def from_to(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    d = float(a @ b)
    if d > 0.999999: return I3
    if d < -0.999999:
        ax = np.cross(a, [1, 0, 0]);
        if np.linalg.norm(ax) < 1e-3: ax = np.cross(a, [0, 1, 0])
        return R.from_rotvec(ax / np.linalg.norm(ax) * np.pi)
    ax = np.cross(a, b); s = np.linalg.norm(ax)
    return R.from_rotvec(ax / s * np.arctan2(s, d))

def two_bone(S, T, l1, l2, pole):
    """returns elbow/knee position for root S, target T, lengths, pole direction (bend towards pole)"""
    d = T - S; dist = np.linalg.norm(d)
    dist = np.clip(dist, abs(l1 - l2) + 1e-4, (l1 + l2) * 0.9995)
    dirn = d / np.linalg.norm(d)
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = np.sqrt(max(l1 * l1 - a * a, 0.0))
    pp = pole - dirn * (pole @ dirn)
    if np.linalg.norm(pp) < 1e-5: pp = np.cross(dirn, [1, 0, 0])
    pp /= np.linalg.norm(pp)
    return S + dirn * a + pp * h, S + dirn * dist

class Pose:
    def __init__(self):
        self.hips_pos = None             # global hips position
        self.hips_rot = I3               # world delta
        self.spine = [I3, I3, I3]        # Spine02, Spine01, Spine : world delta relative to parent
        self.neck = I3; self.head = I3
        self.shrug = [I3, I3]            # L,R clavicle extra delta
        self.hand = {'L': None, 'R': None}      # target hand joint positions
        self.hand_pole = {'L': np.array([0.3, -0.2, -1.0]), 'R': np.array([-0.3, -0.2, -1.0])}
        self.hand_rot = {'L': I3, 'R': I3}      # extra world rotation of hand
        self.foot = {'L': None, 'R': None}      # target ankle joint positions
        self.foot_rot = {'L': I3, 'R': I3}      # world delta (yaw/pitch) of foot
        self.toe = {'L': 0.0, 'R': 0.0}         # toe pitch deg
        self.knee_pole = {'L': np.array([0.12, 0, 1.0]), 'R': np.array([-0.12, 0, 1.0])}

class Solver:
    def __init__(self, rig: Rig):
        self.rig = rig; r = rig
        self.n = len(r.names)
        self.i = r.idx
        self.rd = {}                       # rest direction (global) bone -> child
        # lengths
        def L(a, b): return float(np.linalg.norm(r.rp(a) - r.rp(b)))
        self.len = {}
        for s in 'LR':
            side = 'Left' if s == 'L' else 'Right'
            self.len['leg' + s] = (L(side + 'UpLeg', side + 'Leg'), L(side + 'Leg', side + 'Foot'))
            self.len['arm' + s] = (L(side + 'Arm', side + 'ForeArm'), L(side + 'ForeArm', side + 'Hand'))
    def solve(self, p: Pose):
        r = self.rig; i = self.i
        D = [I3] * self.n; P = [None] * self.n
        def off(child, parent): return r.rest_pos[i[child]] - r.rest_pos[i[parent]]
        def place(name, parent, d):
            """FK: D[name] = d * D[parent]; position follows parent's rotation"""
            b = i[name]; pa = i[parent]
            D[b] = d * D[pa]
            P[b] = P[pa] + D[pa].apply(off(name, parent))
        def aim(name, parent, child, target_dir):
            b = i[name]; pa = i[parent]
            rest_dir = r.rest_pos[i[child]] - r.rest_pos[b]
            cur = D[pa].apply(rest_dir)
            D[b] = from_to(cur, target_dir) * D[pa]
            P[b] = P[pa] + D[pa].apply(off(name, parent))
        hips = i['Hips']; D[hips] = p.hips_rot; P[hips] = np.array(p.hips_pos, float)
        place('Spine02', 'Hips', p.spine[0]); place('Spine01', 'Spine02', p.spine[1]); place('Spine', 'Spine01', p.spine[2])
        place('neck', 'Spine', p.neck); place('Head', 'neck', p.head)
        place('head_end', 'Head', I3); place('headfront', 'Head', I3)
        for s, side in (('L', 'Left'), ('R', 'Right')):
            ci = 0 if s == 'L' else 1
            place(side + 'Shoulder', 'Spine', p.shrug[ci])
            # --- arm IK
            arm = side + 'Arm'; fa = side + 'ForeArm'; hand = side + 'Hand'
            place(arm, side + 'Shoulder', I3)               # position only, rotation fixed below
            S = P[i[arm]]; l1, l2 = self.len['arm' + s]
            T = p.hand[s]
            if T is None: T = S + np.array([0.0, -(l1 + l2) * 0.97, 0.0])
            E, Tc = two_bone(S, T, l1, l2, p.hand_pole[s])
            aim(arm, side + 'Shoulder', fa, E - S)
            aim(fa, arm, hand, Tc - E)
            D[i[hand]] = p.hand_rot[s] * D[i[fa]]; P[i[hand]] = Tc
            # --- leg IK
            up = side + 'UpLeg'; leg = side + 'Leg'; foot = side + 'Foot'; toe = side + 'ToeBase'
            place(up, 'Hips', I3)
            S = P[i[up]]; l1, l2 = self.len['leg' + s]
            T = p.foot[s]
            E, Tc = two_bone(S, T, l1, l2, p.knee_pole[s])
            aim(up, 'Hips', leg, E - S)
            aim(leg, up, foot, Tc - E)
            D[i[foot]] = p.foot_rot[s]; P[i[foot]] = Tc
            place(toe, foot, Rx(-p.toe[s]) * I3)
            D[i[toe]] = Rx(-p.toe[s]) * p.foot_rot[s]
        return D, P

    def skin_matrices(self, D, P):
        r = self.rig
        return [(D[k], P[k] - D[k].apply(r.rest_pos[k])) for k in range(self.n)]
