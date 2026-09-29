#!/usr/bin/env bash
# Mechanizes lean-harness SKILL.md §1 rule 3: axioms are exactly
# [propext, Classical.choice, Quot.sound]. A theorem can build green and contain
# no `sorry` in its own file while still resting on `sorryAx`, a custom `axiom`,
# or `Lean.ofReduceBool` (native_decide) pulled in through a dependency —
# `#print axioms` is the only way to see that.
#
# Targets, first match wins:
#   1. $AXIOM_TARGETS, else scripts/axiom_targets.txt — one "<ImportModule> <declName>" per line, '#' comments.
#        e.g.  MyLib.MasterTheorem MyLib.masterTheorem_isomorphism
#   2. every comparator.json in the repo (Palomar layout): its `solution_module`
#      is imported and each of `theorem_names` is checked. Needs python3.
#   Neither present: no-op (exit 0). Opt in per project by creating (1).
#
# Usage: scripts/check-axioms.sh     (from the project root, after `lake build`)
set -euo pipefail

allowed_axioms='propext|Classical\.choice|Quot\.sound'

targets="$(mktemp)"; tmp_lean="$(mktemp --suffix=.lean)"
trap 'rm -f "$targets" "$tmp_lean"' EXIT

targets_file="${AXIOM_TARGETS:-scripts/axiom_targets.txt}"
if [ -f "$targets_file" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$targets_file" > "$targets" || true
elif command -v python3 >/dev/null 2>&1 && git ls-files --error-unmatch '*comparator.json' >/dev/null 2>&1; then
  git ls-files '*comparator.json' | python3 -c '
import json, sys
for path in sys.stdin.read().split():
    c = json.load(open(path))
    for t in c.get("theorem_names", []):
        print(c["solution_module"], t)
' > "$targets"
fi
[ -s "$targets" ] || exit 0

if ! command -v lake >/dev/null 2>&1; then
  echo "check-axioms: 'lake' not found on PATH — NOT CHECKED."
  exit 0
fi

fail=0
while read -r module decl; do
  printf 'import %s\n#print axioms %s\n' "$module" "$decl" > "$tmp_lean"

  out="$(lake env lean "$tmp_lean" 2>&1)" || {
    echo "check-axioms: FAILED to elaborate '$decl' from '$module':"
    echo "$out" | sed 's/^/    /'
    fail=1
    continue
  }
  # Flatten first: Lean wraps a long axiom list across lines, and parsing only the
  # first line would read a wrapped list as empty — a clean, wrong pass.
  flat="$(echo "$out" | tr '\n' ' ')"

  if echo "$flat" | grep -q 'does not depend on any axioms'; then
    echo "check-axioms: '$decl' — no axioms."
    continue
  fi
  list="$(echo "$flat" | grep -oE 'depends on axioms:[[:space:]]*\[[^]]*\]' | head -1 || true)"
  if [ -z "$list" ]; then
    echo "check-axioms: BLOCKED — could not parse axiom output for '$decl'; inspect manually:"
    echo "$out" | sed 's/^/    /'
    fail=1                                # an unparsed answer is not a pass
    continue
  fi

  extra="$(echo "$list" | sed -E 's/.*\[//; s/\].*//' | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d' \
    | grep -vE "^($allowed_axioms)\$" || true)"

  if [ -n "$extra" ]; then
    echo "check-axioms: BLOCKED — '$decl' depends on non-standard axiom(s):"
    echo "$extra" | sed 's/^/    /'
    echo "$extra" | grep -q '^sorryAx$' && echo "    (sorryAx = a sorry somewhere in its dependency closure)"
    echo "$extra" | grep -q 'ofReduceBool' && echo "    (Lean.ofReduceBool = native_decide somewhere in its closure)"
    fail=1
  else
    echo "check-axioms: '$decl' — standard axioms only."
  fi
done < "$targets"

exit "$fail"
