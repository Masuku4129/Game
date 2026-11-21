from __future__ import annotations

import math
from pathlib import Path

from direct.showbase.ShowBase import ShowBase
from panda3d.core import (
    AmbientLight, DirectionalLight, Fog, Geom, GeomNode, GeomTriangles,
    GeomVertexData, GeomVertexFormat, GeomVertexWriter, NodePath,
    Vec3, Vec4, WindowProperties,
)

ROOT = Path(__file__).resolve().parent
SEASON = "summer"


def height_at(x: float, y: float) -> float:
    """Deterministic, continuous height field in Panda3D's Z-up coordinates."""
    broad = math.sin(x * 0.035) * 1.7 + math.cos(y * 0.028) * 1.35
    rolling = math.sin((x + y) * 0.012) * 2.0
    detail = math.sin(x * 0.11 + y * 0.07) * 0.16
    return broad + rolling + detail


def build_terrain(parent: NodePath, extent: float = 90.0, cells: int = 96) -> NodePath:
    fmt = GeomVertexFormat.getV3n3c4()
    data = GeomVertexData("terrain", fmt, Geom.UHStatic)
    data.setNumRows((cells + 1) ** 2)
    vertex = GeomVertexWriter(data, "vertex")
    normal = GeomVertexWriter(data, "normal")
    color = GeomVertexWriter(data, "color")
    step = (extent * 2.0) / cells

    for row in range(cells + 1):
        y = -extent + row * step
        for column in range(cells + 1):
            x = -extent + column * step
            z = height_at(x, y)
            dx = height_at(x + 0.25, y) - height_at(x - 0.25, y)
            dy = height_at(x, y + 0.25) - height_at(x, y - 0.25)
            n = Vec3(-dx, -dy, 0.5).normalized()
            vertex.addData3(x, y, z)
            normal.addData3(n)
            shade = 0.82 + 0.08 * math.sin(x * 0.08) * math.cos(y * 0.06)
            color.addData4(0.22 * shade, 0.28 * shade, 0.16 * shade, 1.0)

    triangles = GeomTriangles(Geom.UHStatic)
    row_width = cells + 1
    for row in range(cells):
        for column in range(cells):
            a = row * row_width + column
            b, c, d = a + 1, a + row_width, a + row_width + 1
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


class WildlandsApp(ShowBase):
    def __init__(self) -> None:
        super().__init__()
        props = WindowProperties()
        props.setTitle("Wildlands")
        props.setSize(1280, 720)
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
        self._load_player_model()

        self.camera.setPos(10.5, -25.0, 19.0)
        self.camera.lookAt(0, 0, 0)
        self.taskMgr.add(self._update, "game-update")

    def _load_seasonal_model(self, family: str) -> NodePath | None:
        model_path = ROOT / "assets" / "generated" / f"{family}_{SEASON}.glb"
        if not model_path.is_file():
            return None
        model = self.loader.loadModel(str(model_path))
        if model.isEmpty():
            return None
        model.flattenStrong()
        return model

    def _build_forest(self) -> None:
        families = ("tree_spruce", "tree_pine", "tree_birch")
        prototypes: dict[str, NodePath] = {}
        for family in families:
            prototype = self._load_seasonal_model(family)
            if prototype is not None:
                prototype.reparentTo(self.render)
                prototype.hide()
                prototypes[family] = prototype

        if not prototypes:
            print("ASSET_NOTICE: no seasonal tree GLBs found; forest instances skipped")
            return

        for row in range(-8, 9):
            for column in range(-8, 9):
                if abs(row) < 2 and abs(column) < 2:
                    continue
                x = column * 7.4 + math.sin(row * 2.3 + column) * 1.7
                y = row * 7.1 + math.cos(column * 1.7 - row) * 1.4
                species = (row * 7 + column * 11) % len(families)
                family = families[species]
                prototype = prototypes.get(family)
                if prototype is None:
                    prototype = next(iter(prototypes.values()))
                instance = prototype.instanceTo(self.render)
                instance.show()
                instance.setPos(x, y, height_at(x, y))
                instance.setH((row * 31 + column * 17) % 360)
                scale = 0.82 + ((row * 13 + column * 5) % 7) * 0.075
                instance.setScale(scale)

    def _load_player_model(self) -> None:
        model_path = ROOT / "assets" / "character" / "field_explorer.glb"
        if model_path.is_file():
            model = self.loader.loadModel(str(model_path))
            if not model.isEmpty():
                model.reparentTo(self.render)
                model.setPos(0, 0, height_at(0, 0))
                model.setScale(1.0)
                self.player_model = model
                return
        print("ASSET_NOTICE: explorer GLB not found; no substitute primitive spawned")

    def _update(self, task):
        return task.cont


if __name__ == "__main__":
    WildlandsApp().run()
