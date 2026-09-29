#!/usr/bin/env bash
# Post-completion audit: the mechanical half of lean-harness SKILL.md §6. Run it
# before a "0 sorry, build green, done" claim goes into a status file, a paper, a talk
# or a submission — it targets the ways that claim can be hollow while still true.
#
#   1. escape hatches in source   sorry/admit/native_decide/implemented_by/axiom/opaque/
#                                 kernel-weakening set_option, outside comments (textual)
#   2. Palomar sorry count        each Challenge's sorry count == its advertised holes
#                                 (theorem_names + definition_names)
#   3. orphaned modules           check-orphan-modules.sh
#   4. build                      `lake build` (with --clean: root package outputs deleted
#                                 first, so nothing is a cached false green); job count > 0;
#                                 sorry warnings counted
#   5. axioms                     check-axioms.sh on the configured targets
#
# What it cannot do — and what the audit is actually for — is printed at the end:
# non-vacuity and faithfulness. See templates/VERIFICATION.md.template.
#
# Usage: scripts/audit-completion.sh [--clean]     (from the project root)
set -uo pipefail

clean=0; [ "${1:-}" = "--clean" ] && clean=1
fail=0
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
section() { echo; echo "== $1"; }

if [ ! -f lakefile.toml ] && [ ! -f lakefile.lean ]; then
  echo "audit-completion: not a Lake project root."; exit 1
fi

# Tracked .lean sources of this package (not .lake, not dependencies).
mapfile -t srcs < <(git ls-files '*.lean' 2>/dev/null || find . -name '*.lean' -not -path './.lake/*')

section "1. escape hatches in source (comments stripped; docstrings are not — read each hit)"
# Challenge.lean files are the one permitted sorry source in a Palomar layout (counted in 2).
hits=0
for f in "${srcs[@]}"; do
  body="$(sed -E 's/--.*$//' "$f")"
  pat='\bsorry\b|\badmit\b|native_decide|implemented_by|^[[:space:]]*((private|protected|noncomputable|unsafe)[[:space:]]+)*(axiom|opaque)[[:space:]]|set_option[[:space:]]+debug\.|@\[extern'
  case "$f" in */Challenge.lean|Challenge.lean) pat="${pat#\\bsorry\\b|}";; esac
  out="$(echo "$body" | grep -nE "$pat" || true)"
  if [ -n "$out" ]; then
    echo "$out" | sed "s|^|  $f:|"
    hits=1
  fi
done
[ "$hits" -eq 0 ] && echo "  none." || { echo "  ^ each hit is either inside a docstring (fine) or a finding."; fail=1; }

section "2. Palomar Challenge sorry count"
if git ls-files --error-unmatch '*comparator.json' >/dev/null 2>&1 && command -v python3 >/dev/null; then
  while IFS= read -r cfg; do
    python3 - "$cfg" <<'EOF' || fail=1
import json, os, re, sys
cfg = sys.argv[1]; c = json.load(open(cfg))
base = os.path.dirname(cfg)
mod = c["challenge_module"]
path = mod.replace(".", "/") + ".lean"
if not os.path.exists(path):
    path = os.path.join(base, mod.split(".")[-1] + ".lean")
src = re.sub(r"--.*", "", open(path).read())
src = re.sub(r"/-.*?-/", "", src, flags=re.S)        # drop comments and docstrings
n_sorry = len(re.findall(r"\bsorry\b", src))
n_thm = len(c.get("theorem_names", []))
n_def = len(c.get("definition_names", []))   # a definition hole is also `:= sorry`
ok = n_sorry == n_thm + n_def
print(f"  {cfg}: {path} has {n_sorry} sorry; comparator.json advertises "
      f"{n_thm} theorem(s) + {n_def} definition hole(s)" + ("" if ok else "  <-- MISMATCH"))
sys.exit(0 if ok else 1)
EOF
  done < <(git ls-files '*comparator.json')
else
  echo "  no comparator.json — not a Palomar layout, skipped."
fi

section "3. orphaned modules"
if [ -x "$here/check-orphan-modules.sh" ]; then "$here/check-orphan-modules.sh" | sed 's/^/  /'; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
else echo "  check-orphan-modules.sh not found next to this script — NOT CHECKED."; fi

section "4. build$([ $clean -eq 1 ] && echo ' (clean: root package outputs deleted first)')"
if ! command -v lake >/dev/null; then
  echo "  lake not on PATH — NOT CHECKED."; fail=1
else
  [ "$clean" -eq 1 ] && rm -rf .lake/build
  build_out="$(lake build 2>&1)"; rc=$?
  echo "$build_out" | grep -E 'Build completed|error' | tail -5 | sed 's/^/  /'
  [ "$rc" -eq 0 ] || { echo "  BUILD FAILED."; fail=1; }
  echo "$build_out" | grep -qE '\(0 jobs\)' && { echo "  0 jobs — nothing was compiled (default target?)."; fail=1; }
  n_sorry_warn="$(echo "$build_out" | grep -c "declaration uses 'sorry'" || true)"
  echo "  sorry warnings in build output: $n_sorry_warn$([ $clean -eq 0 ] && echo ' (without --clean, only rebuilt modules are guaranteed to report)')"
fi

section "5. axioms"
if [ -x "$here/check-axioms.sh" ]; then
  out="$("$here/check-axioms.sh" 2>&1)"; rc=$?
  if [ -z "$out" ]; then echo "  no targets configured (scripts/axiom_targets.txt or comparator.json) — NOT CHECKED."
  else echo "$out" | sed 's/^/  /'; fi
  [ "$rc" -eq 0 ] || fail=1
else echo "  check-axioms.sh not found next to this script — NOT CHECKED."; fi

section "Not checked by this script — do these by hand (SKILL.md §5, §6)"
cat <<'EOF'
  - Non-vacuity: instantiate each headline theorem at an object the field cares about and
    prove every hypothesis holds there (an inhabited hypothesis type, a canonical example).
  - Faithfulness: read each statement as `#check` prints it, not as its docstring describes
    it; where feasible, brute-force the statement independently of Lean on small cases.
  - Prose: docstrings, README, notes and formalization.yaml say what the theorem proves, at
    that strength, under that name.
  Record the result in VERIFICATION.md (templates/VERIFICATION.md.template).
EOF

echo
[ "$fail" -eq 0 ] && echo "audit-completion: mechanical checks passed." \
                  || echo "audit-completion: one or more mechanical checks FAILED or were not run (see above)."
exit "$fail"
