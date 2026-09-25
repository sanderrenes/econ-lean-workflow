#!/usr/bin/env bash
# lean-econ-workflow: SessionStart check.
# Mirrors SKILL.md START §1-3 mechanically, plus the two checks that used to be
# checklist bullets nobody reliably re-read: git hooks installed/current, and
# the default-target trap (LESSONS.md incidents 1 and 5). Prints a report;
# never blocks the session — START step 5 (ask before writing Lean) stays a
# human/model judgment call, not something this script decides.
set -uo pipefail

ok=1
note() { echo "  - $1"; }

echo "lean-econ-workflow session check ($(pwd)):"

if [ -f memory.md ]; then
  note "memory.md: present"
else
  note "memory.md: MISSING — reconstruct from git log before writing Lean (do not skip this)"
  ok=0
fi

if [ -f CLAUDE.md ]; then
  note "CLAUDE.md: present"
else
  note "CLAUDE.md: not found in this directory (fine if this isn't a project root)"
fi

if command -v lake >/dev/null 2>&1; then
  note "lake: $(lake --version 2>/dev/null | head -1)"
else
  note "lake: NOT on PATH — proofs cannot be verified this session"
fi

if [ -d scripts/git-hooks ] || [ -d hooks/git ]; then
  hook_src_dir="scripts/git-hooks"
  [ -d hooks/git ] && hook_src_dir="hooks/git"
  if [ -f .git/hooks/pre-commit ] && [ -f "$hook_src_dir/pre-commit" ] \
     && cmp -s .git/hooks/pre-commit "$hook_src_dir/pre-commit" \
     && [ -f .git/hooks/pre-push ] && [ -f "$hook_src_dir/pre-push" ] \
     && cmp -s .git/hooks/pre-push "$hook_src_dir/pre-push"; then
    note "git hooks: installed and current"
  else
    note "git hooks: NOT installed or out of date — run:"
    note "    cp $hook_src_dir/pre-commit $hook_src_dir/pre-push .git/hooks/ && chmod +x .git/hooks/pre-commit .git/hooks/pre-push"
    ok=0
  fi
fi

default_target_script=""
[ -x scripts/check-default-target.sh ] && default_target_script="scripts/check-default-target.sh"
[ -x hooks/../scripts/check-default-target.sh ] && default_target_script="hooks/../scripts/check-default-target.sh"
if [ -n "$default_target_script" ]; then
  if "$default_target_script"; then
    note "default target: configured"
  else
    ok=0
  fi
fi

if [ "$ok" -eq 1 ]; then
  echo "  all checks passed — see memory.md for current phase and continue START §4-5."
else
  echo "  one or more checks need attention before proceeding (see above)."
fi

exit 0
