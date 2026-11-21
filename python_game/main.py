from __future__ import annotations

import math
from direct.showbase.ShowBase import ShowBase
from panda3d.core import (
    AmbientLight, DirectionalLight, Fog, Geom, GeomNode, GeomTriangles,
    GeomVertexData, GeomVertexFormat, GeomVertexWriter, NodePath,
    Point3, Vec3, Vec4, WindowProperties,
)


def height_at(x: float, z: float) -> float:
    """Deterministic low-frequency terrain function; stable for a given world seed."""
    broad = math.sin(x * 0.035) * 1.7 + math.cos(z * 0.028) * 1.35
    rolling = math.sin((x + z) * 0.012) * 2.0
    detail = math.sin(x * 0.11 + z * 0.07) * 0.16
    return broad + rolling + detail


def build_terrain(parent: NodePath, extent: float = 90.0, cells: int = 96) -> NodePath:
    fmt = GeomVertexFormat.getV3n3c4()
    data = GeomVertexData("terrain", fmt, Geom.UHStatic)
    data.setNumRows((cells + 1) ** 2)
    vertex = GeomVertexWriter(data, "vertex")
    normal = GeomVertexWriter(data, "normal")
    color = GeomVertexWriter(data, "color")
    step = (extent * 2.0) / cells

    for z_index in range(cells + 1):
        z = -extent + z_index * step
        for x_index in range(cells + 1):
            x = -extent + x_index * step
            y = height_at(x, z)
            dx = height_at(x + 0.25, z) - height_at(x - 0.25, z)
            dz = height_at(x, z + 0.25) - height_at(x, z - 0.25)
            n = Vec3(-dx, -dz, 0.5).normalized()
            vertex.addData3(x, y, z)
            normal.addData3(n)
            shade = 0.82 + 0.08 * math.sin(x * 0.08) * math.cos(z * 0.06)
            color.addData4(0.22 * shade, 0.28 * shade, 0.16 * shade, 1.0)

    triangles = GeomTriangles(Geom.UHStatic)
    row = cells + 1
    for z_index in range(cells):
        for x_index in range(cells):
            a = z_index * row + x_index
            b, c, d = a + 1, a + row, a + row + 1
            triangles.addVertices(a, b, c)
            triangles.addVertices(b, d, c)
    geom = Geom(data)
    geom.addPrimitive(triangles)
    node = GeomNode("terrain")
    node.addGeom(geom)
    terrain = parent.attachNewNode(node)
    terrain.setTwoSided(True)
    terrain.setColor(1, 1, 1, 1)
    return terrain


def make_tree(parent: NodePath, x: float, y: float, z: float, scale: float, species: int) -> NodePath:
    tree = parent.attachNewNode(f"tree-{species}")
    trunk = tree.attachNewNode("trunk")
    trunk.setPos(0, 0, 0)
    trunk.setScale(0.16 * scale, 0.16 * scale, 1.35 * scale)
    trunk.setColor(0.28, 0.17, 0.09, 1)
    crown = tree.attachNewNode("crown")
    crown.setPos(0, 0, 1.65 * scale)
    crown.setScale(0.9 * scale, 0.9 * scale, 1.15 * scale)
    palette = (
        (0.12, 0.28, 0.12, 1),
        (0.22, 0.38, 0.18, 1),
        (0.30, 0.40, 0.19, 1),
    )
    crown.setColor(*palette[species % len(palette)])
    tree.setPos(x, y, z)
    return tree


class WildlandsApp(ShowBase):
    def __init__(self) -> None:
        super().__init__()
        props = WindowProperties()
        props.setTitle("Wildlands — Python prototype")
        props.setSize(1280, 720)
        props.setFullscreen(False)
        self.win.requestProperties(props)
        self.disableMouse()
        self.setBackgroundColor(0.47, 0.61, 0.68, 1)

        ambient = AmbientLight("ambient")
        ambient.setColor(Vec4(0.58, 0.62, 0.56, 1))
        self.render.setLight(self.render.attachNewNode(ambient))
        sun = DirectionalLight("sun")
        sun.setColor(Vec4(1.0, 0.92, 0.78, 1))
        sun_np = self.render.attachNewNode(sun)
        sun_np.setHpr(-35, -55, 0)
        self.render.setLight(sun_np)
        fog = Fog("forest-atmosphere")
        fog.setColor(0.47, 0.61, 0.68)
        fog.setExpDensity(0.0022)
        self.render.setFog(fog)

        build_terrain(self.render)
        self._build_forest()
        self.player = self.render.attachNewNode("player-root")
        self.player.setPos(0, 0, height_at(0, 0) + 0.9)
        self.player_visual = self.loader.loadModel("models/box")
        self.player_visual.reparentTo(self.player)
        self.player_visual.setScale(0.32, 0.32, 0.9)
        self.player_visual.setColor(0.22, 0.38, 0.31, 1)
        self.player_visual.setZ(0.1)

        self.camera.setPos(10.5, -25.0, 19.0)
        self.camera.lookAt(0, 0, 0)
        self.taskMgr.add(self._update, "game-update")

    def _build_forest(self) -> None:
        for row in range(-8, 9):
            for col in range(-8, 9):
                if abs(row) < 2 and abs(col) < 2:
                    continue
                x = col * 7.4 + math.sin(row * 2.3 + col) * 1.7
                y = row * 7.1 + math.cos(col * 1.7 - row) * 1.4
                species = (row * 7 + col * 11) % 3
                scale = 0.78 + ((row * 13 + col * 5) % 7) * 0.075
                make_tree(self.render, x, y, height_at(x, y), scale, species)

    def _update(self, task):
        return task.cont


if __name__ == "__main__":
    WildlandsApp().run()
