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
| [Modular Cave Kit](https://kenney.nl/assets/modular-cave-kit) | 1.0 | CC0 1.0 | The entire play space — central chamber, corridors, side rooms, and the rock formations used as cover |
| [Blaster Kit](https://kenney.nl/assets/blaster-kit) | 2.1 | CC0 1.0 | The player's weapon viewmodel (`blaster-a`) and the weapon cases used as floor dressing |
| [RPG Audio](https://kenney.nl/assets/rpg-audio) | 1.0 | CC0 1.0 | All sound effects — firing, dry-fire, reload, impacts, zombie groans, footsteps, round results |
| [Animated Characters: Survivors](https://kenney.nl/assets/animated-characters-survivors) | 1.0 | CC0 1.0 | Licence retained for reference; see note below |

Each pack's original `License.txt` is preserved verbatim under
`assets/licenses/`.

### Note on the Survivors pack

The Animated Characters: Survivors pack ships **FBX only**. Godot 4 cannot
import FBX without an external `FBX2glTF` converter, which would make the
project depend on a binary that does not travel with it — and the submission
has to open and run from the ZIP alone. The zombies therefore use original
primitive-built models rather than this pack. Its licence is retained above
because the pack was downloaded and evaluated.

### Note on the firing sound

The RPG Audio pack contains no firearm sound. The weapon's firing sound is a
percussive clip from that pack (`chop.ogg`) pitched well down. It reads as a
shot in context, but it is the one audio event without a purpose-made source.

## Self-Created Content

- All GDScript source code in `src/`
- All scene files (`.tscn`), the UI theme, and the arena layout
- Zombie models, built from primitive meshes
- All lighting, materials, and environment setup
- Project icon (`icon.svg`)

## AI Contribution

Portions of this project's scenes and scripts were developed with
[Claude Code](https://claude.com/claude-code) acting as an AI assistant. The
specific files and features it authored are identified in
[`docs/ai-contribution.md`](docs/ai-contribution.md).
