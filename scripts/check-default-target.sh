#!/usr/bin/env bash
# Detect a Lake project whose default target isn't set, so `lake build` can
# silently report "Build completed successfully (0 jobs)" without checking
# anything. Called from hooks/git/pre-push and hooks/claude-code/session-check.sh.
#
# Historical incident: this happened undetected in four sibling Lean-econ
# projects until caught 2026-07-24 (see LESSONS.md incident 1) — nobody noticed
# because "0 jobs" still exits 0 and looks like a passing build in a terminal
# scrollback unless you read the job count.
set -euo pipefail

lakefile=""
[ -f lakefile.toml ] && lakefile="lakefile.toml"
[ -f lakefile.lean ] && lakefile="lakefile.lean"
[ -z "$lakefile" ] && exit 0  # not a Lake project root — nothing to check

if [ "$lakefile" = "lakefile.toml" ]; then
  if ! grep -qE '^\s*defaultTargets\s*=' "$lakefile"; then
    echo "check-default-target: WARNING — $lakefile has no 'defaultTargets = [...]'."
    echo "  'lake build' will silently report 0 jobs and check nothing. Add it."
    exit 1
  fi
else
  if ! grep -qE '@\[default_target\]' "$lakefile"; then
    echo "check-default-target: WARNING — $lakefile has no '@[default_target]' on any lean_lib/lean_exe."
    echo "  'lake build' will silently report 0 jobs and check nothing. Add it."
    exit 1
  fi
fi

exit 0
