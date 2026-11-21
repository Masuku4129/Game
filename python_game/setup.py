from setuptools import setup

PRC_DATA = """
load-display pandagles2
aux-display pandagles
window-title Wildlands
sync-video true
show-frame-rate-meter false
"""

setup(
    name="wildlands",
    version="0.1.0",
    options={
        "build_apps": {
            "application_id": "org.kira.wildlands",
            "android_version_code": 1,
            "android_min_sdk_version": 24,
            "android_target_sdk_version": 36,
            "android_abis": ["arm64-v8a"],
            "platforms": ["android"],
            "gui_apps": {"wildlands": "main.py"},
            "plugins": ["pandagles2", "pandagles"],
            "requirements_path": "requirements.txt",
            "use_optimized_wheels": False,
            "include_patterns": [
                "**/*.glb",
                "**/*.gltf",
                "**/*.png",
                "**/*.jpg",
                "**/*.jpeg",
                "**/*.ogg",
                "**/*.wav",
            ],
            "extra_prc_data": PRC_DATA,
        },
    },
)
