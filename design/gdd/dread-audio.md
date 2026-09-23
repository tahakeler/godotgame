# Dread Audio

## 1. Overview

The cave lies to the player. During quiet stretches a director plays phantom
sounds: footsteps closing in from behind, a call from deep in the tunnels,
rock settling, and once a round a breath at the player's shoulder. None of it
is real. Nothing a phantom plays reaches the zombies, the HUD or the noise
system. Under all of it the cave acoustics make real sounds hard to place:
stone reverb on every effect, distant sounds lose their top end, and a sound
behind rock arrives muffled.

## 2. Player Fantasy

"Something is following me." The player checks behind them, stops to listen,
spends a round of attention on a corridor that was always empty, and is never
sure which sounds to trust. The tension comes from anticipation, not from
contact.

## 3. Detailed Rules

- Phantoms only play while the round is PLAYING, never while the game is paused
  or on the level-up screen.
- **The calm clock** counts up while smoothed threat is under
  `calm_threshold`. It resets when threat passes `interrupt_threshold`. Nothing
  phantom starts while real danger is present.
- **The first phantom** can come only after `calm_before_first` seconds of
  calm. Phantoms are spaced at least `min_gap` apart.
- **The roll.** Each second, a phantom starts with the chance given in §4.
  Kinds are chosen by weight:
  - **FOOTSTEPS_BEHIND:** 3 to 6 steps behind the player, each one closer. The
    sequence stops the moment the player turns to face it, so there is never
    anything there to see.
  - **DISTANT_CALL:** a groan 22 to 35 m away.
  - **CAVE_SETTLE:** rock and creak 8 to 18 m away.
  - **CLOSE_BREATH:** a breath 2 m behind the player. It needs more than 60 s
    of calm and plays at most once per round.
- **Occlusion.** A 3D sound whose straight line to the camera hits map rock
  plays quieter and low-passed. This is decided once, when the sound starts.
- **Score** (Ambience):
  - **Cave bed:** a CC0 cave bed is picked each round.
  - **Tension layer:** fades in above threat 0.25 while the bed ducks, so
    the mix moves from dread to danger without switching tracks.
  - **Dread swell:** plays on the first notice after 40 s of calm, at most
    once per 90 s.
  - **Death:** every layer fades to silence.
- **Vitals:** below 35% health the SFX bus low-passes. The drop is
  front-loaded, reaching 650 Hz at death. A heartbeat on the Master bus, so
  it is never muffled, speeds up with severity. It clears on any round end.
- **Torch flicker:** the beam stutters when a hunting zombie is within 9 m,
  and rarely in calm with nobody near, so a flicker never reliably means
  anything. Only light energy changes; zombie sight does not.
- **Startle:** a notice within 6 m plays a low hit under the rasp. It never
  plays for a Stalker, with a 15 s cooldown.

## 4. Formulas

- `chance_per_second = lerp(base_chance, max_chance, clamp((calm − calm_before_first) / calm_ramp, 0, 1))`
- Occluded sound: `volume += occluded_volume_db`, `cutoff = occluded_cutoff_hz`.

## 5. Edge Cases

- **Real threat interrupts:** the calm clock resets, and a sequence already
  running finishes naturally.
- **The player turns mid-sequence:** it stops. The player is never shown an
  empty source.
- **No camera or world** (headless, menus): the sound plays unoccluded.
- **Restart:** `reset()` clears the calm clock, the gap and the breath flag.

## 6. Dependencies

- SoundBank (`play_at`)
- Ambience (smoothed threat)
- Game (round lifecycle)
- GameSettings buses (the reverb lives on SFX)
- Static map collision layer (occlusion)

## 7. Tuning Knobs

All are `@export` on DreadDirector and SoundBank:

- **DreadDirector:** `calm_threshold`, `interrupt_threshold`,
  `calm_before_first`, `calm_ramp`, `min_gap`, `base_chance`, `max_chance`,
  kind weights, distances, `step_interval`, `look_cut_angle`.
- **SoundBank:** `occluded_volume_db`, `occluded_cutoff_hz`, the distance
  filter, and the reverb constants in GameSettings.

## 8. Acceptance Criteria

`tests/manual/verify_dread.gd`, `verify_acoustics.gd`, `verify_score.gd`,
`verify_vitals.gd` and `verify_flicker.gd` check the following:

- Silent for the first `calm_before_first` seconds.
- At least 3 phantoms in 400 s of calm, never closer together than `min_gap`.
- None under sustained threat.
- Footsteps stop when faced.
- Silent while inactive.
- A wall occludes and open air does not.
- The SFX reverb is added exactly once.
- Every sound event resolves to at least one clip.
- The score silences on death and stays silent under later threat.
- Low health muffles and beats; healing clears it.
- The torch flickers near a hunter and in calm, never far and busy, and never
  changes zombie sight.

Feel is checked by playtest, not by these tests: the player should turn
around at least once in the first five quiet minutes.
