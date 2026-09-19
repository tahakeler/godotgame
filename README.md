# LAST MAGAZINE

A first-person arena survival shooter built in **Godot 4.7**.

> Trapped in an arena until extraction, you count every bullet — and every
> zombie you put down drags the rescue clock closer, so the fastest way out is
> straight through them.

---

## The idea

Killing shortens the round. Ammunition only comes from killing. Those two rules
pull against each other, and between them they remove both easy strategies:

- **Hiding** is safe moment-to-moment, but it leaves the clock running while
  zombie pressure keeps climbing.
- **Spraying** clears the room, but an empty magazine with a zombie three metres
  away is how the round ends.

## How to run

1. Open the project folder in Godot 4.7 (or later 4.x).
2. Press **F5**, or run the `LAST MAGAZINE` project from the project manager.

The entry scene is `src/ui/main_menu.tscn`.

## Controls

| Action | Binding |
|--------|---------|
| Move | `W` `A` `S` `D` |
| Look | Mouse |
| Fire | Left mouse button |
| Reload | `R` |
| Jump | `Space` |
| Restart round | `Enter` |
| Pause / settings | `Esc` |

## Win and loss

- **Win** — the extraction timer reaches `00:00` while you are alive.
- **Lose** — your health reaches zero.
- **Restart** — `Enter` at any time restores the player, weapon, clock, kill
  count, and clears every zombie.

Each kill removes 2 seconds from the extraction clock and awards 3 reserve
rounds.

## Features

**Player Health** — zombie contact reduces health; the bar drops, the screen
flashes, and an arc marker shows the direction the hit came from. Zero health
ends the round. A short invulnerability window after each hit stops a crowd
from deleting the whole bar at once.

**Ammunition and Reload** — firing spends one round from the magazine. An empty
magazine blocks the shot and reports why. Reloading moves rounds from reserve
to magazine; with an empty reserve it is refused.

**Settings** — mouse sensitivity, invert look, master volume, fullscreen, and
difficulty, saved between sessions. Difficulty is not cosmetic: it changes
extraction length, starting ammunition, spawn rate, and the damage you take.

| Difficulty | Extraction | Spare rounds | Damage taken | Spawn rate |
|------------|-----------|--------------|--------------|------------|
| Recruit | 100s | 32 | 65% | 71% |
| Soldier | 120s | 24 | 100% | 100% |
| Veteran | 145s | 16 | 140% | 147% |

## Project layout

```
project.godot              Godot project configuration
assets/
  models/cave/             Kenney Modular Cave Kit (CC0)
  models/weapons/          Kenney Blaster Kit (CC0)
  audio/                   Kenney RPG Audio (CC0)
  licenses/                Original licence files for each pack
src/
  arena/                   Cave layout assembly, collision, navmesh bake
  audio/                   Sound bank and event routing
  core/                    Game loop, round state, settings autoload
  gameplay/
    health.gd              Shared health component (player and zombies)
    player/                First-person controller
    weapon/                Weapon, ammunition, reload
    zombie/                Zombie AI and spawner
  ui/                      HUD, main menu, pause menu, settings, theme
tests/                     Automated checks and assignment test evidence
tools/check.sh             Pre-merge verification gate
design/gdd/                Game concept document
docs/                      Test evidence and AI contribution notes
```

## Verifying the build

```bash
./tools/check.sh
```

Runs import, arena generation, zombie navigation, game loop, feature tests, and
a headless boot. It fails on engine errors — Godot exits `0` even when scripts
throw, so the check greps log text rather than trusting exit codes.

## Documentation

- [Game concept](design/gdd/game-concept.md) — pillars, loop, scope
- [Test evidence](docs/test-evidence.md) — expected vs actual for all checks
- [AI contribution](docs/ai-contribution.md) — what the assistant wrote
- [Credits](CREDITS.md) — asset licences

## Assets

Art and audio come from **Kenney** ([kenney.nl](https://kenney.nl/assets)),
released under **CC0 1.0** (public domain):

- **Modular Cave Kit** — the cave complex and rock cover
- **Blaster Kit** — the weapon viewmodel and floor props
- **RPG Audio** — all sound effects

CC0 requires no attribution, but Kenney is credited anyway. Each pack's
original licence file is preserved under `assets/licenses/`.

All code, scenes, lighting, the UI theme, the arena layout, and the zombie
models are original to this project. Full details in [CREDITS.md](CREDITS.md).

## Licence

MIT — see [LICENSE](LICENSE).
