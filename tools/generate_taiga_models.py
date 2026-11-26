#!/usr/bin/env python3
"""Generate original, textured, Y-up, import-ready Taiga environment GLBs.

Pipeline: tools/gen_model_textures.py -> game/models/environment/textures/*.png
          tools/generate_taiga_models.py (this file) -> game/models/environment/*.glb

Every mesh carries real UVs and a glTF PBR material with an embedded texture
(bark / needle sprays / leaf sprigs / fern / grass / rock / moss / wood end grain).
Geometry is merged per material, so each model is 1-4 draw calls on mobile.
No third-party meshes or images are used.
"""
from pathlib import Path
import math
import numpy as np
import trimesh
from PIL import Image
from trimesh.visual.material import PBRMaterial
from trimesh.visual import TextureVisuals

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "models" / "environment"
TEX = OUT / "textures"
OUT.mkdir(parents=True, exist_ok=True)
UP = np.array([0., 0., 1.])
ALPHA_PREFIX = ("needle_", "leaf_", "fern_", "grass_")


# ------------------------------------------------------------------ infra ---
class Builder:
    """Accumulates geometry per material key (= texture base name)."""

    def __init__(self):
        self.d = {}

    def add(self, key, v, f, uv, n):
        e = self.d.setdefault(key, {"v": [], "f": [], "uv": [], "n": [], "off": 0})
        v = np.asarray(v, float); f = np.asarray(f, int)
        e["v"].append(v); e["f"].append(f + e["off"])
        e["uv"].append(np.asarray(uv, float)); e["n"].append(np.asarray(n, float))
        e["off"] += len(v)


_img_cache = {}


def _img(name):
    if name not in _img_cache:
        im = Image.open(TEX / name)
        _img_cache[name] = im.convert("RGBA" if im.mode == "RGBA" else "RGB")
    return _img_cache[name]


def material(key):
    alpha = key.startswith(ALPHA_PREFIX)
    kw = dict(name=key, baseColorTexture=_img(key + ".png"), metallicFactor=0.0,
              roughnessFactor=1.0, doubleSided=True)
    if (TEX / (key + "_n.png")).exists():
        kw["normalTexture"] = _img(key + "_n.png")
    if alpha:
        kw.update(alphaMode="MASK", alphaCutoff=0.5)
    return PBRMaterial(**kw)


def export(name, b):
    scene = trimesh.Scene()
    rot = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float)  # Z-up -> glTF Y-up
    tris = 0
    for key, e in b.d.items():
        v = np.vstack(e["v"]) @ rot.T
        n = np.vstack(e["n"]) @ rot.T
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        f = np.vstack(e["f"]); uv = np.vstack(e["uv"])
        mesh = trimesh.Trimesh(vertices=v, faces=f, vertex_normals=n, process=False)
        mesh.visual = TextureVisuals(uv=uv, material=material(key))
        scene.add_geometry(mesh, geom_name=key, node_name=key)
        tris += len(f)
    data = scene.export(file_type="glb")
    (OUT / name).write_bytes(data)
    print(f"{name:26s} materials={len(b.d)} tris={tris:6d} {len(data)/1024:7.1f} KB")


def unit(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-9)


def perp(d, phi=0.0):
    d = unit(d)
    ref = np.array([1., 0., 0.]) if abs(d[2]) > .9 else UP
    w = unit(np.cross(d, ref))
    # rotate w around d by phi (Rodrigues)
    return w * math.cos(phi) + np.cross(d, w) * math.sin(phi) + d * np.dot(d, w) * (1 - math.cos(phi))


# --------------------------------------------------------------- primitives ---
def tube(b, key, a, c, r0, r1, sections=8, sides=8, bend=(0, 0, 0), flare=0.0,
         tile_m=1.3, wobble=0.0, rng=None):
    """Tapered tube with seam-correct UVs. u wraps the circumference, v runs along length."""
    a, c = np.asarray(a, float), np.asarray(c, float)
    axis = c - a; length = np.linalg.norm(axis)
    if length < 1e-6:
        return
    d = axis / length
    u_ax = perp(d); v_ax = np.cross(d, u_ax)
    urep = max(2, int(round(2 * math.pi * max(r0, r1 * 1.5) / 0.85)))
    verts, uvs, nrm, faces = [], [], [], []
    ph = rng.uniform(0, 6.28) if rng is not None else 0.0
    for i in range(sections + 1):
        t = i / sections
        ctr = a * (1 - t) + c * t + np.asarray(bend) * math.sin(math.pi * t)
        rad = r0 * (1 - t) + r1 * t
        rad *= 1 + flare * math.exp(-t * length * 2.2)
        for j in range(sides + 1):
            ang = 2 * math.pi * j / sides
            w = 1 + wobble * math.sin(j * 2.0 * 2 * math.pi / sides * 1.5 + t * 7 + ph)
            dirv = u_ax * math.cos(ang) + v_ax * math.sin(ang)
            verts.append(ctr + dirv * rad * w)
            nrm.append(dirv)
            uvs.append((j / sides * urep, t * length / tile_m))
    for i in range(sections):
        for j in range(sides):
            p = i * (sides + 1) + j
            q = p + 1
            faces += [[p, p + sides + 1, q], [q, p + sides + 1, q + sides + 1]]
    b.add(key, verts, faces, uvs, nrm)


