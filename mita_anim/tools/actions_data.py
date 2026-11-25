"""Keyed actions (yaw frame, root-relative, metres/degrees). Exported to assets/actions.json for the game.
Fields per key: t, pel[dx,dy,dz], prot[pitch,yaw,roll], spine[...], head[pitch,yaw], hr, hl (hand targets), fl, fr (foot targets),
turn (root yaw offset in degrees since action start), v (root speed m/s), ease, pl/pr (plant foot on arrival)."""
import json
def K(t, pel, prot, spine, head, hr, hl, fl, fr, turn=0.0, v=0.0, ease='io', pl=False, pr=False):
    return dict(t=t, pel=pel, prot=prot, spine=spine, head=head, hr=hr, hl=hl, fl=fl, fr=fr, turn=turn, v=v, ease=ease, pl=pl, pr=pr)
GUARD = dict(pel=[0, -0.05, 0.04], prot=[1, -6, 0], spine=[4, -8, 0], head=[0, 0], hr=[-0.20, 1.40, 0.30], hl=[0.22, 1.45, 0.34], fl=[0.14, 0, 0.26], fr=[-0.14, 0, -0.20], turn=0.0)
def REC(t, turn): return K(t, GUARD['pel'], GUARD['prot'], GUARD['spine'], [0, 0], GUARD['hr'], GUARD['hl'], GUARD['fl'], GUARD['fr'], turn, 0.0, 'io')
ACTIONS = {
 'punch': dict(type='keys', keys=[
   K(0.13, [0.0,-0.08,-0.04], [1,-22,0], [5,-30,0], [0,6], [-0.12,1.38,0.12], [0.24,1.50,0.40], [0.14,0,0.30], [-0.14,0,-0.24], 0, 0.0, 'io'),
   K(0.08, [0.02,-0.12,0.16], [3,22,1], [8,34,0], [0,-8], [-0.04,1.52,0.92], [0.12,1.40,0.20], [0.14,0,0.34], [-0.14,0,-0.22], 0, 1.6, 'in', pl=True),
   K(0.11, [0.02,-0.12,0.18], [3,24,1], [8,36,0], [0,-10], [-0.04,1.52,0.94], [0.12,1.40,0.20], [0.14,0,0.34], [-0.14,0,-0.22], 0, 0.4, 'out'),
   REC(0.26, 0)]),
 'spinkick': dict(type='keys', keys=[
   K(0.16, [0.0,-0.10,-0.02], [2,-14,0], [6,-22,0], [0,10], [-0.20,1.38,0.20], [0.22,1.40,0.28], [0.14,0,0.20], [-0.14,0,-0.22], 40, 0.0, 'io', pl=True),
   K(0.16, [0.0,-0.14,0.02], [4,-8,0], [10,-12,0], [0,14], [-0.30,1.30,-0.05], [0.30,1.32,0.05], [0.14,0,0.20], [-0.18,0.55,-0.10], 215, 0.6, 'in', pl=True),
   K(0.11, [0.0,-0.08,0.06], [-6,-6,-4], [-16,-6,-6], [-4,0], [-0.45,1.50,-0.05], [0.45,1.55,0.05], [0.14,0,0.20], [-0.20,1.00,0.80], 355, 1.2, 'in', pl=True),
   K(0.10, [0.0,-0.08,0.08], [-6,-6,-4], [-16,-6,-6], [-4,0], [-0.50,1.52,-0.02], [0.50,1.55,0.08], [0.14,0,0.20], [-0.20,1.00,0.82], 365, 0.6, 'out', pl=True),
   K(0.22, [0.0,-0.08,0.04], [2,-6,0], [5,-8,0], [0,0], [-0.20,1.40,0.30], [0.22,1.45,0.34], [0.14,0,0.20], [-0.14,0,-0.20], 360, 0.0, 'io'),
   REC(0.26, 360)]),
 'roll': dict(type='roll', dur=0.82, speed=3.8),
 'jump': dict(type='air', prep=0.17, vy=5.2, vz=0.0, tuck=0.75, land=0.34),
}
if __name__ == '__main__':
    json.dump(dict(actions=ACTIONS, guard=GUARD), open('/home/claude/proj/assets/actions.json', 'w'), indent=1)
