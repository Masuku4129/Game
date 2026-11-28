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
        # Reject collapsed/non-finite triangles before Godot LOD generation.
        finite_vertices = np.isfinite(v).all(axis=1)
        valid_indices = (f >= 0).all(axis=1) & (f < len(v)).all(axis=1)
        safe_faces = f[valid_indices]
        tri = v[safe_faces]
        area2 = np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1)
        valid_faces = np.isfinite(tri).all(axis=(1, 2)) & np.isfinite(area2) & (area2 > 1e-10)
        valid_faces &= finite_vertices[safe_faces].all(axis=1)
        removed_faces = len(f) - int(valid_faces.sum())
        f = safe_faces[valid_faces]
        if len(f) == 0:
            raise RuntimeError(f"{name}/{key}: no valid triangles remain")
        n = np.nan_to_num(n, nan=0.0, posinf=0.0, neginf=0.0)
        nlen = np.linalg.norm(n, axis=1)
        fallback = unit(v - np.mean(v[finite_vertices], axis=0))
        n[nlen < 1e-8] = fallback[nlen < 1e-8]
        n = unit(n)
        mesh = trimesh.Trimesh(vertices=v, faces=f, vertex_normals=n, process=False)
        mesh.visual = TextureVisuals(uv=np.vstack(e["uv"]))
        scene.add_geometry(mesh, geom_name=key, node_name=key)
        tris += len(f)
    data = scene.export(file_type="glb")
    (OUT / name).write_bytes(data)
    print(f"{name:24s} meshes={'/'.join(b.d)} tris={tris:5d} dropped={removed_faces:4d} {len(data)/1024:6.1f} KB")



# --------------------------------------------------------- ground cover GLBs ---
def fern():
    rng = np.random.default_rng(21); b = Builder()
    # A distinct crown of arching rachises with many paired leaflets.
    for frond in range(9):
        a = math.tau * frond / 9 + rng.uniform(-.16, .16)
        reach = rng.uniform(.72, 1.12); rise = rng.uniform(.42, .72)
        end = np.array([math.cos(a) * reach, math.sin(a) * reach, rise])
        tube(b, (0, 0, .04), end, .025, .009, 5, 5, key="bark", rng=rng)
        axis = end / max(np.linalg.norm(end), 1e-6)
        side = np.array([-math.sin(a), math.cos(a), 0.0])
        for j in range(1, 8):
            t = j / 8
            p = end * t
            size = (.22 * (1.0 - t * .55)) * rng.uniform(.8, 1.15)
            for sign in (-1, 1):
                q = p + side * sign * size * .72 + np.array([0, 0, size * .12])
                blob(b, q, (size * .72, size * .22, size * .09), rng, np.array([0,0,.4]), 1, .1, .62, "foliage")
    export("taiga_fern.glb", b)


def reed():
    rng = np.random.default_rng(22); b = Builder()
    for i in range(13):
        a = rng.uniform(0, math.tau); rad = rng.uniform(.08, .42)
        base = np.array([math.cos(a)*rad, math.sin(a)*rad, 0.0])
        h = rng.uniform(1.0, 1.9)
        tip = base + np.array([math.cos(a)*rng.uniform(.08,.22), math.sin(a)*rng.uniform(.08,.22), h])
        tube(b, base, tip, .018, .008, 5, 4, key="bark", rng=rng)
        for t in (.28, .48, .67):
            p = base*(1-t) + tip*t
            side = np.array([-math.sin(a), math.cos(a), .15])
            leaf_tip = p + side*rng.uniform(.22,.42) + np.array([0,0,.12])
            tube(b, p, leaf_tip, .018, .003, 3, 3, key="foliage", rng=rng)
        if i % 3 == 0:
            blob(b, tip + np.array([0,0,.10]), (.055,.055,.20), rng, tip, 1, .08, .6, "foliage")
    export("taiga_reed.glb", b)


def moss():
    rng = np.random.default_rng(23); b = Builder()
    for i in range(18):
        a = math.tau*i/18 + rng.uniform(-.2,.2); r = rng.uniform(.08,.52)
        c = np.array([math.cos(a)*r, math.sin(a)*r, rng.uniform(.02,.10)])
        blob(b, c, (rng.uniform(.14,.28), rng.uniform(.12,.25), rng.uniform(.07,.14)), rng, np.array([0,0,.0]), 1, .12, .62, "foliage")
    export("taiga_moss.glb", b)


