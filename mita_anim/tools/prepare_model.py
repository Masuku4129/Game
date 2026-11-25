"""Offline preparation of the character for the cloth system.
 - classifies cloak vertices geometrically (outside of body proxy capsules, hanging below the shoulders)
 - re-binds cloak vertices from leg bones to Hips (the cloak must not swing with the thighs, cloth drapes on its own)
 - picks simulation particles (farthest point sampling), builds the constraint network and per-vertex binding
 - writes assets/mita_rig.glb, assets/cloak.json, assets/cloak_vtx.bin
usage: prepare_model.py in.glb out_dir
"""
import sys, json, struct, io, numpy as np
from rig import Rig
from body import CAPS, seg_dist
from glbload import load
from scipy.spatial import cKDTree

def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

N_PART = 176
src, out = sys.argv[1], sys.argv[2]
rig = Rig(src)
j, acc, image = load(src)
pr = j['meshes'][0]['primitives'][0]; at = pr['attributes']
pos = acc(at['POSITION']).astype(float); nrm = acc(at['NORMAL']).astype(float)
J = acc(at['JOINTS_0']).astype(int); W = acc(at['WEIGHTS_0']).astype(float)
wacc = j['accessors'][at['WEIGHTS_0']]
if wacc['componentType'] == 5121: W /= 255.0
elif wacc['componentType'] == 5123: W /= 65535.0
V = len(pos)
for k in ('POSITION', 'JOINTS_0', 'WEIGHTS_0'):
    bv = j['bufferViews'][j['accessors'][at[k]]['bufferView']]
    assert not bv.get('byteStride'), 'interleaved buffers not supported'

# --- body proxy ---
caps = []
for name, a, b, r in CAPS:
    caps.append((name, rig.rp(a), rig.rp(b), r, a, b))
dout = np.full(V, 9.0)
for name, A, B, r, a, b in caps:
    dout = np.minimum(dout, seg_dist(pos, A, B) - r)
y = pos[:, 1]
import io as _io
from PIL import Image as _Im
_tex = np.array(_Im.open(_io.BytesIO(image(0))).convert('RGB')).astype(float) / 255
_uv = acc(at['TEXCOORD_0'])
_h, _w = _tex.shape[:2]
lum = _tex[(_uv[:, 1] * (_h - 1)).astype(int).clip(0, _h - 1), (_uv[:, 0] * (_w - 1)).astype(int).clip(0, _w - 1)] @ np.array([.299, .587, .114])
c = smooth(0.012, 0.05, dout) * smooth(0.30, 0.46, y)       # "cloakness": outside the body proxy
dark_gate = np.maximum(smooth(0.10, 0.16, lum), smooth(0.05, 0.09, dout))   # dark parts (pants, boots) must be clearly detached
c = c * dark_gate
hf = smooth(1.52, 1.00, y)                                    # freedom grows towards the hem
w_sim = c * hf
print('cloak verts c>0.5:', int((c > 0.5).sum()), ' sim weight>0.2:', int((w_sim > 0.2).sum()))

# --- rebind legs -> hips for cloak vertices ---
leg_names = ['LeftUpLeg', 'LeftLeg', 'LeftFoot', 'LeftToeBase', 'RightUpLeg', 'RightLeg', 'RightFoot', 'RightToeBase']
leg_ids = [rig.idx[n] for n in leg_names]; hips = rig.idx['Hips']
W2 = np.zeros((V, 24)); 
for s in range(4): np.add.at(W2, (np.arange(V), J[:, s]), W[:, s])
leg_sum = W2[:, leg_ids].sum(1)
move = np.clip(smooth(0.05, 0.4, c), 0, 1)
for li in leg_ids: W2[:, li] *= (1 - move)
W2[:, hips] += leg_sum * move
top = np.argsort(-W2, axis=1)[:, :4]
J2 = top.copy(); Wn = np.take_along_axis(W2, top, 1); Wn /= Wn.sum(1, keepdims=True)
print('rebound weight mass:', float((leg_sum * move).sum()), ' of ', float(leg_sum.sum()))

# --- write GLB with new skinning ---
b = bytearray(open(src, 'rb').read())
cl, _ = struct.unpack('<II', b[12:20]); off = 20 + cl + 8
def put(accessor_idx, arr):
    a = j['accessors'][accessor_idx]; bv = j['bufferViews'][a['bufferView']]
    o = off + bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    dt = {5126: '<f4', 5123: '<u2', 5125: '<u4', 5121: 'u1'}[a['componentType']]
    data = arr.astype(dt).tobytes(); b[o:o + len(data)] = data
