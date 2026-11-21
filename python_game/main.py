from __future__ import annotations

import math
import os

from direct.actor.Actor import Actor
from direct.gui.DirectGui import DirectFrame
from direct.gui import DirectGuiGlobals as DGG
from direct.showbase.ShowBase import ShowBase
import simplepbr
from panda3d.core import (
    AmbientLight, DirectionalLight, Fog, Geom, GeomNode, GeomTriangles,
    GeomVertexData, GeomVertexFormat, GeomVertexWriter, NodePath,
    PNMImage, Texture, TransparencyAttrib, Vec3, Vec4, WindowProperties,
    ClockObject, loadPrcFileData,
)

from world.reference_core import WildlandsBrowserCore
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
        dt = min(ClockObject.getGlobalClock().getDt(), 0.05)
        self.simulation_time += dt
        position = self.player_model.getPos(self.render)
        ground_height, terrain_slope, _moisture, _canopy, _biome, snow_factor, mud_factor = (
            self.simulation.world_sample(position.x, position.y)
        )
        state = self.simulation.step(
            dt,
            self.simulation_time,
            self.joystick.value_x,
            self.joystick.value_y,
            position.x,
            position.y,
            position.z,
            self.player_velocity.x,
            self.player_velocity.y,
            self.simulation_heading,
            self.simulation_heading_velocity,
            ground_height,
            terrain_slope,
            snow_factor,
            mud_factor,
            100000.0,
        )
        (
            world_x, world_y, world_height, velocity_x, velocity_y,
            self.simulation_heading, self.simulation_heading_velocity,
            speed, snow_depth, mud_depth, cloud, rain, snow, fog_density,
            storm, wind, wind_x, wind_y, wetness, snow_cover, puddles,
            walk_phase, step_event, foot_x, foot_y, season_index,
            leaf_fall, canopy_snow, elapsed,
        ) = state
        position.set(world_x, world_y, world_height)
        self.player_model.setPos(self.render, position)
        self.player_velocity.set(velocity_x, velocity_y, 0.0)

        if speed > 0.12:
            self.player_model.setH(-math.degrees(self.simulation_heading) + MODEL_FORWARD_OFFSET)
            state_name = "run" if speed > PLAYER_SPEED * 0.72 else "walk"
            self._set_animation(state_name)
            clip = self.animation_clips.get(state_name)
            if clip is not None:
                nominal_speed = PLAYER_SPEED if state_name == "run" else PLAYER_SPEED * 0.48
                self.player_model.setPlayRate(max(0.65, min(1.35, speed / nominal_speed)), clip)
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
    if os.environ.get("WILDLANDS_HEADLESS") == "1":
        loadPrcFileData("wildlands-headless", "window-type offscreen\naudio-library-name null\nwin-size 1280 720\nsync-video false")
    app = WildlandsApp()
    if os.environ.get("WILDLANDS_HEADLESS") == "1":
        app.taskMgr.doMethodLater(8.0, lambda task: (app.userExit(), task.done)[1], "headless-smoke-exit")
    app.run()