def mushroom():
    rng = np.random.default_rng(24); b = Builder()
    for i in range(3):
        x,y = rng.uniform(-.28,.28,2); h = rng.uniform(.22,.42); rad = rng.uniform(.12,.22)
        tube(b, (x,y,0), (x,y,h), .055, .035, 5, 7, key="bark", rng=rng)
        blob(b, (x,y,h+.035), (rad,rad,.09), rng, np.array([x,y,h]), 2, .08, .62, "foliage")
    export("taiga_mushroom.glb", b)


def flower():
    rng = np.random.default_rng(25); b = Builder()
    for i in range(5):
        a = math.tau*i/5; x,y = math.cos(a)*.12, math.sin(a)*.12
        h = rng.uniform(.35,.68)
        tube(b, (x,y,0), (x*.7,y*.7,h), .018, .009, 4, 4, key="bark", rng=rng)
        for j in range(4):
            q = np.array([x*.7,y*.7,h*.55]) + np.array([math.cos(a+j*math.pi/2)*.12, math.sin(a+j*math.pi/2)*.12,.03])
            blob(b, q, (.10,.055,.035), rng, np.array([x,y,h*.55]), 1, .05, .6, "foliage")
        blob(b, (x*.7,y*.7,h+.035), (.07,.07,.07), rng, np.array([x,y,h]), 1, .04, .6, "foliage")
    export("taiga_flower.glb", b)


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
    """Broad rounded cartoon bough tier with a soft scalloped skirt, not a sharp cone."""
    n = max(24, teeth * 4)
    verts, faces = [], []
    rings = [(0.34, 0.42), (0.72, 0.12), (1.0, -0.23), (0.78, -0.43)]
    phase = rng.uniform(0.0, math.tau)
    for ri, (rf, zf) in enumerate(rings):
        for i in range(n):
            a = math.tau * i / n
            wave = (0.055 * math.sin(a * teeth + phase)
                    + 0.022 * math.sin(a * teeth * 2.0 - phase * 0.7))
            edge = 1.0 + wave if ri >= 2 else 1.0 + wave * 0.35
            rr = r * rf * edge * rng.uniform(.985, 1.015)
            zz = z + h * zf + (wave * h * 0.55 if ri >= 2 else 0.0)
            verts.append([math.cos(a) * rr, math.sin(a) * rr, zz])
    for ri in range(len(rings) - 1):
        for i in range(n):
            a = ri * n + i
            c = ri * n + (i + 1) % n
            d = (ri + 1) * n + i
            e = (ri + 1) * n + (i + 1) % n
            faces += [[a, d, c], [c, d, e]]
    verts = np.asarray(verts, float)
    center = np.array([0.0, 0.0, z + h * 0.12])
    normals = unit(verts - center)
    b.add(key, verts, faces, np.zeros((len(verts), 2)), normals)


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
            if .16 < np.dot(o, o) <= 1:
                break
        c = cc + o * np.array([crx, crx, crz])
        z0 = max(ccz - crz * .9, c[2] - 1.4)
        # Branches remain visible as tapered supports beneath the painted canopy lobes.
        tube(b, (lean[0] * z0 / H, lean[1] * z0 / H, min(z0, H - .3)), c * .85 + cc * .15, .055, .012, 3, 5)
        rx = brad * rng.uniform(.78, 1.18)
        ry = brad * rng.uniform(.78, 1.18)
        rz = brad * rng.uniform(.72, 1.08)
        blob(b, c, (rx, ry, rz), rng, cc, 2, .16, .58)
    # A slightly taller crown cap ties the separate lobes into one readable silhouette.
    blob(b, cc + UP * crz * .82, (brad * .96, brad * .92, brad * .88), rng, cc, 2, .15, .62)
    export(name, b)


def birch():
    broadleaf("taiga_birch.glb", 5, 6.6, .23, 5.0, 1.3, 1.2, 11, .9)


def aspen():
    broadleaf("taiga_aspen.glb", 6, 9.0, .22, 6.9, .9, 1.9, 12, .85, lean=(.1, 0))


