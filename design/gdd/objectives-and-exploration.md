# Signal Relays and Graded Supply

Status: Designed — NOT IMPLEMENTED. See "Implementation Handoff" at the end.

## 1. Overview

The map is worth moving through and nothing asks the player to move. This design
adds one objective type — a **relay chain** — and one reward rule — **supply value
graded by distance from the centre**.

Three signal relays sit at the three deepest terminal points of the cave. Each must
be reached and held to arm. Arming a relay is loud: it broadcasts noise for the whole
hold and keeps leaking noise afterwards, so the player is deliberately calling a crowd
to the worst place on the map to be caught — a dead end with one exit. Once all three
are armed, the extraction point opens back at the central chamber and the player has
to run the whole way home. The objective is one line on the HUD at all times
("RELAY 2 OF 3 — DEEP NORTH", then "EXTRACT — RETURN TO THE ARENA") and a bearing on
the compass the game already draws.

This ships as a fourth mode, `Mode.RELAY`. `EXTRACTION` and `TIMED` are untouched.

## 2. Player Fantasy

You are not waiting for rescue. You are *calling* it, and the call is what gives you
away. Every relay is a decision to make the loudest noise in the game in the place
you least want to be heard, then survive the consequences of having done it. The walk
out is reconnaissance; the walk home is a chase.

Target MDA aesthetics, in priority order:

- **Challenge** — primary. The cost of the objective is paid in the noise system, not
  in a difficulty multiplier.
- **Discovery** — secondary. The deep arms currently terminate in nothing. After this
  they terminate in the best supplies on the map.
- **Sensation** — tertiary. The residual beacon hum is a spatial audio source that
  says "they know where this is" for as long as it runs.

Against Self-Determination Theory:

- **Autonomy** — relay order is free. Three targets, no forced sequence; the player
  chooses which deep arm to spend their opening ammunition on, and whether to arm a
  relay immediately or clear the chamber first.
- **Competence** — failure is legible. If a Screamer arrives mid-hold, the player
  heard the hold being loud and can name the mistake. Feedback is within the 0.5s
  micro window (the hold ring) and the 5–15 minute meso window (a relay armed).
- **Relatedness** — thin, as it is in the rest of the game. The rescue on the other
  end of the signal is the only other party in the fiction; the relay chain makes it
  something the player acts toward rather than waits on.

## 3. Detailed Rules

### 3.1 Mode

Add `Mode.RELAY` to `GameSettings.Mode` as the **last** enum entry. Appending rather
than inserting matters: `GameSettings.load_settings()` reads the mode back as a raw
int from `user://settings.cfg`, so inserting would silently reassign every saved
preference on every existing install.

Register `MODE_NAMES[Mode.RELAY] = "Signal"`, a `MODE_BLURBS` entry, and
`MODE_DURATIONS[Mode.RELAY] = 0.0`.

In `RELAY`:

- There is no countdown. `elapsed_time` counts up and is the score, exactly as
  `ENDLESS` already does in `Game._process()`. Reuse that branch — the condition
  becomes "mode has no win clock" rather than "mode is ENDLESS".
- Kills award ammunition as they always do. Kills do **not** move any clock; the
  `mode != Mode.EXTRACTION` early return in `_on_zombie_died()` already handles this
  correctly with no edit.
- `spawner.endless` stays **false**. The escalation ramp in `ENDLESS` exists because
  that mode cannot be won; `RELAY` can be, and the relay chain is its own escalation.

### 3.2 The relay chain

Three `SignalRelay` nodes are placed from a table (§7, `RELAY_PLACEMENTS`) at the
three furthest points from the origin:

| Relay | Cell | Label | Approx. distance from centre |
|---|---|---|---|
| Deep north | `Vector2i(0, 12)` | `DEEP NORTH` | 12 cells |
| Deep west | `Vector2i(-11, 0)` | `WEST HALL` | 11 cells |
| Deep east | `Vector2i(12, 0)` | `EAST HALL` | 12 cells |

