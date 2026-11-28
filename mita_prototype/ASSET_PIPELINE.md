# Mita Prototype — character-first setup

## Scope
Only the first playable sandbox: a ground plane, fixed 45° orthographic camera, Mita character, Idle/Walk/Run and mobile joystick. No narrative or unrelated systems.

## Asset policy
- No paid generation accounts, API keys, credits, or registration-dependent workflows.
- Do not call a generated image a 3D model.
- Do not present primitive-built character geometry as the final Mita model.
- Final Mita requires a full stylized character mesh with distinctive face, layered long black hair with cool violet/blue highlights, black oversized hoodie, trousers and footwear; a usable skeleton and actual animation clips.
- Free rigged animation sources are only a motion/reference base; they do not count as Mita until her appearance is recreated and the model is integrated.

## Free animation source
Vinish.Dev publishes a free GLB pack with female/male 65-bone humanoid rigs and 36 clips, including Idle, Walk and Run. License: CC BY 4.0; credit must be included in the game's credits. No login.
Source: https://vinish.dev/free-3d-models/character-animations
Archive URL: https://models.vinish.dev/animations/animations.zip

Run `scripts/get_free_animation_pack.sh` in a shell with curl and unzip. It validates the ZIP before extraction. Network access is required for downloading; downloads could not be performed in this execution environment.

## Open character creation route
Ara 3D Gen is MIT-licensed, self-hostable and account-free. It offers rigging, customizable body/face/hair/clothes, and exports GLB/FBX/OBJ. It is an asset authoring tool—not a completed Mita model. Source: https://github.com/TuriaArt/3d-gen-TU

## Current prototype state
- Godot project is stored under `mita_prototype/`.
- Touch drag event handling was corrected in `main.gd`.
- Procedural mesh Mita remains a temporary placeholder and does NOT meet final character quality.
- The proper rigged, textured Mita asset and animation integration remain pending; this is not claimed complete.
