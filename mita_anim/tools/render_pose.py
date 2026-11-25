import numpy as np, io
from PIL import Image
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
from rig import Rig
from glbload import load

class Renderer:
    def __init__(self, glb):
        j, acc, image = load(glb)
        pr = j['meshes'][0]['primitives'][0]; at = pr['attributes']
        self.pos = acc(at['POSITION']).astype(float)
        self.J = acc(at['JOINTS_0']).astype(int); W = acc(at['WEIGHTS_0']).astype(float)
        ct = j['accessors'][at['WEIGHTS_0']]['componentType']
        if ct == 5121: W /= 255
        elif ct == 5123: W /= 65535
        self.W = W
        self.idx = acc(pr['indices']).reshape(-1, 3).astype(int)
        uv = acc(at['TEXCOORD_0'])
        tex = np.array(Image.open(io.BytesIO(image(0))).convert('RGB').resize((512, 512)))
        c = uv[self.idx].mean(1)
        self.col = tex[(c[:, 1] * 511).astype(int).clip(0, 511), (c[:, 0] * 511).astype(int).clip(0, 511)] / 255.
        self.nj = 24
    def skin(self, M):
        """M: list of (Rotation, translation) per joint in joint order of skin"""
        Rm = np.stack([m[0].as_matrix() for m in M]); T = np.stack([m[1] for m in M])
        out = np.zeros_like(self.pos)
        for s in range(4):
            jj = self.J[:, s]; w = self.W[:, s:s + 1]
            out += w * (np.einsum('vij,vj->vi', Rm[jj], self.pos) + T[jj])
        return out
    def draw(self, ax, verts, view='side', disp=None, title=''):
        tri = self.idx; Pt = verts[tri]
        i, k, d = {'front': (0, 1, 2), 'side': (2, 1, 0), 'back': (0, 1, 2), 'top': (0, 2, 1)}[view]
        sx = -1.0 if view == 'back' else 1.0
        depth = Pt[:, :, d].mean(1) * (-1 if view in ('back',) else 1)
        if view == 'side': depth = -depth
        order = np.argsort(depth)
        X = Pt[:, :, i] * sx; Y = Pt[:, :, k]
        polys = np.stack([X, Y], -1)[order]
        n = np.cross(Pt[:, 1] - Pt[:, 0], Pt[:, 2] - Pt[:, 0]); n /= (np.linalg.norm(n, axis=1, keepdims=True) + 1e-9)
        sh = (0.45 + 0.55 * np.abs(n[:, d]))[order, None]
        ax.add_collection(PolyCollection(polys, facecolors=np.clip(self.col[order] * sh * 2.2, 0, 1), edgecolors='none'))
        ax.set_aspect('equal'); ax.set_facecolor('#7a7a8a'); ax.set_title(title, fontsize=8)