These are the three terminal chambers already in `Arena.LAYOUT` (`CENTRE_ROOM` at
(0,12), `WIDE_ROOM` at (-11,0), `WIDE_ROOM` at (12,0)). The south `WIDE_ROOM` at
(0,-8) is deliberately **not** a relay: it is only 8 cells out and it sits on the
route to the southern ring, so it is the chamber the player passes through anyway.
Three relays that all require a dedicated trip is the point.

A relay is in exactly one of three states: `DORMANT`, `ARMING`, `ARMED`.

**Arming.** A relay uses the same interaction contract as `AmmoCache` and `Medkit` —
a held interact with a `hold_duration`. `relay_hold_duration` defaults to **3.0s**,
longer than the medkit's 2.0s and much longer than the cache's 1.2s, because it is the
most expensive commitment in the game. A hold interrupted for any reason returns the
relay to `DORMANT` with **zero progress banked**. Partial credit would turn the relay
into something you chip at between waves, and the whole design is that it is one
unbroken window of vulnerability.

**Noise.** For the entire duration of the hold, the relay emits a noise pulse every
`relay_pulse_interval` (default 0.5s) at `relay_arming_loudness` (default 0.9 — twice
the cache's 0.45, and near a gunshot). After arming completes it continues pulsing at
`relay_residual_loudness` (default 0.35) for `relay_residual_duration` (default 20.0s)
before going silent. Noise is emitted from the **relay's** position, not the player's,
matching the muzzle-not-player rule already established in `Game._wire_noise()`: the
crowd converges on the relay, so the player's play is to arm it and then not be
standing next to it.

Every pulse routes through `Game._make_noise()`. That is non-negotiable — it is the
single call that both broadcasts to the spawner and reports the cost to the HUD's
noise ring, so a relay that called `spawner.broadcast_noise()` directly would be loud
without ever telling the player it was loud.

**Reward.** On reaching `ARMED`, the relay spawns a medkit at its own position via
`Medkit.spawn(relay_parent, relay.global_position + RELAY_REWARD_OFFSET)`, and the
newly spawned kit is passed to `Game.wire_medkit_audio()` so it has a voice. The
reward exists only after the player has committed, and it is the resource they will
need because of what the commitment just summoned.

### 3.3 Extraction

When the third relay reaches `ARMED`, the objective changes to extraction. The
extraction point is the **central chamber**, cell `Vector2i(0, 0)` — the player's own
spawn. Sending them home rather than to a fourth unexplored point is deliberate: the
run home crosses ground they have already made noisy, against a crowd that has spent
the round converging on three widely separated points. It is the only leg of the
round where the player knows exactly where they are going and that is what makes it
a chase rather than a search.

Extraction requires standing within `extraction_radius` (default 4.0m) of the
extraction point for `extraction_hold_duration` (default 2.0s). Entering the radius
alone does not win; a win the player can trip over by accident is not a win they
earned. Completing the hold calls `Game._end_round(RoundState.WON)`.

### 3.4 HUD contract

The relay system never touches the HUD. `Game` owns the routing, matching the rule
already stated in `Game._ready()` for the interactor's prompt.

One new signal on `Game`:

```gdscript
signal objective_changed(text: String, bearing_target: Vector3, has_bearing: bool)
```

`HUD` gets one new method and one label inside the existing `$ObjectiveBlock`:

```gdscript
## The single line telling the player what they are doing and where.
func set_objective(text: String, bearing_target: Vector3, has_bearing: bool) -> void
```

Text is exactly one line, upper case, and always in one of these forms:

| State | Text |
|---|---|
| 0 armed | `SIGNAL RELAYS — 0 OF 3 ARMED` |
| Arming | `ARMING RELAY — DEEP NORTH` |
| 1–2 armed | `SIGNAL RELAYS — 2 OF 3 ARMED` |
| All armed | `EXTRACT — RETURN TO THE ARENA` |
| Extracting | `EXTRACTING…` |
| Round over | `""` (the block is hidden by `_set_round_readouts_visible`) |

**Direction without a map.** `bearing_target` feeds the compass `HUD` already draws
(`_draw_compass`). The compass gets a single chevron at the bearing of the nearest
dormant relay — or of the extraction point once the chain is complete. It shows a
*direction*, never a route and never a distance.

This is the rule that keeps the objective from defeating fog-of-war. The minimap's
reveal system (`sample_visibility()`, touch/sight/torch) is untouched: a relay's cell
is revealed by the same earning rule as any other cell. The player is told which way
to walk and nothing at all about how to get there — which, on a map with a ring, two
crossroads and four arms, is still a real navigation problem. An objective marker
painted on the minimap would answer that problem and delete the cave.

## 4. Formulas

### 4.1 Arming progress

```
progress(t) = t_held / relay_hold_duration          for an unbroken hold
progress     = 0                                     the instant the hold breaks
armed        = progress >= 1.0
```

`t_held` accumulates only while the interact action is held AND the player is inside
the relay's interaction volume. No decay curve, no partial banking (§5).

### 4.2 Relay noise over time

Let `T = relay_hold_duration` (3.0), `I = relay_pulse_interval` (0.5),
`L_a = relay_arming_loudness` (0.9), `L_r = relay_residual_loudness` (0.35),
`D = relay_residual_duration` (20.0).

```
pulses_arming   = floor(T / I)              = floor(3.0 / 0.5) = 6
pulses_residual = floor(D / I)              = floor(20.0 / 0.5) = 40
total_loudness  = pulses_arming * L_a + pulses_residual * L_r
                = 6 * 0.9 + 40 * 0.35 = 5.4 + 14.0 = 19.4
```

For comparison, a full 8-round magazine at the pistol's loudness is ~8.0 of the same
unit. **One relay is louder than two magazines**, and most of that noise arrives after
the player has stopped being able to control it. That ratio is the design: the
objective is the loudest thing in the game and the player should be able to feel the
arithmetic without being shown it.

Three relays over a round: `3 * 19.4 = 58.2`. The whole chain is the noise budget of
roughly seven magazines, spent at three fixed, widely separated, dead-end locations.

### 4.3 Graded supply value

Cache payout scales with distance from the centre, so an arm is worth walking down.

```
rounds(cell) = cache_base_rounds + round(cache_rounds_per_cell * |cell|)
where |cell| = sqrt(cell.x^2 + cell.y^2)
```

With `cache_base_rounds = 8` and `cache_rounds_per_cell = 0.9`:

| Cache cell | \|cell\| | Rounds |
|---|---|---|
| `(0, 7)` | 7.00 | 8 + 6 = **14** |
| `(-5, 0)` | 5.00 | 8 + 5 = **13** |
| `(5, 0)` | 5.00 | 8 + 5 = **13** |
| `(0, 12)` deep north (new) | 12.00 | 8 + 11 = **19** |
| `(-11, 0)` west hall (new) | 11.00 | 8 + 10 = **18** |
| `(12, 0)` east hall (new) | 12.00 | 8 + 11 = **19** |

A deep cache is worth ~1.4x a mid cache. That is a real incentive and not a
game-breaking one: the walk is roughly three times as long and three times as exposed,
so the *rate* still favours the inner loop. The deep cache is a deliberate loss on
rate and a win on lump sum — which is exactly the trade a player low on ammunition
with a relay to arm wants to be offered.

**Curve choice.** Linear in distance rather than quadratic. Quadratic would make the
deep caches so rich that a player would farm the ring on recharge and ignore the
middle of the map, which is a degenerate loop (§5).

## 5. Edge Cases

| Case | Behaviour | Why |
|---|---|---|
| Hold interrupted at 2.9s of 3.0 | Progress resets to 0 | Partial banking turns a commitment into an errand. The pain is the mechanic. |
| Round restarts mid-hold | Relay returns to `DORMANT`, progress 0, `Interactor.reset()` already called in `start_round()` | This is the exact class of bug QA just found twice (interact state surviving death and restart). `Game.start_round()` must call `relay.reset()` on every relay, in the same block that calls `cache.reset()`. |
| Round ends (win or loss) mid-hold | Hold is abandoned; `_end_round()` already disables `player.interactor` | Same reason the interact key is disabled there today: the results screen must not be a place the map can still be worked. |
| Player dies with 2 relays armed | Relays reset on the next `start_round()`, not on death | The round is over; nothing should carry. Asserted by the test. |
| Player dies mid-extraction-hold | Loss. Death is checked in `_on_player_died()` and sets state before the hold can complete | Death always wins ties. |
| Extraction hold completes on the same frame as death | `_end_round()` guards on `state != RoundState.PLAYING`; whichever sets state first wins and the second is a no-op | Deterministic, and the existing guard already provides it. |
| All three relays armed but player never returns | Round never ends. `elapsed_time` climbs forever | Acceptable and intended — `RELAY` has no clock, and a player hiding forever is doing so with zero ammunition income and an escalating crowd. Not a stable strategy. |
| Relay placed in a chamber the navmesh failed to bake | Relay is still armable (it is a trigger volume, not navmesh), but no zombie can reach it, making it free | **Mitigation required at implementation:** assert at build time that each relay cell is present in the arena's occupied-cell dictionary, and log an error if not. |
| `arena.caches_enabled` is false | No caches build; relays are unaffected and still place | Relays are their own table, not an extension of the cache table. |
| Two relays armed simultaneously | Impossible — one player, one interactor | Noted only to state that no multi-arm ordering logic is needed. |
| Screamer recruits during a hold | Intended. This is the headline failure case | The 36m Screamer recruit radius against a 0.9 pulse in a dead-end chamber is the single most dangerous moment in the design, and it should be. |
| `relay_residual_duration` set to 0 | Relay goes silent immediately on arming | Valid tuning floor; removes the "you cannot un-ring the bell" pressure. Documented as the low end of the range, not a bug. |

### Degenerate strategies considered

**Snipe-and-flee.** Arm a relay, immediately sprint out, let the crowd pile onto an
empty chamber, and never fight. This is *intended play*, not degenerate — it costs the
medkit the relay just dropped (you left it), and ammunition only comes from kills, so
a player who never fights runs dry before the third relay. The balancing loop is
already in the economy.

**Ring farming.** Cycle the outer ring hitting deep caches on recharge, never arming
anything. Mitigated by the linear (not quadratic) payout curve in §4.3 — the deep
caches lose on rate — and by the fact that `RELAY` has no win condition that time
alone satisfies. A player doing this is choosing to not finish the round.

**Torch-off relay run.** Arm all three with the flashlight off to minimise minimap
sight and zombie attention. Fine. That is the game's existing bargain being used well:
the player trades their own vision for the cave's. Sirlin's line applies — this is
mastery, not an exploit.

**Reload-cancel the residual.** Nothing in the design lets the player stop the
residual broadcast. Confirmed intentional: the irreversibility is what makes arming a
decision rather than a button.

## 6. Dependencies

| System | Direction | Contract |
|---|---|---|
| `Game` (`src/core/game.gd`) | owns | Instantiates the objective controller, routes relay noise into `_make_noise()`, routes objective text into the HUD, resets relays in `start_round()`, ends the round on extraction. |
| `GameSettings` (`src/core/game_settings.gd`) | reads | Supplies `Mode.RELAY` and its name/blurb/duration entries. |
| `Arena` (`src/arena/arena.gd`) | reads | Supplies `_cell_to_world()` for placement and the occupied-cell set for the navmesh sanity check. Additive change only: three new `CACHE_CELLS` entries and one new `MEDKIT_PLACEMENTS` entry. |
| `AmmoCache` | reads | Payout is set from the graded formula at build time; `reset()` contract unchanged. |
| `Medkit` | calls | `Medkit.spawn(parent, position)` for the relay reward. New kits must be passed to `Game.wire_medkit_audio()`. |
| `ZombieSpawner` | writes (indirect) | Every relay pulse reaches it via `Game._make_noise()` → `spawner.broadcast_noise()`. Never called directly. |
| `HUD` (`src/ui/hud.gd`) | writes | One new `set_objective()` method and a compass chevron. No other HUD change. |
| `Player.interactor` | reads | Provides the held-interact contract and is already reset in `start_round()` and disabled in `_end_round()`. |
| `Records` | reads | `submit(mode, difficulty, kills, elapsed_time, won)` already takes the mode; `RELAY` records by elapsed time, lower being better. **Confirm `Records` treats a no-clock mode's time as a score, not a survival duration, before shipping.** |

Broken/unverified references: `design/gdd/` contains no document for the noise system,
the spawner, or the arena. This document cites their behaviour from source, not from a
GDD. That is a documentation gap worth closing but not a blocker here.

## 7. Tuning Knobs

All values live in exported vars or `const` tables, per the house rule. The placement
table follows the `ZombieTypes` pattern.

```gdscript
## Where each relay stands, and what the HUD calls it. Ordered deep-north,
## west, east — but order is presentational only; the player picks their own.
const RELAY_PLACEMENTS := [
    {"cell": Vector2i(0, 12),  "offset": Vector3(-2.8, 0.0, 0.0), "label": "DEEP NORTH"},
    {"cell": Vector2i(-11, 0), "offset": Vector3(0.0, 0.0, 2.8),  "label": "WEST HALL"},
    {"cell": Vector2i(12, 0),  "offset": Vector3(0.0, 0.0, 2.8),  "label": "EAST HALL"},
]
```

Offsets mirror `Arena.CACHE_OFFSET`'s reasoning — clear of every point in
`SPAWN_SPREAD`, and on the opposite side from the chamber's cache so the player is not
made to choose between standing in a crate and standing in a relay.

| Knob | Default | Range | Category | Rationale |
|---|---|---|---|---|
| `relay_hold_duration` | 3.0s | 1.5–6.0 | Feel | Longer than the medkit's 2.0s so it reads as the biggest commitment in the game. Below ~1.5s it stops being a window of vulnerability. |
| `relay_arming_loudness` | 0.9 | 0.4–1.2 | Curve | Twice `CACHE_LOUDNESS` (0.45), near a gunshot. This is the number that sets the whole cost of the objective — tune it first. |
| `relay_residual_loudness` | 0.35 | 0.0–0.6 | Curve | Below `CACHE_LOUDNESS`, above `FOOTSTEP_LOUDNESS` (0.22). A relay that has been armed should be noisier than a person walking and quieter than a crate being opened. |
| `relay_residual_duration` | 20.0s | 0.0–45.0 | Gate | Long enough to cover the retreat from a dead end. At 0 the "cannot un-ring the bell" pressure disappears entirely — that is the intended low end for a Recruit-difficulty variant. |
| `relay_pulse_interval` | 0.5s | 0.25–1.0 | Feel | Ten pulses would be a siren; one would be a tell you could miss. Also the cost knob — halving it doubles total loudness (§4.2). |
| `relay_count_required` | 3 | 1–3 | Gate | The session-length knob. Three deep trips plus the run home is the target round; two is the Recruit-difficulty cut. |
| `extraction_radius` | 4.0m | 2.0–8.0 | Feel | Must comfortably contain the spawn point without being trippable from a corridor mouth. |
| `extraction_hold_duration` | 2.0s | 0.0–4.0 | Feel | Matches the medkit. Non-zero so the win is taken, not stumbled into. |
| `cache_base_rounds` | 8 | 4–14 | Curve | The inner-loop cache payout floor. |
| `cache_rounds_per_cell` | 0.9 | 0.3–1.6 | Curve | Sets how strongly distance pays. Above ~1.6 the deep caches dominate on rate and ring-farming becomes viable (§5). |
| `relay_reward_kit` | true | bool | Gate | Whether arming drops a medkit. Off is the Veteran-difficulty variant. |

Per-difficulty overrides belong in `DIFFICULTY_PROFILES` alongside
`extraction_duration`, using the same shape.

## 8. Acceptance Criteria

### Functional — `tests/manual/verify_objectives.gd`

The test pins `Mode.RELAY` explicitly (do **not** change `DeterministicSettings`,
which pins `EXTRACTION` for `verify_game_loop.gd` and `verify_progression.gd`).
Structure follows `verify_game_loop.gd`: `_initialize()` instantiates, the first
`_process` frame calls `DeterministicSettings.apply(root)` then overrides the mode
then `start_round()`, and `_teardown()` frees the scene before `quit()`.

1. **`test_relay_advances_only_on_completed_hold`** — drive a relay's hold to
   `relay_hold_duration - 0.01` and assert it is still `DORMANT` and the armed count
   is still 0. Then advance past the threshold and assert `ARMED` and count 1. Then,
   separately, advance a dormant relay by pure elapsed time with no hold and assert it
   is still `DORMANT`. This is the "never on a timer alone" assertion.
2. **`test_interrupted_hold_banks_no_progress`** — hold to 90%, break the hold, resume,
   and assert the relay needs a full fresh `relay_hold_duration`.
3. **`test_hud_objective_text_matches_state`** — after 0, 1, 2 and 3 arms, assert the
   string handed to `HUD.set_objective()` equals the exact expected line from §3.4.
   Assert against the value the HUD actually received, not against the controller's
   internal counter — the claim under test is that the player was told.
4. **`test_extraction_only_available_after_full_chain`** — with 2 of 3 armed, place the
   player at the extraction point, complete the hold, assert the round is still
   `PLAYING`. Arm the third, repeat, assert `WON`.
5. **`test_extraction_hold_is_required`** — stand inside `extraction_radius` for one
   frame with the chain complete and assert the round has not been won.
6. **`test_restart_resets_every_relay`** — arm all three, then `start_round()`, and
   assert all three are `DORMANT`, armed count is 0, the objective line is back to
   `SIGNAL RELAYS — 0 OF 3 ARMED`, and no residual broadcast is pending. Then repeat
   the same assertions after a **death** followed by `start_round()`. Both paths are
   asserted because QA found two separate bugs where interact state survived exactly
   one of them.
7. **`test_relay_noise_routes_through_game`** — assert that an arming pulse increments
   whatever `Game._make_noise()` increments (spawner broadcast + HUD noise report),
   proving the relay cannot be loud silently.
8. **`test_existing_modes_unchanged`** — cheap regression: assert
   `Mode.EXTRACTION`'s integer value is unchanged and that a round started in
   `EXTRACTION` still has `time_remaining == extraction_duration`.

Register as a `run_step` line in `tools/check.sh`. `verify_game_loop.gd` and
`verify_progression.gd` must pass **unmodified** — if either needs a change, the round
flow was broken and the design is wrong, not the test.

### Experiential — validated by playtest, not by CI

- A player who has never seen the mode can state their current goal and point roughly
  in the right direction within 5 seconds of being asked, at any point in the round.
- Players report the *first* relay as tense and the *third* as the hardest, without
  any difficulty value changing between them. If the third is not harder, the residual
  noise is not doing its job and `relay_residual_duration` is too short.
- At least one player in five, unprompted, retreats from a chamber immediately after
  arming rather than standing and fighting. If nobody does, `relay_arming_loudness` is
  too low.
- Players choose to walk down a deep arm for the cache *before* they have a relay
  reason to. If not, `cache_rounds_per_cell` is too low.
- No player reports being "lost" for more than ~30 seconds. If they do, the compass
  chevron is insufficient and the fallback is a distance band on the objective line
  (`— 40M`), not a minimap marker.

---

## Implementation Handoff

This document is design only. Implementation, `tests/manual/verify_objectives.gd`,
the `tools/check.sh` registration, and the commit on `feat/objectives` still need to
be done by an agent with shell access.

New files expected:

- `src/gameplay/objectives/signal_relay.gd` — one relay: state, hold, pulse timer,
  `reset()`. Emits `armed()` and `noise_pulsed(at: Vector3, loudness: float)`. Knows
  nothing about `Game`, the HUD, or the spawner.
- `src/gameplay/objectives/relay_objective.gd` — the chain: owns the three relays,
  counts arms, owns the extraction hold, produces the objective line and bearing.
  Emits `objective_changed` and `completed()`.

Edits expected: `src/core/game_settings.gd` (append `Mode.RELAY` + table entries),
`src/core/game.gd` (instantiate, wire noise through `_make_noise`, wire text to the
HUD, `reset()` in `start_round()`, end round on `completed`), `src/ui/hud.gd`
(`set_objective()` + compass chevron — additive only), `src/arena/arena.gd` (three
`CACHE_CELLS` entries, one `MEDKIT_PLACEMENTS` entry, graded payout).