def strip(b, key, p0, p1, wdir, width, segs=3, droop=0.0, ncenter=None, nup=0.3,
          taper=0.0, uvr=(0, 0, 1, 1)):
    """Bendable card from p0 (base) to p1 (tip); the texture's v axis runs along it."""
    p0, p1, wdir = np.asarray(p0, float), np.asarray(p1, float), unit(wdir)
    verts, uvs, nrm, faces = [], [], [], []
    u0, v0, u1, v1 = uvr
    for i in range(segs + 1):
        t = i / segs
        ctr = p0 * (1 - t) + p1 * t - UP * droop * t * t
        hw = width * .5 * (1 - taper * t)
        for s, uu in ((-1, u0), (1, u1)):
            p = ctr + wdir * hw * s
            verts.append(p)
            uvs.append((uu, v0 + (v1 - v0) * t))
            if ncenter is None:
                nrm.append(UP)
            else:
                nrm.append(unit(unit(p - ncenter) * (1 - nup) + UP * nup))
    for i in range(segs):
        p = i * 2
        faces += [[p, p + 1, p + 2], [p + 1, p + 3, p + 2]]
    b.add(key, verts, faces, uvs, nrm)


def spray(b, key, p0, p1, width, droop=0.0, phis=(0.0, math.pi / 2), ncenter=None, segs=3, taper=0.1, nup=.3):
    d = np.asarray(p1, float) - np.asarray(p0, float)
    for phi in phis:
        strip(b, key, p0, p1, perp(d, phi), width, segs, droop, ncenter, nup, taper)


def leaf_cluster(b, key, center, radius, count, size, ncenter, rng):
    """Cloud of randomly oriented leaf-sprig cards with radial (volumetric) normals."""
    for _ in range(count):
        o = rng.normal(size=3); o = unit(o) * radius * rng.uniform(.15, 1.0)
        o[2] *= .8
        pos = np.asarray(center, float) + o
        nrm = rng.normal(size=3)
        w = perp(nrm, rng.uniform(0, 6.28))
        h = unit(np.cross(nrm, w))
        sz = size * rng.uniform(.75, 1.25)
        base = pos - h * sz * .5
        tip = pos + h * sz * .5
        strip(b, key, base, tip, w, sz, 1, 0.0, ncenter, .15)


def disc(b, key, center, radius, axis, n=24, uv_scale=1.0):
    axis = unit(axis); u = perp(axis); v = np.cross(axis, u)
    verts = [np.asarray(center, float)]; uvs = [(.5, .5)]; nrm = [axis]; faces = []
    for j in range(n):
        a = 2 * math.pi * j / n
        verts.append(np.asarray(center, float) + (u * math.cos(a) + v * math.sin(a)) * radius)
        uvs.append((.5 + .5 * math.cos(a) * uv_scale, .5 + .5 * math.sin(a) * uv_scale))
        nrm.append(axis)
        faces.append([0, 1 + j, 1 + (j + 1) % n])
    b.add(key, verts, faces, uvs, nrm)


def box_uv(verts, faces, normals, scale):
    """Per-corner dominant-axis projection UVs (unmerged vertices, smooth normals kept)."""
    verts = np.asarray(verts); faces = np.asarray(faces)
    fn = np.cross(verts[faces[:, 1]] - verts[faces[:, 0]], verts[faces[:, 2]] - verts[faces[:, 0]])
    ax = np.argmax(np.abs(fn), axis=1)
    V = verts[faces].reshape(-1, 3); N = np.asarray(normals)[faces].reshape(-1, 3)
    uv = np.zeros((len(V), 2))
    for k in range(len(faces)):
        a = ax[k]
        idx = slice(k * 3, k * 3 + 3)
        c = V[idx]
        if a == 0: uv[idx] = c[:, [1, 2]]
        elif a == 1: uv[idx] = c[:, [0, 2]]
        else: uv[idx] = c[:, [0, 1]]
    return V, np.arange(len(V)).reshape(-1, 3), uv * scale, N


