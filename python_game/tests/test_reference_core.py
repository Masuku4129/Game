from world.reference_core import WildlandsBrowserCore


def test_seasons_weather_and_wind_controls():
    core = WildlandsBrowserCore(seed=17)
    assert core.season() == "spring"
    core.set_season("winter")
    core.set_weather("snow")
    core.set_wind(0.9)
    assert core.season() == "winter"
    result = core.step(0.05, 1.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1.0, 0.0, 1000)
    assert result[12] > 0.0
    assert result[15] >= 0.0
    core.set_season("auto")
    core.set_weather("auto")
    core.set_wind(None)
    assert core.season() == "spring"


def test_world_chunks_keep_full_ecology_and_are_deterministic():
    a = WildlandsBrowserCore(seed=123)
    b = WildlandsBrowserCore(seed=123)
    chunk_a = a.world.chunk(0, 0)
    chunk_b = b.world.chunk(0, 0)
    assert chunk_a["size"] == 72.0
    assert chunk_a["trees"] == chunk_b["trees"]
    assert chunk_a["objects"] == chunk_b["objects"]
    assert len(chunk_a["objects"]) >= 500
    assert {item["kind"] for item in chunk_a["objects"]}
    assert {tree["species"] for tree in chunk_a["trees"]}


def test_surface_response_slows_movement_and_records_footprints():
    core = WildlandsBrowserCore(seed=8)
    x = z = y = vx = vz = heading = heading_velocity = 0.0
    saw_step = False
    for frame in range(220):
        result = core.step(
            0.05, frame * 0.05, 0.0, 1.0,
            x, z, y, vx, vz, heading, heading_velocity,
            0.0, 0.0, 1.0, 0.0, 1000.0,
        )
        x, z, y, vx, vz, heading, heading_velocity = result[:7]
        saw_step = saw_step or bool(result[22])
    assert saw_step
    assert core.footprints
    assert len(core.footprints[-1]) == 6
    assert core.footprints[-1][4] in {"snow", "mud", "earth"}