def alder():
    broadleaf("taiga_alder.glb", 7, 6.0, .20, 4.1, 1.6, 1.2, 10, .95, lean=(-.2, .1), second=(.6, .3, 5.2))


def fir():
    """Narrow, dense fir silhouette with short, irregular tiers and a visible leader."""
    rng = np.random.default_rng(26)
    b = Builder()
    H = 9.2
    tube(b, (0, 0, 0), (.02, -.03, H), .31, .025, 10, 7, (.05, 0, 0), flare=.9, rng=rng, wobble=.035)
    for i in range(15):
        t = i / 14
        z = 1.0 + t * 7.3
        radius = 2.0 * (1.0 - t) ** .82 + .16
        phase = rng.uniform(-.18, .18)
        for k in range(5):
            a = math.tau * k / 5 + phase + i * .29
            reach = radius * rng.uniform(.72, 1.05)
            end = np.array([math.cos(a) * reach, math.sin(a) * reach, z + rng.uniform(-.12, .12)])
            tube(b, (0, 0, z - .12), end, .095 * (1.0 - t * .55), .025, 4, 5, rng=rng, wobble=.04)
            blob(b, end + np.array([0, 0, -.10]), (reach * .43, reach * .43, .22 + reach * .12), rng,
                 np.array([0, 0, z]), 1, .14, .6, "foliage")
    export("taiga_fir.glb", b)


def willow():
    """Broad river willow with curved limbs and distinct hanging foliage curtains."""
    rng = np.random.default_rng(27)
    b = Builder()
    tube(b, (0, 0, 0), (-.12, .04, 6.8), .34, .075, 12, 8, (.18, 0, 0), flare=1.0, rng=rng, wobble=.04)
    for i in range(9):
        a = math.tau * i / 9 + rng.uniform(-.15, .15)
        reach = rng.uniform(2.0, 3.0)
        z = rng.uniform(4.0, 5.8)
        shoulder = np.array([math.cos(a) * reach * .52, math.sin(a) * reach * .52, z + .55])
        tip = np.array([math.cos(a) * reach, math.sin(a) * reach, z - rng.uniform(.45, .9)])
        tube(b, (0, 0, z - .6), shoulder, .12, .055, 5, 6, rng=rng, wobble=.04)
        tube(b, shoulder, tip, .06, .018, 6, 5, bend=(math.cos(a) * .18, math.sin(a) * .18, -.35), rng=rng)
        for j in range(4):
            t = .25 + j * .18
            center = shoulder * (1 - t) + tip * t
            center[2] -= .16
            blob(b, center, (.32, .30, .46), rng, np.array([0, 0, 4.7]), 1, .18, .62, "foliage")
        for j in range(3):
            t = .48 + j * .16
            q = shoulder * (1 - t) + tip * t
            q[2] -= .55
            tube(b, q, q + np.array([math.cos(a) * .08, math.sin(a) * .08, -.55]), .022, .008, 3, 4, key="foliage", rng=rng)
    blob(b, (-.1, 0, 6.2), (1.15, 1.1, .8), rng, np.array([0, 0, 5.4]), 1, .16, .6, "foliage")
    export("taiga_willow.glb", b)


def rowan():
    """Airy rowan crown: slim trunk, open branching and separated foliage clusters."""
    broadleaf("taiga_rowan.glb", 28, 7.2, .19, 5.4, 1.75, 1.35, 9, .56, lean=(.08, -.04),
              second=(.38, -.12, 6.0))


def juniper():
    """Low, wide juniper shrub with spreading woody arms and dense rounded tips."""
    rng = np.random.default_rng(29)
    b = Builder()
    center = np.array([0.0, 0.0, .48])
    for i in range(11):
        a = math.tau * i / 11 + rng.uniform(-.2, .2)
        reach = rng.uniform(.75, 1.5)
        rise = rng.uniform(.35, .9)
        end = np.array([math.cos(a) * reach, math.sin(a) * reach, rise])
        tube(b, (0, 0, .12), end, .10, .025, 5, 5, bend=(0, 0, .12), rng=rng, wobble=.05)
        for t in (.55, .82, 1.0):
            q = end * t
            blob(b, q, (rng.uniform(.32, .48), rng.uniform(.28, .42), rng.uniform(.24, .38)),
                 rng, center, 1, .16, .62, "foliage")
    blob(b, (0, 0, .55), (.58, .54, .42), rng, center, 1, .13, .62, "foliage")
    export("taiga_juniper.glb", b)