put(at['JOINTS_0'], J2)
if wacc['componentType'] == 5126: put(at['WEIGHTS_0'], Wn)
elif wacc['componentType'] == 5121: put(at['WEIGHTS_0'], np.round(Wn * 255))
else: put(at['WEIGHTS_0'], np.round(Wn * 65535))
open(out + '/mita_rig.glb', 'wb').write(bytes(b))

# --- particles ---
cand = np.where((c > 0.3) & (y > 0.33) & (y < 1.60))[0]
# dedupe coincident verts
key = np.round(pos[cand] / 0.004).astype(np.int64)
_, ui = np.unique(key, axis=0, return_index=True); cand = cand[np.sort(ui)]
cp = pos[cand]
# FPS biased: start from lowest vertex
chosen = [int(np.argmin(cp[:, 1]))]
dist = np.linalg.norm(cp - cp[chosen[0]], axis=1)
for _ in range(N_PART - 1):
    k = int(np.argmax(dist)); chosen.append(k)
    dist = np.minimum(dist, np.linalg.norm(cp - cp[k], axis=1))
pid = cand[np.array(chosen)]
P = pos[pid]; PN = nrm[pid]; N = len(P)
tree = cKDTree(P)
nn = tree.query(P, k=2)[0][:, 1]; spacing = float(np.median(nn)); print('particles', N, 'spacing', round(spacing, 3))
edges = []
for i in range(N):
    idxs = tree.query_ball_point(P[i], 2.4 * spacing)
    idxs = [k for k in idxs if k != i]
    idxs.sort(key=lambda k: np.linalg.norm(P[k] - P[i]))
    cnt = 0
    for k in idxs:
        d = float(np.linalg.norm(P[k] - P[i]))
        if PN[i] @ PN[k] < -0.25 and d > 0.7 * spacing: continue
        a_, b_ = (i, k) if i < k else (k, i)
        edges.append((a_, b_)); cnt += 1
        if cnt >= 7: break
edges = sorted(set(edges))
elen = [float(np.linalg.norm(P[a_] - P[b_])) for a_, b_ in edges]
print('edges', len(edges), 'avg degree', round(2 * len(edges) / N, 2))
wp = w_sim[pid]
kpin = 70.0 * (1 - wp) ** 2 + 3.0 * wp                    # 1/s : pull towards the animated (pinned) position
maxd = 0.035 + 0.50 * wp ** 0.8                            # m  : max distance from the pinned position
mass = 1.0 + 0.0 * wp
# per-particle skinning (modified weights)
pb = [[rig.names[int(J2[v, s])] for s in range(4)] for v in pid]
pw = [[float(Wn[v, s]) for s in range(4)] for v in pid]
# collision clearance per particle per capsule
clear = np.zeros((N, len(caps)))
for ci, (name, A, B, r, a, bb) in enumerate(caps):
    rd = seg_dist(P, A, B)
    cl_ = np.minimum(r + 0.012, rd - 0.004); cl_[rd > r + 0.5] = 0.0
    clear[:, ci] = np.maximum(cl_, 0.0)
# --- per-vertex binding to 4 nearest particles ---
d_, ii = tree.query(pos, k=4)
wb = 1.0 / (d_ + 0.5 * spacing) ** 2
wb /= wb.sum(1, keepdims=True)
wb *= w_sim[:, None]
vtx = np.concatenate([ii.astype(np.float32).ravel(), wb.astype(np.float32).ravel()])
open(out + '/cloak_vtx.bin', 'wb').write(vtx.tobytes())
data = dict(
    n=N, spacing=spacing, vertex_count=V,
    pos=np.round(P, 5).tolist(), nrm=np.round(PN, 4).tolist(),
    bones=pb, weights=np.round(pw, 5).tolist(),
    kpin=np.round(kpin, 3).tolist(), maxd=np.round(maxd, 4).tolist(), wsim=np.round(wp, 3).tolist(),
    edges=[[int(a_), int(b_), round(l, 5)] for (a_, b_), l in zip(edges, elen)],
    caps=[dict(name=n, a=a, b=bb, r=r) for n, A, B, r, a, bb in caps],
    clear=np.round(clear, 4).tolist())
json.dump(data, open(out + '/cloak.json', 'w'), separators=(',', ':'))
np.savez('/home/claude/work/prep.npz', pos=pos, w_sim=w_sim, c=c, pid=pid, J2=J2, Wn=Wn, ii=ii, wb=wb)
print('done')