def moss_mound(b, center, size, rng, key="moss"):
    m = trimesh.creation.icosphere(subdivisions=3, radius=1.0)
    v = m.vertices.copy()
    n = np.sin(v[:, 0] * 5 + 1.3) * np.cos(v[:, 1] * 6) * .12 + np.sin(v[:, 2] * 9 + v[:, 0] * 3) * .06
    v *= (1 + n)[:, None] * np.array(size)
    v[:, 2] = np.maximum(v[:, 2], 0) + np.where(v[:, 2] < 0, 0, 0)
    v += np.asarray(center)
    mm = trimesh.Trimesh(v, m.faces, process=False)
    b.add(key, mm.vertices, mm.faces, (mm.vertices[:, :2] - np.asarray(center)[:2]) * 1.5 + .5, mm.vertex_normals)


# ----------------------------------------------------------------- conifers ---
def conifer(name, seed, key_bark, key_needle, height, r0, r1, tiers, z0, z1, boughs, length,
            width, droop, tilt, taper_len, bend=(.12, 0, 0), tuft=False, stubs=0, phis=(0, math.pi / 2, math.pi / 4),
            bough_r=.06):
    rng = np.random.default_rng(seed)
    b = Builder()
    top = np.array([.04, 0, height])
    tube(b, key_bark, (0, 0, 0), top, r0, r1, 24, 12, bend, flare=.9, wobble=.03, rng=rng)
    cc = np.array([.02, 0, height * .5])
    for ti, z in enumerate(np.linspace(z0, z1, tiers)):
        frac = max(0.0, 1 - (z - z0) / max(height - z0, 1e-3))
        nb = max(3, int(round(boughs * (.55 + .45 * frac))))
        for j in range(nb):
            a = 2 * math.pi * j / nb + ti * 2.39 + rng.uniform(-.25, .25)
            L = (length * (taper_len + (1 - taper_len) * frac) + .35) * rng.uniform(.82, 1.15)
            start = np.array([.03, 0, z + rng.uniform(-.12, .12)])
            end = start + np.array([math.cos(a) * L, math.sin(a) * L, -droop * L + tilt * L])
            tube(b, key_bark, start, end, bough_r * frac + .018, .012, 4, 6, (0, 0, -.05))
            inner = start + (end - start) * .12
            tip = end + unit(end - start) * .25
            if tuft:   # pine/cedar: clumps at the shoot ends
                for k in range(3):
                    off = np.array([rng.uniform(-.35, .35), rng.uniform(-.35, .35), rng.uniform(0, .3)])
                    spray(b, key_needle, end - unit(end - start) * .3, tip + off + UP * .25, width * 1.2, droop=.25, phis=phis, ncenter=cc)
                spray(b, key_needle, inner, end, width * .9, droop=.2, phis=(0, math.pi / 3), ncenter=cc)
            else:
                spray(b, key_needle, inner, tip, width * (.6 + .6 * frac) + .35, droop=droop * L * .6, phis=phis, ncenter=cc)
    # leader tuft
    spray(b, key_needle, top - UP * .8, top + UP * .55, width * .45, 0, phis=(0, math.pi / 2, math.pi / 4), ncenter=cc, segs=2, taper=.7)
    for i in range(stubs):
        z = rng.uniform(1.2, z0 + .5); a = rng.uniform(0, 6.28)
        s = np.array([.03, 0, z]); e = s + np.array([math.cos(a), math.sin(a), -.1]) * rng.uniform(.25, .55)
        tube(b, key_bark, s, e, .03, .012, 2, 5)
    export(name, b)


def spruce():
    conifer("taiga_spruce.glb", 1, "bark_spruce", "needle_spruce", 7.8, .34, .035, 13, .9, 7.2, 9, 2.2, 1.6, .22, -.02, .22)


def pine():
    conifer("taiga_pine.glb", 2, "bark_pine", "needle_pine", 11.0, .30, .05, 8, 6.4, 10.4, 5, 2.4, 1.8, .06, .22, .35,
            tuft=True, stubs=9, bough_r=.07)


