#!/usr/bin/env python3
"""Generate painterly low-poly Taiga environment GLBs (Y-up, Godot 4).

Style = the in-game "живописный" look: crowns are soft rounded clouds or jagged tier
skirts with soft (radial) normals, trunks are tapered tubes with seam-correct UVs.
No photo textures: colour, brush strokes, warm light / cool shadows, snow, autumn and
fade come from the game's own paint shaders, which pveg.model_variants() assigns by
mesh name: bark / foliage / cut / rock.
"""
from pathlib import Path
import math
import numpy as np
import trimesh
from trimesh.visual import TextureVisuals

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "models" / "environment"
OUT.mkdir(parents=True, exist_ok=True)
UP = np.array([0., 0., 1.])


class Builder:
    def __init__(self):
        self.d = {}

    def add(self, key, v, f, uv, n):
        e = self.d.setdefault(key, {"v": [], "f": [], "uv": [], "n": [], "off": 0})
        v = np.asarray(v, float)
        e["v"].append(v); e["f"].append(np.asarray(f, int) + e["off"])
        e["uv"].append(np.asarray(uv, float).reshape(len(v), 2)); e["n"].append(np.asarray(n, float).reshape(len(v), 3))
        e["off"] += len(v)


def unit(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v, axis=-1, keepdims=True) if v.ndim > 1 else np.linalg.norm(v)
    return v / np.maximum(n, 1e-9)


def perp(d):
    d = unit(d)
    ref = np.array([1., 0., 0.]) if abs(d[2]) > .9 else UP
    return unit(np.cross(d, ref))


def export(name, b):
    scene = trimesh.Scene()
    rot = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float)  # Z-up -> glTF Y-up
    tris = 0
    for key, e in b.d.items():
        v = np.vstack(e["v"]) @ rot.T
        n = unit(np.vstack(e["n"]) @ rot.T)
        f = np.vstack(e["f"])
        mesh = trimesh.Trimesh(vertices=v, faces=f, vertex_normals=n, process=False)
        mesh.visual = TextureVisuals(uv=np.vstack(e["uv"]))
        scene.add_geometry(mesh, geom_name=key, node_name=key)
        tris += len(f)
    data = scene.export(file_type="glb")
    (OUT / name).write_bytes(data)
    print(f"{name:24s} meshes={'/'.join(b.d)} tris={tris:5d} {len(data)/1024:6.1f} KB")


# ---------------------------------------------------------------- primitives ---
def tube(b, a, c, r0, r1, sections=6, sides=6, bend=(0, 0, 0), flare=0.0, key="bark", rng=None, wobble=0.0):
    a, c = np.asarray(a, float), np.asarray(c, float)
    axis = c - a; length = np.linalg.norm(axis)
    if length < 1e-6:
        return
    d = axis / length; u_ax = perp(d); v_ax = np.cross(d, u_ax)
    verts, uvs, nrm, faces = [], [], [], []
    ph = rng.uniform(0, 6.28) if rng is not None else 0.0
    for i in range(sections + 1):
        t = i / sections
        ctr = a * (1 - t) + c * t + np.asarray(bend) * math.sin(math.pi * t)
        rad = (r0 * (1 - t) + r1 * t) * (1 + flare * math.exp(-t * length * 2.2))
        for j in range(sides + 1):
            ang = 2 * math.pi * j / sides
            w = 1 + wobble * math.sin(j * 3.0 + t * 7 + ph)
            dv = u_ax * math.cos(ang) + v_ax * math.sin(ang)
            verts.append(ctr + dv * rad * w); nrm.append(dv)
            uvs.append((j / sides * max(1.0, round(2 * math.pi * r0 * 1.3)), t * length * .5))
    for i in range(sections):
        for j in range(sides):
            p = i * (sides + 1) + j
            faces += [[p, p + sides + 1, p + 1], [p + 1, p + sides + 1, p + sides + 2]]
    b.add(key, verts, faces, uvs, nrm)


def blob(b, center, radii, rng, cc, sub=2, jit=.16, soft=.58, key="foliage"):
    """Cartoon foliage mass: scalloped, slightly flattened cloud with soft painted normals."""
    m = trimesh.creation.icosphere(subdivisions=sub, radius=1.0)
    base = np.asarray(m.vertices)
    # Deliberate broad lobes break the repeated ball silhouette without noisy micro-detail.
    az = np.arctan2(base[:, 1], base[:, 0])
    lat = base[:, 2]
    scallop = (0.075 * np.sin(az * 5.0 + lat * 2.2)
               + 0.045 * np.sin(az * 9.0 - lat * 3.1)
               + 0.035 * np.cos(lat * 7.0 + az * 2.0))
    variation = 1.0 + scallop + jit * rng.uniform(-1, 1, (len(base),))
    v = base * np.asarray(radii) * variation[:, None]
    # Lift the upper silhouette and tuck the underside into the branch structure.
    v[:, 2] *= np.where(base[:, 2] > 0.0, 1.08, 0.88)
    v = v + np.asarray(center)
    radial = unit(v - np.asarray(center))
    n = unit(radial * (1 - soft) + unit(v - np.asarray(cc)) * soft)
    b.add(key, v, m.faces, np.zeros((len(v), 2)), n)


