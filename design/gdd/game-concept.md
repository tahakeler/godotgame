# Game Concept: LAST MAGAZINE

**Status**: Locked
**Created**: 2026-09-19
**Last Updated**: 2026-09-19
**Author**: tahakeler (with Claude Code)

---

## Elevator Pitch

Trapped in an arena until extraction arrives, you count every bullet — and every
zombie you put down drags the rescue clock closer, so the fastest way out is
straight through them.

The ten-second version: *a first-person arena survival shooter where killing
shortens the round, but ammunition only comes from kills.*

---

## Core Identity

| Field | Value |
|-------|-------|
| **Working Title** | LAST MAGAZINE |
| **Genre** | First-person arena survival shooter |
| **Perspective** | First-person |
| **Core Verb** | Shoot (deliberately) |
| **Primary MDA Aesthetic** | Challenge |
| **Secondary Aesthetic** | Sensation |
| **Target Platform** | PC (primary), Console-capable input |
| **Engine** | Godot 4.6 |
| **Estimated Scope** | Small (1-2 weeks, solo) |
| **Session Length** | 2-4 minutes per round |

---

## Core Fantasy

**The disciplined survivor who earns their way out.**

Not a power fantasy. The player is not a super-soldier mowing down a horde — they
are competent but supply-limited, and the feeling we are selling is *control under
scarcity*. The emotional peak is a clean round: no wasted shots, reloads taken at
the right moments, extraction reached with rounds to spare.

The emotional low we deliberately allow is the dry click of an empty magazine with
a zombie three metres away. That moment must be the player's fault, and they must
know it.

---

## Unique Hook

Like a wave-survival shooter, **and also** a game where killing does not merely
clear the room — it *shortens the round*.

This single inversion creates the whole design tension:

- Kills accelerate extraction → aggression is rewarded
- Kills cost bullets → aggression is expensive
- Bullets only come from kills → you cannot farm safety by hiding

Hiding is safe moment-to-moment but extends the round, and a longer round means
more time for the horde to build. There is no stable passive strategy.

---

## Player Experience Analysis (MDA Framework)

### Target Aesthetics (What the player FEELS)

| Aesthetic | Priority | How it is produced |
|-----------|----------|--------------------|
| **Challenge** | Primary | Ammo scarcity + escalating spawn pressure + no regenerating health |
| **Sensation** | Secondary | Weapon punch, hit feedback, directional damage flash, reload weight |
| **Discovery** | Minor | Learning arena geometry and spawn rhythms across replays |

Explicitly **not** targeted: Fellowship (single-player), Narrative (no story),
Expression (no builds or loadouts).

### Key Dynamics (Emergent player behaviours)

- **Reload windows** — players learn to read the arena for a safe 1.5-second gap
- **Target triage** — deciding which approaching zombie is worth a bullet *now*
- **Clock math** — "three more kills and I can hold this corner until extraction"
- **Kiting vs committing** — retreating preserves health but spends clock

### Core Mechanics (Systems we build)

1. First-person movement and look (WASD + mouse)
2. Hitscan weapon firing with raycast damage
3. Magazine/reserve ammunition with reload
4. Player health with contact damage and i-frames
5. Zombie spawner with escalating wave pressure
6. Zombie navigation and contact attack
7. Extraction timer that decrements on kill
8. HUD, win/loss resolution, and full-state restart

---

## Player Motivation Profile

### Primary Psychological Needs Served

- **Competence** — the dominant need. Each replay is measurably cleaner: fewer
  wasted shots, faster extraction, more health retained.
- **Autonomy** — moderate. The player chooses engagement range, target priority,
  and reload timing. They do not choose loadouts or upgrades (by design).
- **Relatedness** — not served. Single-player, no characters. Accepted tradeoff.

### Player Type Appeal (Bartle Taxonomy)

| Type | Appeal | Why |
|------|--------|-----|
| **Achievers** | Primary | Clear success metric, improvable run quality |
| **Competitors** | Primary | Self-competition on extraction time and accuracy |
| **Explorers** | Low | One arena, no secrets |
| **Socialisers** | None | No multiplayer or social layer |

**Who this is NOT for**: players seeking story, exploration, character progression,
or a relaxing experience. The game is deliberately short, tense, and repeatable.

### Flow State Design

- **Challenge ramp**: spawn rate increases over the round, so difficulty rises
  with player warm-up.
- **Grace period**: the first ~15 seconds are deliberately light, letting the
  player orient before pressure begins.
- **Failure cost**: low — rounds are 2-4 minutes and restart is instant, so death
  pushes players back into flow rather than out of it.
- **Feedback latency**: immediate. Every shot, hit, and damage event has a
  same-frame visual response.

---

## Core Loop

### Moment-to-Moment (30 seconds)

Assess threat direction → prioritise targets → fire counted shots → find a safe
window → reload → reposition.

### Short-Term (5-15 minutes)

Multiple rounds. The player experiments with engagement distance and reload
discipline, discovering that the arena's open centre is fast but exposed while the
edges are safe but slow.

### Session-Level (30-120 minutes)

Repeated attempts at a cleaner extraction. Natural stopping point is any
successful run.

### Long-Term Progression

None by design. Progression is in the player's skill, not in stored state. This
is a deliberate scope decision for a 1-2 week build.

### Retention Hooks

- "I can do that cleaner" — the primary hook
- Sub-goals players set themselves: no-damage run, fastest extraction

---

## Game Pillars

### Pillar 1: Every Bullet Is A Decision

Ammunition is scarce enough that firing is always a choice, never a reflex.

**Design test**: *If we are debating between giving the player more ammo and
preserving tension, we choose tension.*

### Pillar 2: Aggression Must Be Earned

