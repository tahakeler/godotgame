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

| Action | Keyboard / mouse | Gamepad |
|--------|------------------|---------|
| Move | `W` `A` `S` `D` | Left stick |
| Look | Mouse, or arrow keys | Right stick |
| Fire | Left mouse button | Right trigger |
| Reload | `R` | X / Square |
| Jump | `Space` | A / Cross |
| Restart round | `Enter` | Y / Triangle |
| Pause / settings | `Esc` | Start |

Every menu is fully navigable on a gamepad. The magazine reloads itself when it
runs empty; the reload control is for topping up a partial magazine, which is a
decision worth making.

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

**Modes** — *Extraction* (kills shorten the rescue clock), *Last Stand* (a fixed
five minutes that kills do not shorten), and *Endless* (no clock and no win —
pressure keeps climbing until it finishes you). Each keeps its own personal
best per difficulty.

**Progression** — kills award experience, and each level offers a choice of
three upgrades: magazine size, vitality, damage, reload speed, movement,
scavenging and reserve capacity. Upgrades last the round and are stripped back
on restart, so no run inherits the last one's advantages.

**The cave** — fourteen chambers on four rings, assembled from a modular kit at
runtime, with raised decks and ramps for ground worth holding. Zombies arrive
from twelve chambers, weighted to appear behind you rather than in plain view.

**Enemy types** — Shamblers, Runners and Brutes with deliberately lopsided
stats, so a horde forces target priority rather than being one texture.

**Settings** — mouse and gamepad sensitivity, invert look, master volume,
fullscreen, graphics preset and difficulty, saved between sessions. Difficulty
is not cosmetic: it changes extraction length, starting ammunition, spawn rate,
and the damage you take.

**Accessibility** — four colour vision modes (the health readout's colour comes
from the active palette, and bar length plus the number carry the same
information regardless), interface scaling from 80% to 150%, camera shake down
to zero, and a reduced-flashing option that damps the damage wash without
removing the feedback.

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

Runs import, arena generation, zombie navigation, spawn weighting, hitbox
scale, the game loop, pause, look input, progression, records, ammunition,
accessibility, the assignment feature tests, and a headless boot. It fails on
engine errors — Godot exits `0` even when scripts throw, so the check greps log
text rather than trusting exit codes.

Frame time is measured separately, because logic checks cannot tell you whether
the game is playable:

```bash
Godot --path . --script tools/benchmark.gd --resolution 1920x1080 -- --zombies=30
```

Must run *without* `--headless`: the headless renderer draws nothing and
reports a frame rate the game will never see. Current figures on an M2 Pro at
1080p with 26 zombies: 14.7ms mean, 14.8ms at the 95th percentile, against a
16.67ms budget.

## Building

Export presets for macOS, Windows and Linux are in `export_presets.cfg`, each
excluding `tools/`, `tests/`, `docs/` and the design and process directories
from the shipped build.

```bash
Godot --headless --export-release "macOS" build/macos/LastMagazine.zip
```

This needs Godot's export templates for 4.7.2 installed (Editor → Manage Export
Templates). Without them the presets still validate but no binary is produced.

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
- **Animated Characters: Survivors** — the zombie model, skins, and animations

CC0 requires no attribution, but Kenney is credited anyway. Each pack's
original licence file is preserved under `assets/licenses/`.

All code, scenes, lighting, the UI theme, and the arena layout are original to
this project. Full details in [CREDITS.md](CREDITS.md).

## Licence

MIT — see [LICENSE](LICENSE).