def skirt(b, z, r, h, teeth, rng, key="foliage"):
    """Jagged drooping tier of a spruce/larch: cone with scalloped edge, soft outward normals."""
    n = teeth * 2
    verts = [np.array([0, 0, z + h * .5]), np.array([0, 0, z - h * .45])]
    for i in range(n):
        a = 2 * math.pi * i / n
        outer = i % 2 == 0
        rr = r * (rng.uniform(.9, 1.1) if outer else .62)
        zz = z - h * (.5 if outer else .12) + rng.uniform(-.05, .05) * h
        verts.append(np.array([math.cos(a) * rr, math.sin(a) * rr, zz]))
    verts = np.array(verts)
    faces = []
    for i in range(n):
        j = 2 + i; k = 2 + (i + 1) % n
        faces += [[0, j, k], [1, k, j]]
    nrm = np.zeros_like(verts)
    nrm[0] = UP
    nrm[1] = -UP
    for i in range(2, len(verts)):
        nrm[i] = unit(np.array([verts[i][0], verts[i][1], r * .55]))
    b.add(key, verts, faces, np.zeros((len(verts), 2)), nrm)


def disc(b, center, radius, axis, key="cut", n=14):
    axis = unit(axis); u = perp(axis); v = np.cross(axis, u)
    verts = [np.asarray(center, float)]; uvs = [(.5, .5)]; nrm = [axis]; faces = []
    for j in range(n):
        a = 2 * math.pi * j / n
        verts.append(np.asarray(center, float) + (u * math.cos(a) + v * math.sin(a)) * radius)
        uvs.append((.5 + .5 * math.cos(a), .5 + .5 * math.sin(a))); nrm.append(axis)
        faces.append([0, 1 + j, 1 + (j + 1) % n])
    b.add(key, verts, faces, uvs, nrm)


# --------------------------------------------------------------------- trees ---
def tiered(name, seed, H, r0, r1, tiers, z0, z1, R0, teeth, hscale, top_r):
    rng = np.random.default_rng(seed)
    b = Builder()
    tube(b, (0, 0, 0), (.04, 0, H * .9), r0, r1, 8, 7, (.1, 0, 0), flare=.8, rng=rng, wobble=.03)
    for i in range(tiers):
        t = i / max(tiers - 1, 1)
        z = z0 + (z1 - z0) * t
        r = R0 * (1 - t * .85) * rng.uniform(.9, 1.1)
        skirt(b, z, r, r * hscale + .4, teeth, rng)
    skirt(b, H * .9, top_r, H * .12, 4, rng)
    export(name, b)


def spruce():
    H = 7.8
    tiered("taiga_spruce.glb", 1, H, .34, .04, 9, H * .14, H * .86, H * .23, 11, .7, .35)


def larch():
    H = 10.0
    tiered("taiga_larch.glb", 3, H, .27, .04, 13, 2.0, H * .88, H * .15, 9, .55, .3)


def clouds(name, seed, H, r0, bark_bend, crown_c, layers, top_blob=True, branches=4):
    """Conifers with rounded crowns (pine, cedar): bare/limbed trunk + layered flat clouds."""
    rng = np.random.default_rng(seed)
    b = Builder()
    cc = np.array(crown_c, float)
    tube(b, (0, 0, 0), (.04, 0, H * .95), r0, .06, 9, 7, bark_bend, flare=.9, rng=rng, wobble=.03)
    for (z, ring, rad, n) in layers:
        for k in range(n):
            a = 2 * math.pi * k / n + rng.uniform(-.3, .3) + z
            rr = ring * rng.uniform(.7, 1.15)
            c = np.array([math.cos(a) * rr, math.sin(a) * rr, z + rng.uniform(-.3, .3)])
            blob(b, c, (rad * rng.uniform(.85, 1.15), rad * rng.uniform(.85, 1.15), rad * .42), rng, cc + np.array([0, 0, -1.5]), 1, .22, .6)
            if branches:
                tube(b, (0.03, 0, max(z - 1.2, 1.5)), c * .6 + np.array([0, 0, z * .4]), .06, .02, 2, 4)
    if top_blob:
        blob(b, (0.04, 0, H * .97), (rad * .8, rad * .8, rad * .5), rng, cc, 1, .2, .6)
    export(name, b)


def pine():
    clouds("taiga_pine.glb", 2, 11.0, .30, (.12, 0, 0), (0, 0, 9.0),
           [(7.2, 1.2, 1.4, 3), (8.4, 1.5, 1.7, 4), (9.6, 1.0, 1.4, 3)])


def cedar():
    clouds("taiga_cedar.glb", 4, 9.0, .44, (.1, 0, 0), (0, 0, 5.8),
           [(3.6, 1.8, 1.8, 5), (5.0, 1.6, 1.9, 5), (6.5, 1.1, 1.6, 4), (7.7, .5, 1.2, 2)])


