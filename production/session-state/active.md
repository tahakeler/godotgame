# Active session state

<!-- STATUS -->
Epic: Early Access push
Feature: post-facing-fix re-measurement, ammo economy, Stalker commit
Task: two agents working; lead reviewing
<!-- /STATUS -->

## Baseline on main

Gate 37 steps, exit 0. Frame time 6.91ms mean, 1.11ms physics (budget 16.6).
Map 238 cells, 1 area, 14 chokepoints, 55/55 spawns reach, 8/8 caches.

## The big finding this session

**Every zombie was facing 180 degrees from its direction of travel.** Steering
used `atan2(velocity.x, velocity.z)`, putting +Z along travel, while the model,
`look_at()`, the 140 degree sight cone and the lunge all use Godot's -Z forward.
Measured `dot(facing, direction_to_player) = -1.00` across an entire approach.

HUNTING is only entered by *seeing* the player, so one sign explained four
separate apparent design problems: the hunting tell rarely lit, `threat_level()`
read near zero during a mauling, Screamers could not raise alarms, and Stalkers
could not break off.

Fixed and verified by the lead: steering is `atan2(-x, -z)`, `facing()` returns
`-basis.z`, benchmark flat.

**Any measurement taken before this fix is suspect**, especially anything
sight-dependent. The agent that found it deliberately tuned nothing, because
the obvious pre-fix read — "the Screamer is too weak, raise its alarm radius" —
would have been exactly backwards.

## Open measurements

- **Screamer cascade: still unmeasured.** The probe wakes all 12 zombies at
  t=0, so nothing remains in UNAWARE to recruit. 36 alarms, 0 recruits is an
  artefact of the probe, not a result. Needs the probe to start them asleep.
- **Stalker dithers at arm's length.** Lone Stalker, stationary player: closes
  to 2.6m and never attacks, 45% stalled, 0.44 reversals/s, 100% out of view.
  Reach is ~1.85m, so it orbits just outside its own strike range. Hypothesis:
  `preferred_approach_point()` swings faster than the Stalker can follow as it
  closes, so flanking should stop governing once inside striking distance.
- **Ammo economy: not yet measured post-fix.** Pre-fix figures understate the
  pressure, because pursuit was far weaker than intended.

## Decisions taken as lead

- **Melee does not stagger a Brute.** Its defining rule is that you must move,
  not shoot. Becomes a feedback requirement instead: the hit must land loudly
  and visibly fail to move it.
- **Runner overrun as a melee window: keep.** Rewards reading an overcommit;
  the 1.1s cooldown stops it becoming a rhythm.
- **Runner's lead over Shamblers is fixed with spawn distance, not speed.**
  5.8 is the readability ceiling.
- **Do not chase the 2-of-12 that never arrive.** Map geometry, and the map is
  being rebuilt in Blender. Noted as a check for the import instead.
- **The camera is mouse and right stick only.** Arrow keys were bound to the
  four look actions purely to satisfy the gate's "every action needs a keyboard
  binding" rule. They are gone, and an assertion now requires a stick binding
  and forbids a keyboard one.

## Watch list

- The HUNTING glow (`HUNTING_GLOW_ENERGY 0.32`) now fires properly for the
  first time, because the facing bug meant zombies rarely reached HUNTING. On
  screen a hunting zombie reads bright red against a grounded palette. Not
  changed — flagged for the owner's judgement.

## Standing constraints

- **Do not touch `src/arena/arena.gd`.** The owner builds real maps in Blender;
  this one is a test environment. On import, the Blender geometry is the source
  of truth and agents handle Godot integration only.
- **Do not grow the gate.** 37 steps is enough. New checks only for a real
  regression, a high-risk system or a concurrency issue.
- **Judge the gate by its exit code**, never by grepping its output.
- Briefs must be small, concrete and finishable in ~20 turns; agents commit the
  moment the gate is green.
