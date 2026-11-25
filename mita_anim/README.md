# Mita Animation Lab

Реалистичные анимации (mocap CMU, перенесённый на скелет) и физика плаща и физика плаща для персонажа из `assets/mita_rig.glb`. Godot 4.3, Android.

Управление: левая половина экрана это джойстик (маленький наклон ходьба, полный бег, кнопка «Ускорение» спринт), правая половина вращает камеру, кнопки: прыжок, кувырок, удар кулаком, удар ногой с разворота; переключатели плаща и ветра.

Сборка APK: GitHub Actions (`.github/workflows/mita-anim-apk.yml` в корне репозитория) собирает debug-APK и публикует его в Releases.

Подробности и принятые решения: `docs/ARCHITECTURE.md`.
Подготовка модели заново: `python3 tools/prepare_model.py исходник.glb assets` (нужны numpy, scipy, Pillow).
Пересборка клипов: `python3 tools/export_clips.py` (нужен `kira_rigged.glb`), кулак: `python3 tools/prepare_fist.py`.
