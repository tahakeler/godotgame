#!/usr/bin/env bash
# Pre-merge verification for LAST MAGAZINE.
# Runs import, static project checks, and a headless boot, then fails on any
# engine error. Run this before merging any branch to main.

set -uo pipefail

GODOT="${GODOT_BIN:-/Applications/Godot47.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${TMPDIR:-/tmp}/lastmagazine-check"

export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$DOTNET_ROOT:$PATH"

mkdir -p "$LOG_DIR"
cd "$PROJECT_DIR" || exit 1

if [[ ! -x "$GODOT" ]]; then
  echo "FATAL: Godot binary not found at $GODOT"
  echo "Set GODOT_BIN to override."
  exit 127
fi

fail_count=0

# Engine errors that must fail the build. Godot exits 0 on script errors, so the
# only reliable signal is the log text itself.
ERROR_PATTERN='SCRIPT ERROR|Parse Error|ERROR:|Failed to load|Cannot open|error CS[0-9]+'

# Godot reports audio streams as still referenced when a headless run quits
# mid-playback: the AudioServer holds them even after the nodes release them.
# A teardown artifact of --script runs, not a fault in the game. This is the
# only message excluded, and it is excluded by exact text.
BENIGN_PATTERN='resources still in use at exit'

run_step() {
  local name="$1"
  local log="$LOG_DIR/${name}.log"
  shift

  echo "--- $name ---"
  "$@" >"$log" 2>&1
  local code=$?

  local errors
  errors="$(grep -E "$ERROR_PATTERN" "$log" | grep -vE "$BENIGN_PATTERN" || true)"

  if [[ $code -ne 0 ]]; then
    echo "FAIL: $name exited $code"
    [[ -n "$errors" ]] && echo "$errors" | head -20
    fail_count=$((fail_count + 1))
    return 1
  fi

  if [[ -n "$errors" ]]; then
    echo "FAIL: $name reported engine errors"
    echo "$errors" | head -20
    fail_count=$((fail_count + 1))
    return 1
  fi

  echo "PASS: $name"
  return 0
}

run_step "import" "$GODOT" --headless --import
run_step "static-checks" "$GODOT" --headless --script tests/manual/verify_project.gd
run_step "arena" "$GODOT" --headless --script tests/manual/verify_arena.gd
run_step "zombies" "$GODOT" --headless --script tests/manual/verify_zombies.gd
run_step "game-loop" "$GODOT" --headless --script tests/manual/verify_game_loop.gd
run_step "feature-tests" "$GODOT" --headless --script tests/feature_tests.gd
run_step "boot" "$GODOT" --headless --quit-after 120

echo
if [[ $fail_count -gt 0 ]]; then
  echo "RESULT: FAILED ($fail_count step(s)). Logs in $LOG_DIR"
  exit 1
fi

echo "RESULT: PASSED — safe to merge"
exit 0