def larch():
    conifer("taiga_larch.glb", 3, "bark_larch", "needle_larch", 10.0, .27, .04, 17, 1.8, 9.3, 5, 2.0, 1.25, .30, .02, .25,
            stubs=6, bough_r=.045)


def cedar():
    conifer("taiga_cedar.glb", 4, "bark_cedar", "needle_cedar", 9.0, .44, .05, 9, 1.6, 8.2, 6, 2.7, 2.1, .16, .12, .45,
            tuft=True, stubs=4, bough_r=.10)


# -------------------------------------------------------------- broadleaves ---
def broadleaf(name, seed, key_bark, key_branch, key_leaf, h, r0, ccz, crx, crz, clusters, cl_size, cl_count,
              lean=(0.0, 0.0), second=None):
    rng = np.random.default_rng(seed)
    b = Builder()
    top = np.array([lean[0], lean[1], h])
    tube(b, key_bark, (0, 0, 0), top, r0, .05, 24, 12, (.14, .05, 0), flare=.8, wobble=.03, rng=rng)
    if second:
        tube(b, key_bark, (.08, .05, 0), np.array(second), r0 * .7, .04, 18, 10, (-.1, 0, 0), flare=.5, rng=rng)
    cc = np.array([lean[0] * .6, lean[1] * .6, ccz])
    for i in range(clusters):
        while True:
            o = rng.uniform(-1, 1, 3)
            if np.dot(o, o) <= 1 and np.dot(o, o) > .25:
                break
        c = cc + o * np.array([crx, crx, crz])
        # branch
        z0 = max(ccz - crz * .9, c[2] - 1.5) + rng.uniform(0, .3)
        start = np.array([lean[0] * z0 / h, lean[1] * z0 / h, min(z0, h - .3)])
        tube(b, key_branch, start, c * .88 + cc * .12, .05 * (1 - o[2] * .3) + .012, .008, 5, 6, (0, 0, .12))
        leaf_cluster(b, key_leaf, c, cl_size * 1.1, cl_count, cl_size * 1.15, cc, rng)
    leaf_cluster(b, key_leaf, cc + UP * crz * .8, crx * .5, cl_count, cl_size * 1.15, cc, rng)
    export(name, b)


def birch():
    broadleaf("taiga_birch.glb", 5, "bark_birch", "bark_alder", "leaf_birch", 6.6, .23, 5.0, 1.5, 1.4, 22, .85, 14)


def aspen():
    broadleaf("taiga_aspen.glb", 6, "bark_aspen", "bark_aspen", "leaf_aspen", 9.0, .22, 6.9, 1.0, 2.0, 24, .8, 14, lean=(.1, .0))


def alder():
    broadleaf("taiga_alder.glb", 7, "bark_alder", "bark_alder", "leaf_alder", 6.0, .20, 4.1, 1.8, 1.3, 22, .85, 14,
              lean=(-.2, .1), second=(.6, .3, 5.2))


# ------------------------------------------------------------- undergrowth ---
def bush():
    rng = np.random.default_rng(8)
    b = Builder()
    cc = np.array([0, 0, .55])
    for i in range(11):
        a = 2 * math.pi * i / 11 + rng.uniform(-.2, .2); L = rng.uniform(.9, 1.5)
        end = np.array([math.cos(a) * L * .55, math.sin(a) * L * .55, L])
        tube(b, "bark_stump", (0, 0, .02), end, .035, .01, 5, 5, (0, 0, .08))
        for t in (.55, .85, 1.0):
            c = np.array([0, 0, .02]) + (end - np.array([0, 0, .02])) * t
            leaf_cluster(b, "leaf_bush", c, .32, 8, .5, cc, rng)
    export("taiga_bush.glb", b)


def fern():
    rng = np.random.default_rng(9)
    b = Builder()
    for i in range(10):
        a = 2 * math.pi * i / 10 + rng.uniform(-.2, .2)
        L = rng.uniform(.85, 1.2)
        p0 = np.array([0, 0, .04])
        p1 = np.array([math.cos(a) * L * .8, math.sin(a) * L * .8, rng.uniform(.5, .85)])
        w = perp(p1 - p0, rng.uniform(-.5, .5) + math.pi / 2 * 0)
        strip(b, "fern_frond", p0, p1, w, .6 * L, 5, droop=.5 * L, ncenter=np.array([0, 0, -.3]), nup=.5)
        strip(b, "fern_frond", p0, p1, perp(p1 - p0, math.pi / 2 + .4), .35 * L, 5, droop=.5 * L, ncenter=np.array([0, 0, -.3]), nup=.5)
    export("taiga_fern.glb", b)


