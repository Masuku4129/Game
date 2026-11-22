#!/bin/bash
# Упрощает тяжёлые модели Poly Haven под телефон (gltfpack) и удаляет оригиналы.
set -u
cd "$(dirname "$0")/../game/assets/ph"
declare -A R=( [fir_sapling_medium]=0.02 [pine_sapling_medium]=0.005 [rock_moss_set_01]=0.12 [boulder_01]=0.08 [tree_stump_01]=0.12 [dead_tree_trunk]=0.06 [shrub_02]=0.4 )
for id in "${!R[@]}"; do
  [ -f "$id/$id.gltf" ] || continue
  npx -y gltfpack@0.21.0 -i "$id/$id.gltf" -o "$id/${id}_lo.gltf" -si "${R[$id]}" -noq -kn -km 2>&1 | tail -1
  rm -f "$id/$id.gltf" "$id/$id.bin"
  python3 -c "import json,sys;j=json.load(open('$id/${id}_lo.gltf'));print('$id', sum(j['accessors'][p['indices']]['count']//3 for m in j['meshes'] for p in m['primitives']),'tris')"
done
for id in fern_02 grass_medium_01 grass_medium_02; do [ -f "$id/$id.gltf" ] && mv "$id/$id.gltf" "$id/${id}_lo.gltf"; done
du -sh .
