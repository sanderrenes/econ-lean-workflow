#!/usr/bin/env bash
# Flag .lean files inside a library directory that no build root of the package
# (transitively) imports. `lake build` compiles only what its roots reach, so an
# orphaned file is never checked: it can rot against an upstream rename for
# months while every build stays green (LESSONS.md, "orphaned module").
#
# Roots: each [[lean_lib]]'s `roots` (default: its `name`), plus each
# [[lean_exe]]'s `root` (default: its `name`). Handles lakefile.toml and the
# common lakefile.lean forms (`lean_lib X where roots := #[`A, `B]`). A library
# that sets `globs` is skipped: its build set is not "whatever the roots import",
# so this check would give a wrong answer, and a check that guesses is worse than
# none.
#
# Usage: scripts/check-orphan-modules.sh    (from the project root)
# Exit 1 if any orphan is found, 0 otherwise. Not a Lake project root: exit 0.
set -euo pipefail

lakefile=""
[ -f lakefile.toml ] && lakefile="lakefile.toml"
[ -f lakefile.lean ] && lakefile="lakefile.lean"
[ -z "$lakefile" ] && exit 0

lib_names=()   # library directories to scan for orphans
seeds=()       # modules every build starts from

if [ "$lakefile" = "lakefile.toml" ]; then
  kind=""; name=""; roots=""; root=""; globs=0
  flush() {
    [ -n "$kind" ] && [ -n "$name" ] || return 0
    if [ "$kind" = "lib" ]; then
      if [ "$globs" -eq 1 ]; then
        echo "check-orphan-modules: '$name' sets globs — skipped (build set is not root-reachability)."
        return 0
      fi
      lib_names+=("$name")
      if [ -n "$roots" ]; then
        for r in $roots; do seeds+=("$r"); done
      else
        seeds+=("$name")
      fi
    else
      seeds+=("${root:-$name}")
    fi
  }
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*\[ ]]; then
      flush
      kind=""; name=""; roots=""; root=""; globs=0
      [[ "$line" =~ ^[[:space:]]*\[\[lean_lib\]\] ]] && kind="lib"
      [[ "$line" =~ ^[[:space:]]*\[\[lean_exe\]\] ]] && kind="exe"
      continue
    fi
    [ -n "$kind" ] || continue
    if [[ "$line" =~ ^[[:space:]]*name[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
      name="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*root[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
      root="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*roots[[:space:]]*=[[:space:]]*\[(.*)\] ]]; then
      roots="$(echo "${BASH_REMATCH[1]}" | tr -d '"' | tr ',' ' ')"
    elif [[ "$line" =~ ^[[:space:]]*globs[[:space:]]*= ]]; then
      globs=1
    fi
  done < "$lakefile"
  flush
else
  # lakefile.lean: split into `lean_lib`/`lean_exe` blocks; read `roots`/`root`/`globs` inside each.
  while IFS=$'\t' read -r kind name body; do
    name="${name#«}"; name="${name%»}"
    if [ "$kind" = "lean_lib" ]; then
      if echo "$body" | grep -qE 'globs[[:space:]]*:='; then
        echo "check-orphan-modules: '$name' sets globs — skipped (build set is not root-reachability)."
        continue
      fi
      lib_names+=("$name")
      r="$(echo "$body" | grep -oE 'roots[[:space:]]*:=[[:space:]]*#\[[^]]*\]' | grep -oE '`[«»A-Za-z0-9_.]+' | tr -d '`«»' || true)"
      if [ -n "$r" ]; then while IFS= read -r x; do seeds+=("$x"); done <<< "$r"; else seeds+=("$name"); fi
    else
      r="$(echo "$body" | grep -oE 'root[[:space:]]*:=[[:space:]]*`[«»A-Za-z0-9_.]+' | grep -oE '`[«»A-Za-z0-9_.]+' | tr -d '`«»' || true)"
      seeds+=("${r:-$name}")
    fi
  done < <(awk '
    function emit() { if (k != "") { gsub(/\t/, " ", b); print k "\t" n "\t" b } }
    /^[[:space:]]*(@\[[^]]*\][[:space:]]*)?lean_(lib|exe)[[:space:]]/ {
      emit(); line = $0; sub(/^[[:space:]]*(@\[[^]]*\][[:space:]]*)?/, "", line)
      split(line, w, /[[:space:]]+/); k = w[1]; n = w[2]; b = ""; next }
    /^[[:space:]]*(package|require|lean_(lib|exe)|@\[|target|extern_lib|script)[[:space:]]/ { emit(); k = "" }
    k != "" { b = b " " $0 }
    END { emit() }' "$lakefile")
fi

[ "${#lib_names[@]}" -eq 0 ] && exit 0

# Module names imported by one file. Covers `import A B`, and the module-system
# forms `public import`, `private import`, `meta import`, `import all`.
imports_of() {
  sed -nE 's/^[[:space:]]*(public[[:space:]]+|private[[:space:]]+)?(meta[[:space:]]+)?import[[:space:]]+(all[[:space:]]+)?//p' "$1" \
    | sed -E 's/--.*$//' | tr -s ' \t' '\n' | tr -d '«»' | sed '/^$/d'
}

declare -A seen=()
queue=()
for s in "${seeds[@]}"; do
  [ -z "${seen[$s]:-}" ] && { seen["$s"]=1; queue+=("$s"); }
done
while [ "${#queue[@]}" -gt 0 ]; do
  mod="${queue[0]}"; queue=("${queue[@]:1}")
  f="${mod//.//}.lean"
  [ -f "$f" ] || continue                 # Mathlib, sibling packages, etc.
  while IFS= read -r imp; do
    [ -z "${seen[$imp]:-}" ] && { seen["$imp"]=1; queue+=("$imp"); }
  done < <(imports_of "$f")
done

fail=0
for lib in "${lib_names[@]}"; do
  lib_dir="${lib//.//}"
  orphans=()
  for f in "$lib_dir.lean"; do            # the library-named file itself, if roots skip it
    [ -f "$f" ] && [ -z "${seen[$lib]:-}" ] && orphans+=("$f")
  done
  if [ -d "$lib_dir" ]; then
    while IFS= read -r f; do
      m="${f%.lean}"; m="${m//\//.}"
      [ -z "${seen[$m]:-}" ] && orphans+=("$f")
    done < <(find "$lib_dir" -name '*.lean' -not -path '*/.lake/*' | sort)
  fi
  if [ "${#orphans[@]}" -gt 0 ]; then
    echo "check-orphan-modules: '$lib' — ${#orphans[@]} file(s) that no build root of THIS package"
    echo "  imports, so this package's 'lake build' never compiles them (a downstream package that"
    echo "  imports one still compiles it — but only when that package is rebuilt):"
    printf '    %s\n' "${orphans[@]}"
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "check-orphan-modules: every library file is reachable from a build root."
else
  echo "  Fix: import each file from a root (or from a module a root imports), or delete it."
  echo "  Before deleting, grep sibling packages for importers: a file only a downstream package"
  echo "  imports is compiled there, and deleting it breaks that package."
  echo "  A deliberate scratch file belongs outside the library directory."
fi
exit "$fail"
