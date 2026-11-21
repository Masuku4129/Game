# Wildlands

Мобильная 3D-игра о выживании в природной среде Дальнего Востока.

## Проект

- Главный документ требований: [PROJECT_MASTER.md](PROJECT_MASTER.md)
- Структура legacy-проекта: [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)
- План миграции: [docs/PYTHON_ENGINE_PORT.md](docs/PYTHON_ENGINE_PORT.md)
- Текущий legacy runtime: Godot 4.7.2 (сохранён, не удаляется)
- Новый экспериментальный runtime: Python 3.13 + Panda3D 1.11 в `python_game/`
- Целевая платформа: Android ARM64 / APK
- Автоматическая сборка: GitHub Actions

## Получение APK

- Legacy Godot APK собирается workflow **Android APK** из основной ветки.
- Python/Panda3D APK собирается workflow **Python Android APK** из ветки `python-panda3d-port`.
- Для Python-порта workflow сначала тестирует код, затем собирает AAB и преобразует его в подписанный universal APK.
- APK считается готовым только после успешного завершения workflow, появления артефакта и проверки архива.

## Статус

Миграция на Python/Panda3D экспериментальная. Godot-проект сохраняется до подтверждения Android-сборки и проверки нового runtime на физическом телефоне. Наличие исходников, тестов или AAB само по себе не подтверждает корректную работу APK на устройстве.
