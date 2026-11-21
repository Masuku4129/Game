from __future__ import annotations

import math

from direct.actor.Actor import Actor
from direct.gui.DirectGui import DirectFrame
from direct.gui import DirectGuiGlobals as DGG
from direct.showbase.ShowBase import ShowBase
from panda3d.core import (
    AmbientLight, DirectionalLight, Fog, Geom, GeomNode, GeomTriangles,
    GeomVertexData, GeomVertexFormat, GeomVertexWriter, NodePath,
    PNMImage, Texture, TransparencyAttrib, Vec3, Vec4, WindowProperties,
    globalClock,
)

from world.movement import camera_relative_direction, heading_for_direction
from world.terrain import height_at

SEASON = "summer"
PLAYER_SPEED = 5.2
PLAYER_ACCELERATION = 18.0
PLAYER_DECELERATION = 24.0
CAMERA_OFFSET = Vec3(5.5, -13.0, 24.0)
MODEL_FORWARD_OFFSET = 0.0


def _circle_texture(name: str, edge_alpha: float, fill_alpha: float) -> Texture:
    image = PNMImage(128, 128, 4)
    for y in range(128):
        for x in range(128):
            dx = (x + 0.5 - 64.0) / 64.0
            dy = (y + 0.5 - 64.0) / 64.0
            distance = math.sqrt(dx * dx + dy * dy)
            if distance > 1.0:
                alpha = 0.0
            elif distance > 0.88:
                alpha = edge_alpha
            else:
                alpha = fill_alpha
            image.setXelA(x, y, 0.92, 0.96, 1.0, alpha)
    texture = Texture(name)
    texture.load(image)
    return texture


class VirtualJoystick:
    """Single-pointer touch joystick; Android touch is delivered as mouse1."""

    def __init__(self, app: ShowBase) -> None:
        self.app = app
        self.center_x = -1.0
        self.center_y = -0.68
        self.radius = 0.23
        self.value_x = 0.0
        self.value_y = 0.0
        self.active = False
        self.base_texture = _circle_texture("joystick-base", 0.72, 0.14)
        self.knob_texture = _circle_texture("joystick-knob", 0.92, 0.55)

        self.base = DirectFrame(
            parent=app.aspect2d,
            frameTexture=self.base_texture,
            frameColor=(1, 1, 1, 0.64),
            frameSize=(-self.radius, self.radius, -self.radius, self.radius),
            relief=DGG.FLAT,
            sortOrder=50,
        )
        self.base.setPos(self.center_x, 0, self.center_y)
        knob_radius = self.radius * 0.40
        self.knob = DirectFrame(
            parent=app.aspect2d,
            frameTexture=self.knob_texture,
            frameColor=(1, 1, 1, 0.82),
            frameSize=(-knob_radius, knob_radius, -knob_radius, knob_radius),
            relief=DGG.FLAT,
            sortOrder=51,
        )
        self.knob.setPos(self.center_x, 0, self.center_y)
        self.base.setTransparency(TransparencyAttrib.MAlpha)
        self.knob.setTransparency(TransparencyAttrib.MAlpha)

        app.accept("mouse1", self._on_down)
        app.accept("mouse1-up", self._on_up)
        app.taskMgr.add(self._update, "virtual-joystick-update")

    def _pointer(self) -> tuple[float, float] | None:
        watcher = self.app.mouseWatcherNode
        if not watcher.hasMouse():
            return None
        aspect = self.app.win.getXSize() / max(1, self.app.win.getYSize())
        return watcher.getMouseX() * aspect, watcher.getMouseY()

    def _on_down(self) -> None:
        pointer = self._pointer()
        if pointer is None:
            return
        x, y = pointer
        if math.hypot(x - self.center_x, y - self.center_y) > self.radius * 1.45:
            return
        self.active = True
        self._set_from_pointer(x, y)

    def _on_up(self) -> None:
        self.active = False
        self.value_x = 0.0
        self.value_y = 0.0
        self.knob.setPos(self.center_x, 0, self.center_y)

    def _set_from_pointer(self, x: float, y: float) -> None:
        dx = (x - self.center_x) / self.radius
        dy = (y - self.center_y) / self.radius
        length = math.hypot(dx, dy)
        if length > 1.0:
            dx /= length
            dy /= length
        deadzone = 0.075
        if math.hypot(dx, dy) < deadzone:
            dx = dy = 0.0
        self.value_x = dx
        self.value_y = dy
        knob_range = self.radius * 0.55
        self.knob.setPos(
            self.center_x + dx * knob_range,
            0,
            self.center_y + dy * knob_range,
        )

    def _update(self, task):
        if self.active:
            pointer = self._pointer()
            if pointer is not None:
                self._set_from_pointer(*pointer)
        return task.cont


