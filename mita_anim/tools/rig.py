"""Reference rig: reads the GLB skeleton, rest pose in metres (character space: +Y up, +Z forward, +X = character's left)."""
import numpy as np
from scipy.spatial.transform import Rotation as R
from glbload import load

class Rig:
    def __init__(self, glb):
        j, acc, image = load(glb)
        self.j, self.acc, self.image = j, acc, image
        nodes = j['nodes']
        self.nodes = nodes
        skin = j['skins'][0]
        self.joint_nodes = skin['joints']
        self.names = [nodes[n]['name'] for n in self.joint_nodes]
        self.idx = {n: i for i, n in enumerate(self.names)}
        parent_node = {}
        for pi, n in enumerate(nodes):
            for c in n.get('children', []):
                parent_node[c] = pi
        node2j = {n: i for i, n in enumerate(self.joint_nodes)}
        self.parent = []
        for n in self.joint_nodes:
            p = parent_node.get(n)
            self.parent.append(node2j.get(p, -1))
        nj = len(self.names)
        self.rest_loc_rot = [R.from_quat(nodes[n].get('rotation', [0, 0, 0, 1])) for n in self.joint_nodes]
        self.rest_loc_pos = [np.array(nodes[n].get('translation', [0, 0, 0]), float) * 0.01 for n in self.joint_nodes]
        # topological order (parents first)
        order = []
        seen = set()
        def visit(i):
            if i in seen: return
            if self.parent[i] >= 0: visit(self.parent[i])
            seen.add(i); order.append(i)
        for i in range(nj): visit(i)
        self.order = order
        self.rest_rot = [None] * nj   # global rest rotations
        self.rest_pos = [None] * nj   # global rest positions (m)
        for i in order:
            p = self.parent[i]
            if p < 0:
                self.rest_rot[i] = self.rest_loc_rot[i]; self.rest_pos[i] = self.rest_loc_pos[i]
            else:
                self.rest_rot[i] = self.rest_rot[p] * self.rest_loc_rot[i]
                self.rest_pos[i] = self.rest_pos[p] + self.rest_rot[p].apply(self.rest_loc_pos[i])
        self.children = [[] for _ in range(nj)]
        for i, p in enumerate(self.parent):
            if p >= 0: self.children[p].append(i)
    def rp(self, name): return self.rest_pos[self.idx[name]]

if __name__ == '__main__':
    import sys
    r = Rig(sys.argv[1])
    for i in r.order:
        print(f'{r.names[i]:14s} par={r.names[r.parent[i]] if r.parent[i]>=0 else "-":12s} pos={np.round(r.rest_pos[i],3)}')
    for a, b in [('LeftUpLeg','LeftLeg'),('LeftLeg','LeftFoot'),('LeftArm','LeftForeArm'),('LeftForeArm','LeftHand'),('RightUpLeg','RightLeg'),('RightLeg','RightFoot'),('RightArm','RightForeArm'),('RightForeArm','RightHand')]:
        print(a, b, np.linalg.norm(r.rp(a)-r.rp(b)).round(3))
