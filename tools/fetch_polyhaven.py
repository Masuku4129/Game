"""Скачивает CC0-ассеты Poly Haven в game/assets/ph/. Запускается в GitHub Actions.
Использование: python fetch_polyhaven.py catalog | python fetch_polyhaven.py get id1 id2 ..."""
import json, os, sys, urllib.request
API = "https://api.polyhaven.com"
UA = {"User-Agent": "taiga-game-asset-fetch"}
def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
def jget(url):
    return json.loads(get(url))
root = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "ph")
if sys.argv[1] == "catalog":
    out = {}
    for t in ("models", "textures"):
        a = jget(f"{API}/assets?t={t}")
        out[t] = {k: {"name": v["name"], "cat": v.get("categories", []), "tags": v.get("tags", [])} for k, v in a.items()}
    os.makedirs("tools", exist_ok=True)
    json.dump(out, open("tools/polyhaven_catalog.json", "w"), ensure_ascii=False, indent=0)
else:
    for aid in sys.argv[2:]:
        files = jget(f"{API}/files/{aid}")
        d = os.path.join(root, aid); os.makedirs(d, exist_ok=True)
        if "gltf" in files:
            g = files["gltf"]["1k"]["gltf"]
            open(os.path.join(d, aid + ".gltf"), "wb").write(get(g["url"]))
            for rel, inc in g.get("include", {}).items():
                p = os.path.join(d, rel); os.makedirs(os.path.dirname(p), exist_ok=True)
                open(p, "wb").write(get(inc["url"]))
        else:
            for m in ("Diffuse", "nor_gl", "Rough", "AO", "Displacement"):
                if m in files and "1k" in files[m]:
                    f = files[m]["1k"].get("jpg") or files[m]["1k"].get("png")
                    open(os.path.join(d, f"{aid}_{m.lower()}." + f["url"].rsplit(".", 1)[1]), "wb").write(get(f["url"]))
        if "gltf" in files:
            j = json.load(open(os.path.join(d, aid + ".gltf")))
            tris = sum(j["accessors"][pr["indices"]]["count"] // 3 for m in j["meshes"] for pr in m["primitives"] if "indices" in pr)
            print("ok", aid, "meshes", len(j["meshes"]), "nodes", [n.get("name") for n in j["nodes"]][:12], "tris", tris)
        else:
            print("ok", aid, os.listdir(d))