def broadleaf(name, seed, H, r0, ccz, crx, crz, nblobs, brad, lean=(0, 0), second=None):
    rng = np.random.default_rng(seed)
    b = Builder()
    tube(b, (0, 0, 0), (lean[0], lean[1], H), r0, .05, 10, 7, (.12, .04, 0), flare=.8, rng=rng, wobble=.03)
    if second:
        tube(b, (.08, .05, 0), second, r0 * .7, .04, 8, 6, (-.1, 0, 0), flare=.5, rng=rng)
    cc = np.array([lean[0] * .6, lean[1] * .6, ccz])
    for i in range(nblobs):
        while True:
            o = rng.uniform(-1, 1, 3)
            if .2 < np.dot(o, o) <= 1:
                break
        c = cc + o * np.array([crx, crx, crz])
        z0 = max(ccz - crz * .9, c[2] - 1.4)
        tube(b, (lean[0] * z0 / H, lean[1] * z0 / H, min(z0, H - .3)), c * .85 + cc * .15, .05, .012, 3, 5)
        blob(b, c, (brad * rng.uniform(.8, 1.2), brad * rng.uniform(.8, 1.2), brad * rng.uniform(.7, 1.0)), rng, cc, 1, .24, .55)
    blob(b, cc + UP * crz * .85, (brad, brad, brad * .8), rng, cc, 1, .2, .55)
    export(name, b)


def birch():
    broadleaf("taiga_birch.glb", 5, 6.6, .23, 5.0, 1.3, 1.2, 11, .9)


def aspen():
    broadleaf("taiga_aspen.glb", 6, 9.0, .22, 6.9, .9, 1.9, 12, .85, lean=(.1, 0))


def alder():
    broadleaf("taiga_alder.glb", 7, 6.0, .20, 4.1, 1.6, 1.2, 10, .95, lean=(-.2, .1), second=(.6, .3, 5.2))


# --------------------------------------------------------------- small things ---
def bush():
    rng = np.random.default_rng(8)
    b = Builder()
    cc = np.array([0, 0, .5])
    for i in range(5):
        a = 2 * math.pi * i / 5 + rng.uniform(-.3, .3); L = rng.uniform(.9, 1.4)
        tube(b, (0, 0, .02), (math.cos(a) * L * .5, math.sin(a) * L * .5, L), .035, .01, 3, 4, (0, 0, .06))
    for i in range(7):
        a = 2 * math.pi * i / 7 + rng.uniform(-.3, .3); r = rng.uniform(.2, .6)
        blob(b, (math.cos(a) * r, math.sin(a) * r, rng.uniform(.4, 1.0)), (rng.uniform(.4, .6), rng.uniform(.4, .6), rng.uniform(.3, .5)), rng, cc, 1, .24, .5)
    export("taiga_bush.glb", b)


def stump():
    rng = np.random.default_rng(13)
    b = Builder()
    h = .85; r = .36
    tube(b, (0, 0, 0), (0, 0, h), r * 1.02, r * .86, 4, 9, flare=.9, rng=rng, wobble=.05)
    disc(b, (0, 0, h), r * .86, UP)
    for i in range(4):
        a = 2 * math.pi * i / 4 + rng.uniform(-.3, .3)
        tube(b, (math.cos(a) * .2, math.sin(a) * .2, .25), (math.cos(a) * .7, math.sin(a) * .7, -.03), .1, .03, 3, 5, (0, 0, .05))
    export("taiga_stump.glb", b)


def fallen_log():
    rng = np.random.default_rng(14)
    b = Builder()
    a, c = np.array([0, 0, .38]), np.array([3.1, .08, .28])
    tube(b, a, c, .34, .27, 8, 9, (0, 0, .1), rng=rng, wobble=.05)
    disc(b, a, .32, (-1, 0, 0)); disc(b, c, .25, (1, 0, 0))
    for t in (.3, .6):
        p = a * (1 - t) + c * t + np.array([0, 0, .27]); ang = rng.uniform(0, 6.28)
        tube(b, p - UP * .06, p + np.array([math.cos(ang) * .3, math.sin(ang) * .3, .12]), .045, .018, 2, 4)
    export("taiga_fallen_log.glb", b)


def rock():
    rng = np.random.default_rng(12)
    m = trimesh.creation.icosphere(subdivisions=2, radius=1)
    v = np.asarray(m.vertices)
    f = 1 + .16 * np.sin(v[:, 0] * 7 + v[:, 2] * 3) + .1 * np.cos(v[:, 1] * 9 - v[:, 0] * 2) + .05 * rng.uniform(-1, 1, len(v))
    v = v * f[:, None] * np.array([1.25, .72, .92]) + np.array([0, 0, .6])
    v[:, 2] = np.maximum(v[:, 2], .02)
    b = Builder()
    b.add("rock", v, m.faces, np.zeros((len(v), 2)), unit(v - np.array([0, 0, .6])))
    export("taiga_rock.glb", b)


ALL = [spruce, pine, larch, cedar, birch, aspen, alder, bush, stump, fallen_log, rock]

if __name__ == "__main__":
    for fn in ALL:
        fn()
    print(f"Generated {len(ALL)} painterly Taiga GLB models in", OUT)
