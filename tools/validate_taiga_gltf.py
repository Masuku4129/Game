#!/usr/bin/env python3
"""Validate self-contained glTF 2.0 files in game/models/nature."""
import base64
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1] / "game" / "models" / "nature"
files = sorted(ROOT.glob("*.gltf"))
if not files:
    raise SystemExit("FAIL: no glTF files found")
errors = []
for path in files:
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
        assert doc.get("asset", {}).get("version") == "2.0", "not glTF 2.0"
        assert doc.get("meshes"), "no meshes"
        assert doc.get("materials"), "no materials"
        assert doc.get("accessors"), "no accessors"
        assert doc.get("buffers"), "no buffers"
        uri = doc["buffers"][0]["uri"]
        prefix = "data:application/octet-stream;base64,"
        assert uri.startswith(prefix), "buffer is not embedded"
        raw = base64.b64decode(uri[len(prefix):], validate=True)
        assert len(raw) == doc["buffers"][0]["byteLength"], "buffer byteLength mismatch"
        for accessor in doc["accessors"]:
            assert accessor["count"] > 0, "empty accessor"
        attrs = doc["meshes"][0]["primitives"][0]["attributes"]
        assert all(k in attrs for k in ("POSITION", "NORMAL", "COLOR_0")), "missing position/normal/color"
        print(f"PASS {path.name}: {len(doc['accessors'])} accessors, {len(raw)} buffer bytes")
    except Exception as exc:
        errors.append(f"{path.name}: {exc}")
if errors:
    print("\n".join("FAIL " + e for e in errors))
    raise SystemExit(1)
print(f"\nPASS: {len(files)} glTF assets validated")
