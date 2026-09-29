#!/usr/bin/env bash
# Mechanizes lean-harness SKILL.md §7 "presentation artefacts are frozen": blocks
# a staged edit to a path listed as frozen. Called from hooks/git/pre-commit.
#
# scripts/frozen_paths.txt (in the project): one glob per line, matched against
# the repo-relative staged path with bash's [[ == ]]; '#' comments allowed.
# Missing file = no frozen paths, no-op.
#
# This enforces only the "don't touch it" half of the rule. The other half — log
# the divergence the day the Lean overtakes a frozen claim — is a discipline no
# script can check (LESSONS.md, "the frozen talk went stale").
set -euo pipefail

frozen_file="scripts/frozen_paths.txt"
[ -f "$frozen_file" ] || exit 0

staged=$(git diff --cached --name-only --diff-filter=ACMRD || true)
[ -z "$staged" ] && exit 0

fail=0
while IFS= read -r pattern; do
  [[ -z "$pattern" || "$pattern" == \#* ]] && continue
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # shellcheck disable=SC2053  # unquoted on purpose: $pattern is a glob
    if [[ "$f" == $pattern ]]; then
      echo "frozen-guard: BLOCKED — '$f' matches frozen path '$pattern' (scripts/frozen_paths.txt)."
      fail=1
    fi
  done <<< "$staged"
done < "$frozen_file"

if [ "$fail" -ne 0 ]; then
  echo "  Finished talks/papers are arguments, not living documents. If the Lean has overtaken"
  echo "  a claim in one, log the divergence in memory.md/TODO.md and leave the file alone."
  echo "  If the human explicitly asked for this edit: git commit --no-verify"
fi
exit "$fail"