# --------------------------------------------------------------- small things ---
def bush():
    """Layered, asymmetrical berry shrub with visible woody stems and broad leaf clusters."""
    rng = np.random.default_rng(8)
    b = Builder()
    cc = np.array([0.0, 0.0, 0.62])
    count = 9
    for i in range(count):
        a = math.tau * i / count + rng.uniform(-.22, .22)
        reach = rng.uniform(.62, 1.05)
        height = rng.uniform(.72, 1.28)
        end = np.array([math.cos(a) * reach, math.sin(a) * reach, height])
        tube(b, (0, 0, .04), end * np.array([.78, .78, .86]), .055, .018, 4, 5,
             (rng.uniform(-.08, .08), rng.uniform(-.08, .08), .08))
        # Two overlapping lobes per branch create a continuous leafy silhouette.
        for side in (-1, 1):
            offset = np.array([math.cos(a + side * .34) * .18,
                               math.sin(a + side * .34) * .18,
                               rng.uniform(-.08, .16)])
            center = end + offset
            radii = (rng.uniform(.34, .48), rng.uniform(.30, .43), rng.uniform(.28, .40))
            blob(b, center, radii, rng, cc, 2, .12, .62)
    blob(b, (0.0, 0.0, 1.05), (.48, .44, .42), rng, cc, 2, .11, .65)
    export("taiga_bush.glb", b)


def stump():
    """Broken cartoon stump with a jagged crown, flared roots and layered growth rings."""
    rng = np.random.default_rng(13)
    b = Builder()
    h, r = .92, .37
    tube(b, (0, 0, 0), (0, 0, h), r * 1.12, r * .82,
         6, 11, bend=(.025, -.015, 0), flare=1.0, rng=rng, wobble=.085)
    # Uneven broken rim gives the cut surface a hand-shaped silhouette.
    rim = []
    for i in range(18):
        a = math.tau * i / 18
        rim.append([math.cos(a) * r * .84, math.sin(a) * r * .84,
                    h + .10 * math.sin(a * 3.0 + .4) + .035 * math.sin(a * 7.0)])
    verts = [[0.0, 0.0, h]] + rim
    faces = [[0, 1 + i, 1 + (i + 1) % len(rim)] for i in range(len(rim))]
    b.add("cut", verts, faces, np.zeros((len(verts), 2)), np.tile(UP, (len(verts), 1)))
    for i in range(6):
        a = math.tau * i / 6 + rng.uniform(-.2, .2)
        reach = rng.uniform(.48, .72)
        tube(b, (math.cos(a) * .16, math.sin(a) * .16, .24),
             (math.cos(a) * reach, math.sin(a) * reach, -.025),
             rng.uniform(.09, .13), .018, 4, 6, (0, 0, .07), flare=.35, rng=rng, wobble=.08)
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
    """Low, broad cartoon boulder: flattened base, broad planes and an irregular crown."""
    rng = np.random.default_rng(12)
    m = trimesh.creation.icosphere(subdivisions=2, radius=1)
    v = np.asarray(m.vertices)
    az = np.arctan2(v[:, 1], v[:, 0])
    crown = 1.0 + .10 * np.sin(az * 5.0 + v[:, 2] * 2.0) + .045 * np.cos(az * 9.0)
    broad = 1.0 + .09 * np.sin(v[:, 0] * 3.0 + v[:, 2] * 2.0) * np.cos(v[:, 1] * 2.5)
    f = crown * broad + .025 * rng.uniform(-1, 1, len(v))
    v = v * f[:, None] * np.array([1.34, .94, .78]) + np.array([0, 0, .61])
    # Flatten the foot into a stable, grounded cartoon silhouette.
    v[:, 2] = np.maximum(v[:, 2], .035)
    center = np.array([0.0, 0.0, .61])
    n = unit(v - center)
    # Broad, softened facets instead of a noisy pebble surface.
    b = Builder()
    b.add("rock", v, m.faces, np.zeros((len(v), 2)), n)
    export("taiga_rock.glb", b)