def grass():
    rng = np.random.default_rng(10)
    b = Builder()
    for k in range(3):
        ang = k * math.pi / 3 + rng.uniform(-.1, .1)
        w = np.array([math.cos(ang), math.sin(ang), 0])
        strip(b, "grass_tuft", (0, 0, 0), (rng.uniform(-.05, .05), rng.uniform(-.05, .05), .75), w, .95, 3, droop=.08, taper=0)
    export("taiga_grass.glb", b)


def moss():
    rng = np.random.default_rng(11)
    b = Builder()
    moss_mound(b, (0, 0, 0), (.9, .7, .32), rng)
    moss_mound(b, (.7, .25, 0), (.45, .38, .2), rng)
    moss_mound(b, (-.5, -.4, 0), (.35, .3, .16), rng)
    export("taiga_moss.glb", b)


# ------------------------------------------------------------ rock / wood ---
def rock():
    rng = np.random.default_rng(12)
    m = trimesh.creation.icosphere(subdivisions=3, radius=1)
    v = m.vertices.copy()
    f = (1 + .13 * np.sin(v[:, 0] * 9 + v[:, 2] * 4) + .08 * np.cos(v[:, 1] * 11 - v[:, 0] * 3)
         + .04 * np.sin(v[:, 0] * 23 + v[:, 1] * 17))
    v = v * f[:, None] * np.array([1.25, .72, .92]) + np.array([0, 0, .62])
    v[:, 2] = np.maximum(v[:, 2], .02)
    mesh = trimesh.Trimesh(v, m.faces, process=False)
    nrm = mesh.vertex_normals
    fn = mesh.face_normals
    nz = np.sin(mesh.triangles_center[:, 0] * 4) * np.cos(mesh.triangles_center[:, 1] * 5) * .5 + .5
    mossy = (fn[:, 2] > .55) & (nz > .35)
    b = Builder()
    for sel, key, off in ((~mossy, "rock", 0.0), (mossy, "moss", .025)):
        F = mesh.faces[sel]
        V = v + nrm * off
        VV, FF, UV, NN = box_uv(V, F, nrm, .55)
        b.add(key, VV, FF, UV, NN)
    export("taiga_rock.glb", b)


def stump():
    rng = np.random.default_rng(13)
    b = Builder()
    h = .85; r = .36
    tube(b, "bark_stump", (0, 0, 0), (0, 0, h), r * 1.02, r * .86, 8, 14, flare=.9, wobble=.05, tile_m=1.0, rng=rng)
    disc(b, "wood_end", (0, 0, h), r * .86, UP, 24)
    for i in range(5):
        a = 2 * math.pi * i / 5 + rng.uniform(-.3, .3)
        s = np.array([math.cos(a) * .2, math.sin(a) * .2, .25])
        e = np.array([math.cos(a) * .75, math.sin(a) * .75, -.03])
        tube(b, "bark_stump", s, e, .11, .03, 4, 6, (0, 0, .05))
    moss_mound(b, (.18, .1, h - .02), (.2, .16, .07), rng)
    export("taiga_stump.glb", b)


def fallen_log():
    rng = np.random.default_rng(14)
    b = Builder()
    a, c = np.array([0, 0, .38]), np.array([3.1, .08, .28])
    tube(b, "bark_spruce", a, c, .34, .27, 28, 16, (0, 0, .1), wobble=.05, tile_m=1.3, rng=rng)
    disc(b, "wood_end", a, .32, (-1, 0, 0), 24)
    disc(b, "wood_end", c, .25, (1, 0, 0), 24)
    for t in (.25, .5, .75):
        p = a * (1 - t) + c * t + np.array([0, 0, .27])
        ang = rng.uniform(0, 6.28)
        e = p + np.array([math.cos(ang) * .3, math.sin(ang) * .3, .12])
        tube(b, "bark_spruce", p - UP * .06, e, .045, .018, 2, 5)
    moss_mound(b, (1.0, .1, .62), (.5, .22, .09), rng)
    moss_mound(b, (2.2, -.05, .56), (.38, .18, .07), rng)
    export("taiga_fallen_log.glb", b)


ALL = [spruce, pine, larch, cedar, birch, aspen, alder, bush, fern, grass, moss, rock, stump, fallen_log]

if __name__ == "__main__":
    for fn in ALL:
        fn()
    print(f"Generated {len(ALL)} textured Taiga GLB models in", OUT)
