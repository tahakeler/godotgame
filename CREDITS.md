# Credits and Asset Licences

**LAST MAGAZINE** — first-person arena survival shooter built in Godot 4.7.

## Engine

- [Godot Engine](https://godotengine.org/) 4.7.2 — MIT Licence

## Project Template

This project is built on the
[Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios)
template by Donchitos — MIT Licence.

## External Assets

All external art and audio in this project comes from **Kenney**
([kenney.nl](https://kenney.nl/assets)) and is released under
**Creative Commons CC0 1.0 Universal** (public domain dedication).

CC0 requires no attribution, but Kenney is credited here regardless — and
supporting the work is encouraged at [kenney.nl](https://kenney.nl/).

| Pack | Version | Licence | Used for |
|------|---------|---------|----------|
| [Modular Cave Kit](https://kenney.nl/assets/modular-cave-kit) | 1.0 | CC0 1.0 | The original procedural cave generator. Kept in the project; the shipped map is the Amethyst Labyrinth, modelled in Blender for this game |
| [Blaster Kit](https://kenney.nl/assets/blaster-kit) | 2.1 | CC0 1.0 | The player's weapon viewmodel (`blaster-a`) and the weapon cases used as floor dressing |
| [RPG Audio](https://kenney.nl/assets/rpg-audio) | 1.0 | CC0 1.0 | All sound effects — firing, dry-fire, reload, impacts, zombie groans, footsteps, round results |
| [Animated Characters: Survivors](https://kenney.nl/assets/animated-characters-survivors) | 1.0 | CC0 1.0 | The zombies — rigged character mesh, zombie skins, and the idle/run animations |

### Sourced horror audio (OpenGameArt, CC0)

The dread system's music beds, phantom one-shots and stingers are CC0 works by the authors below, downloaded from OpenGameArt. Each page's licence is recorded under `assets/licenses/oga-*.txt`.

| Title | Author | Source URL | Licence | Used for |
|-------|--------|------------|---------|----------|
| Ancient Caverns | congusbongus | https://opengameart.org/content/ancient-caverns-horror-ambient-loop | CC0 1.0 | Exploration drone bed (`music/ancient_caverns_drone_loop.ogg`) |
| Dark Cavern Ambient | Paul Wortmann | https://opengameart.org/content/dark-cavern-ambient | CC0 1.0 | Second exploration bed (`music/dark_cavern_ambient_loop.ogg`) |
| A Lurking Evil | congusbongus | https://opengameart.org/content/a-lurking-evil-horror-ambience | CC0 1.0 | Tense bed (`music/lurking_evil_tense_loop.ogg`) |
| Cave In | StarNinjas | https://opengameart.org/content/cave-in | CC0 1.0 | Phantom distant rock fall |
| Heartbeat Sounds | bart | https://opengameart.org/content/heartbeat-sounds | CC0 1.0 | Phantom heartbeat |
| Female High Pitched Scream SFX | WuxiaScrub | https://opengameart.org/content/female-high-pitched-scream-sfx | CC0 1.0 | Phantom distant scream |
| Wolf Monster Sound | CaveboyTup | https://opengameart.org/content/wolf-monster-sound | CC0 1.0 | Phantom distant howl |
| Metal Impact Sounds | BMacZero | https://opengameart.org/content/metal-impact-sounds | CC0 1.0 | Phantom distant metal clang |
| Footsteps | GboxMikeFozzy | https://opengameart.org/content/footsteps-0 | CC0 1.0 | Phantom footsteps (4 variants) |
| Dark Stinger 1 | Kresiek The Furry | https://opengameart.org/content/dark-stinger-1 | CC0 1.0 | Horror stinger |
| Horror Breathing | primbal | https://opengameart.org/content/horror-breathing | CC0 1.0 | A breath at your shoulder, once a round |
| Water Drops | ceoxblackj | https://opengameart.org/content/water-drops | CC0 1.0 | Water dripping somewhere in the cave |
| Breaking Rock | themightyglider | https://opengameart.org/content/breaking-rock | CC0 1.0 | Small rocks breaking in the dark |
| Moving Boulder | themightyglider | https://opengameart.org/content/moving-boulder | CC0 1.0 | A stone dropping somewhere unseen |
| Horror Hit Soundpack 1 | psychhead | https://opengameart.org/content/horror-hit-soundpack-1 | CC0 1.0 | Low hits (two clips, trimmed to 2.8 s) |
| Undead Moans | antumdeluge | https://opengameart.org/content/undead-moans | CC0 1.0 | A distant moan |
| Ghost/Monster Voice | qubodup | https://opengameart.org/content/ghost-monster-voice-moaning-growling | CC0 1.0 | A distant, inhuman moan |

Each pack's original `License.txt` is preserved verbatim under
`assets/licenses/`.

### Note on the Survivors pack

This pack ships **FBX only**, which historically required the external
`FBX2glTF` converter. Godot 4.7 imports it directly with its built-in `ufbx`
importer, so no external tool is needed and the project runs from the ZIP
alone.

The pack separates the rigged mesh from its animations — one file per clip,
all sharing the same 58-bone skeleton. `src/gameplay/zombie/zombie_visual.gd`
merges them at runtime into a single AnimationPlayer.

### Note on the firing sound

The RPG Audio pack contains no firearm, and nothing low enough to mark a
Brute. Those two sounds are synthesised instead by `tools/generate_audio.gd`
and live in `assets/audio/generated/`. They are original content, so no
third-party licence applies to them.

## Self-Created Content

- All GDScript source code in `src/`
- The Amethyst Labyrinth map (`amethyst_labyrinth/`), modelled in Blender for this game
- All scene files (`.tscn`) and the UI theme
- The gunshot and Brute growl, synthesised by `tools/generate_audio.gd`
- All lighting, materials, and environment setup
- Project icon (`icon.svg`)

## AI Contribution

Portions of this project's scenes and scripts were developed with
[Claude Code](https://claude.com/claude-code) acting as an AI assistant. The
specific files and features it authored are identified in
[`docs/ai-contribution.md`](docs/ai-contribution.md).