def build_terrain(parent: NodePath, ground_texture: Texture, extent: float = 90.0, cells: int = 96) -> NodePath:
    fmt = GeomVertexFormat.getV3n3c4t2()
    data = GeomVertexData("terrain", fmt, Geom.UHStatic)
    data.setNumRows((cells + 1) ** 2)
    vertex = GeomVertexWriter(data, "vertex")
    normal = GeomVertexWriter(data, "normal")
    color = GeomVertexWriter(data, "color")
    texcoord = GeomVertexWriter(data, "texcoord")
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
            color.addData4(shade, shade, shade, 1.0)
            texcoord.addData2(x * 0.16, y * 0.16)

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
    terrain.setTexture(ground_texture, 1)
    return terrain


class WildlandsApp(ShowBase):
    def __init__(self) -> None:
        super().__init__()
        props = WindowProperties()
        props.setTitle("Wildlands")
        props.setSize(1280, 720)
        props.setFullscreen(True)
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

        ground_texture = self.loader.loadTexture("assets/textures/ground_albedo.png")
        if ground_texture is None:
            raise RuntimeError("Required generated ground texture could not be loaded")
        build_terrain(self.render, ground_texture)
        self._build_forest()
        self._load_player_model()
        self.player_velocity = Vec3(0, 0, 0)
        self.joystick = VirtualJoystick(self)
        self.camera.setPos(CAMERA_OFFSET)
        self.camera.lookAt(0, 0, height_at(0, 0) + 0.8)
        self.taskMgr.add(self._update, "game-update")

    def _build_forest(self) -> None:
        forest = self.loader.loadModel(f"assets/generated/forest_{SEASON}.bam")
        if forest.isEmpty():
            raise RuntimeError(f"Required baked forest scene is missing for season: {SEASON}")
        forest.reparentTo(self.render)

    def _load_player_model(self) -> None:
        model = self.loader.loadModel("assets/character/field_explorer.glb")
        if model.isEmpty():
            raise RuntimeError("Required authored explorer GLB could not be loaded")
        actor = Actor(model)
        actor.reparentTo(self.render)
        actor.setPos(0, 0, height_at(0, 0))
        actor.setScale(1.0)
        self.player_model = actor
        clips = actor.getAnimNames()
        self.animation_clips = {
            "idle": next((clip for clip in clips if "idle" in clip.lower()), None),
            "walk": next((clip for clip in clips if "walk" in clip.lower()), None),
            "run": next((clip for clip in clips if "run" in clip.lower()), None),
        }
        self.current_animation = None
        self._set_animation("idle")
        print(f"PLAYER_MODEL_LOADED: clips={clips}")

    def _set_animation(self, state: str) -> None:
        clip = self.animation_clips.get(state)
        if clip is None or clip == self.current_animation:
            return
        if self.current_animation is not None:
            self.player_model.stop(self.current_animation)
        self.player_model.loop(clip)
        self.current_animation = clip

    def _update(self, task):
        dt = min(globalClock.getDt(), 0.05)
        input_x = self.joystick.value_x
        input_y = self.joystick.value_y
        camera_heading = math.radians(self.camera.getH())
        direction_x, direction_y = camera_relative_direction(
            input_x, input_y, camera_heading
        )
        moving = math.hypot(direction_x, direction_y) > 0.01
        target_speed = PLAYER_SPEED if moving else 0.0
        target_x = direction_x * target_speed
        target_y = direction_y * target_speed
        rate = PLAYER_ACCELERATION if moving else PLAYER_DECELERATION
        blend = 1.0 - math.exp(-rate * dt)
        self.player_velocity.x += (target_x - self.player_velocity.x) * blend
        self.player_velocity.y += (target_y - self.player_velocity.y) * blend

        position = self.player_model.getPos(self.render)
        position.x += self.player_velocity.x * dt
        position.y += self.player_velocity.y * dt
        position.z = height_at(position.x, position.y)
        self.player_model.setPos(self.render, position)

        speed = math.hypot(self.player_velocity.x, self.player_velocity.y)
        if speed > 0.12:
            heading = heading_for_direction(
                self.player_velocity.x, self.player_velocity.y
            )
            self.player_model.setH(heading + MODEL_FORWARD_OFFSET)
            self._set_animation("run" if speed > PLAYER_SPEED * 0.72 else "walk")
        else:
            self._set_animation("idle")

        target_camera = position + CAMERA_OFFSET
        camera_blend = 1.0 - math.exp(-5.0 * dt)
        current_camera = self.camera.getPos(self.render)
        self.camera.setPos(
            self.render,
            current_camera + (target_camera - current_camera) * camera_blend,
        )
        self.camera.lookAt(position + Vec3(0, 0, 0.8))
        return task.cont


if __name__ == "__main__":
    WildlandsApp().run()
