# LAST MAGAZINE

A first-person survival horror shooter made in Godot 4.7 by Taha Keler.
You're stuck in a dark stone labyrinth, the zombies keep coming, and there's
never enough ammo. Survive until the extraction clock runs out.

## Open and play
1. Open Godot 4.7 and import this folder (it contains `project.godot`).
2. Press Play (F5).

## Controls
WASD move · mouse / trackpad look · left click fire · R reload · 1 2 3 weapons ·
Shift sprint · Ctrl or C crouch · Space jump · F torch · V melee · G decoy ·
hold E interact · Enter restart · Esc pause

## What's in here
- `project.godot`: the project
- `src/`: all game scripts and scenes
- `assets/`: models, zombies, audio, materials, and one licence file per third-party source
- `amethyst_labyrinth/`: the map
- `systems/`: lighting budget used by the map

Credits and licences for every asset are in `CREDITS.md` and on the in-game Credits screen.

## Checks (for the report)
The feature checks from the report can be re-run from this folder:

    Godot --headless --path . --script tools/check_ammo_health.gd
    Godot --path . --script tools/check_headshots.gd

`tools/check.sh` runs the full automated test suite.