The game rewards forward pressure, but only when it is skilled. Reckless
aggression is punished by the ammo economy; passivity is punished by the clock.

**Design test**: *If we are debating between rewarding safe play and rewarding
skilled pressure, we choose pressure.*

### Pillar 3: Readable At A Glance

In a first-person game with threats behind you, the player must always be able to
understand their situation in under a second.

**Design test**: *If we are debating between visual richness and instant clarity,
we choose clarity.*

### Anti-Pillars (What This Game Is NOT)

- **No cover system** — it would compromise Pillar 2 by making turtling viable.
- **No weapon variety or upgrades** — it would compromise Pillar 1, because
  abundance destroys scarcity, and it would compromise the timeline.
- **No narrative, cutscenes, or dialogue** — it would compromise Pillar 3 and
  consume time the build does not have.
- **No regenerating health** — it would compromise Pillar 1 and 2 by removing the
  persistent cost of mistakes.

---

## Inspiration and References

| Source | What we take | What we leave |
|--------|-------------|---------------|
| Godot Arena FPS tutorial | Core FPS control feel, arena structure | Its default abundance of ammo |
| Left 4 Dead | Directional damage readability, horde pressure | Co-op, narrative campaigns |
| Resident Evil (classic) | Ammo scarcity as a source of tension | Inventory management, puzzles |
| Doom (2016) | Aggression-is-rewarded design philosophy | Glory kills, weapon variety, scale |

---

## Target Player Profile

- **Primary**: players who enjoy short, skill-driven arena challenges and replay
  for self-improvement.
- **Secondary**: players who like survival-horror resource pressure but want a
  faster session than a full horror game.
- **Explicitly not targeted**: story-seekers, explorers, relaxation players.

---

## Technical Considerations

- **Engine**: Godot 4.6, GDScript primary
- **Rendering**: Forward+
- **Physics**: Jolt (Godot 4.6 default) — `CharacterBody3D` for player and zombies
- **Assets**: Kenney (CC0) low-poly packs plus primitive geometry. All external
  assets credited in the project README.
- **Navigation**: `NavigationAgent3D` on a baked `NavigationRegion3D`, or direct
  steering toward the player if navmesh proves unnecessary for a flat arena.
- **Input**: keyboard/mouse primary; action map defined so gamepad can be added.

---

## Risks and Open Questions

### Design Risks

- **Ammo tuning is the whole game.** Too generous and tension evaporates; too
  stingy and the round becomes unwinnable. Mitigation: expose all ammo values as
  exported variables for fast iteration.
- **First-person flanking frustration.** Threats behind the player are invisible.
  Mitigation: directional damage indicator on the HUD plus zombie proximity audio.

### Technical Risks

- **Zombie navigation on a flat arena** — low risk; steering is sufficient if
  navmesh causes trouble.
- **First Godot project** — the developer is new to the engine, so unknown-unknowns
  are the main schedule risk. Mitigation: build in vertical slices, test each
  system before moving on.

### Market Risks

Not applicable — this is a coursework build, not a commercial release.

### Scope Risks

- **Feature creep into weapon variety or multiple arenas.** Mitigation: the
  anti-pillars above are binding.

### Open Questions

- Exact magazine size and reserve ammo per kill — resolve by playtest.
- Round length target (currently 120 seconds baseline before kill reductions).
- Whether zombies drop ammo on death or ammo is awarded automatically per kill.

---

## MVP Definition

The minimum build that answers "is this fun?":

1. First-person player that moves, looks, and shoots in a walled arena
2. Zombies that spawn, path to the player, and die to bullets
3. Ammunition with magazine, reserve, and reload — empty magazine blocks firing
4. Player health that decrements on zombie contact and ends the round at zero
5. Extraction timer displayed on the HUD, reduced by kills, that wins at zero
6. Restart control that resets player, zombies, ammo, health, and timer

This MVP is also the complete assignment deliverable. Everything beyond it is
optional polish.

### Scope Tiers (if time shrinks)

| Tier | Contents |
|------|----------|
| **Must ship** | MVP items 1-6 above |
| **Should ship** | Directional damage indicator, hit feedback, zombie audio |
| **Could ship** | Kenney art pass replacing primitives, muzzle flash, particle blood |
| **Will not ship** | Weapon variety, upgrades, multiple arenas, menus beyond restart |

---

## Assignment Requirement Mapping

| Requirement | Implementation |
|-------------|----------------|
| Player input controls a 3D action | WASD movement, mouse look, left-click fire |
| Collision/overlap triggers gameplay response | Bullet raycast hits zombie (damage/death); zombie body contact hits player (damage) |
| Display progress | HUD: extraction countdown, health bar, ammo counter, kill count |
| Win/loss result | Win when extraction timer reaches zero; loss when health reaches zero |
| Restart control | `R` key restores player position, health, ammo, timer, and clears zombies |
| **Feature 1 — Player Health** | Trigger: zombie contact. State: `current_health` decrements. Result: health bar drops, damage flash, loss screen at zero. |
| **Feature 2 — Ammunition and Reload** | Trigger: fire input / reload input. State: `magazine_ammo` and `reserve_ammo`. Result: HUD counter updates, firing blocked at zero, reload refills magazine from reserve. |
| Bonus mechanic | Kills subtract seconds from the extraction timer. |

---

## Next Steps

1. Scaffold the Godot 4.6 project (`feat/project-scaffold`)
2. Build the arena and navigation (`feat/arena`)
3. Build the first-person player controller (`feat/player-controller`)
4. Build the weapon, ammunition, and reload system (`feat/ammo-reload`)
5. Build zombies, spawning, and contact damage (`feat/zombies`)
6. Build health, extraction timer, HUD, and restart (`feat/game-loop`)
7. Test normal and boundary cases for both features (`test/qa-pass`)