def hazel():
    """Multi-stem hazel shrub with layered leaf clusters and visible woody forks."""
    rng = np.random.default_rng(31)
    b = Builder()
    cc = np.array([0.0, 0.0, 1.15])
    for i in range(7):
        a = math.tau * i / 7 + rng.uniform(-.18, .18)
        reach = rng.uniform(.45, .9)
        h = rng.uniform(1.35, 2.15)
        end = np.array([math.cos(a) * reach, math.sin(a) * reach, h])
        tube(b, (0, 0, .04), end, .075, .022, 5, 5, bend=(.04, -.03, .06), rng=rng, wobble=.04)
        for t in (.58, .86, 1.0):
            q = end * t
            blob(b, q, (rng.uniform(.30,.42), rng.uniform(.28,.39), rng.uniform(.28,.38)), rng, cc, 2, .14, .6)
    export("taiga_hazel.glb", b)


def dogrose():
    """Open thorny dog-rose shrub with arching stems and pink flower clusters."""
    rng = np.random.default_rng(32)
    b = Builder()
    cc = np.array([0.0, 0.0, .95])
    for i in range(8):
        a = math.tau * i / 8 + rng.uniform(-.2,.2)
        reach = rng.uniform(.55, 1.05)
        end = np.array([math.cos(a)*reach, math.sin(a)*reach, rng.uniform(.9,1.65)])
        tube(b, (0,0,.04), end, .045, .012, 4, 5, bend=(.05*math.cos(a),.05*math.sin(a),.08), rng=rng, wobble=.06)
        for t in (.62,.92):
            q=end*t
            blob(b,q,(.24,.22,.20),rng,cc,2,.12,.58,"foliage")
        if i % 2 == 0:
            blob(b,end+np.array([0,0,.10]),(.13,.13,.12),rng,cc,2,.08,.65,"foliage")
    export("taiga_dogrose.glb", b)


def dead_birch():
    """Weathered dead birch snag with broken crown, exposed branches and pale bark."""
    rng = np.random.default_rng(33)
    b = Builder()
    h = 7.1
    tube(b,(0,0,0),(.12,-.04,h),.24,.055,9,7,(.08,0,0),flare=1.0,rng=rng,wobble=.07)
    for i in range(6):
        a=math.tau*i/6+rng.uniform(-.2,.2)
        z=rng.uniform(3.0,6.1)
        reach=rng.uniform(.65,1.35)
        end=np.array([math.cos(a)*reach,math.sin(a)*reach,z+rng.uniform(-.2,.35)])
        tube(b,(0,0,z),end,.075,.018,4,5,rng=rng,wobble=.08)
    tip=np.array([.12,-.04,h])
    tube(b,tip,tip+np.array([.35,.08,-.55]),.055,.012,3,5,rng=rng)
    export("taiga_dead_birch.glb",b)


def sedge_clump():
    """Dense tuft of curved sedge blades for wet banks and bog hummocks."""
    rng=np.random.default_rng(34)
    b=Builder()
    for i in range(27):
        a=rng.uniform(0,math.tau)
        reach=rng.uniform(.12,.48)
        h=rng.uniform(.38,.95)
        base=np.array([math.cos(a)*rng.uniform(0,.18),math.sin(a)*rng.uniform(0,.18),.02])
        mid=base+np.array([math.cos(a)*reach*.45,math.sin(a)*reach*.45,h*.55])
        tip=base+np.array([math.cos(a)*reach,math.sin(a)*reach,h])
        tube(b,base,mid,.025,.014,3,4,key="foliage",rng=rng)
        tube(b,mid,tip,.014,.003,3,4,key="foliage",rng=rng)
    export("taiga_sedge.glb",b)


ALL = [spruce, pine, larch, cedar, fir, birch, aspen, alder, willow, rowan, juniper, bush, hazel, dogrose, dead_birch, sedge_clump, stump, fallen_log, rock, fern, reed, moss, mushroom, flower]

if __name__ == "__main__":
    for fn in ALL:
        fn()
    print(f"Generated {len(ALL)} painterly Taiga GLB models in", OUT)
