# Lessons: what went wrong, and what the workflow does about it now

This is the postmortem record behind `lean-econ-workflow`'s rules. Each rule in
`SKILL.md` that looks like defensive overkill exists because skipping it already
cost real time once, in the workspace this workflow was extracted from. Recorded
here so the reasoning travels with the workflow instead of living only in that
workspace's own `memory.md`/`progress.md` history.

Format per incident: what happened → why it wasn't caught sooner → what catches
it now (or the proposal, if nothing does yet).

---

## Incident 1 — silent "0 jobs" builds (default target not set)

**What happened**: four sibling Lean projects had no `@[default_target]` (or
`defaultTargets = [...]` in `lakefile.toml`) on their `lean_lib`/`lean_exe`. Bare
`lake build` exited 0 and printed `Build completed successfully (0 jobs)` —
which reads as a passing build in scrollback unless you read the job count —
while never actually compiling anything. This went unnoticed until an explicit
audit in 2026-07-24.

**Why it wasn't caught sooner**: the pre-push hook at the time ran `lake build`
and checked only the exit code, not the job count. A misconfigured default
target and a genuinely empty, fully-verified project produce the same exit
code.

**Caught now by**: `scripts/check-default-target.sh`, called from both
`hooks/git/pre-push` (blocks the push) and `hooks/claude-code/session-check.sh`
(flags it at session start, before any work happens). `pre-push` also now greps
the build output itself for `(0 jobs)` as a second line of defense, in case a
future refactor changes what "default target" means in a newer Lake version.

---

## Incident 2 — a theorem marked done silently stopped compiling

**What happened**: in one project, a theorem was marked complete in `memory.md`
for several weeks after an *upstream* project's public signature changed
underneath it. Nothing rebuilt it in the meantime, so nothing failed — until a
real `lake build` was finally run before a push, well after the drift started.

**Why it wasn't caught sooner**: nothing in the workflow ran a real build
between commits. `memory.md` said "done," and there was no mechanism to
re-verify that claim against the current state of its dependencies.

**Caught now by**: `hooks/git/pre-push` — requires a clean `lake build` (with a
nonzero job count, per incident 1) before anything leaves the machine. This is
the single most load-bearing hook in the workflow: it's the only check that
re-verifies old "done" claims against the *current* state of the world rather
than trusting what was true when they were written.

**Residual gap**: `pre-push` only fires when someone pushes. A long session that
never pushes can still accumulate silent drift. Proposed addition (not yet
built): a periodic/idle `lake build` via a Claude Code hook (e.g. on `Stop`,
throttled), or a CI job on a schedule independent of pushes.

---

## Incident 3 — a status claim, copied into a second file, went stale there

**What happened**: this pattern recurred twice.
1. A project's own `CLAUDE.md`/`README.md` were updated same-day when its last
   `sorry` was eliminated, but the *outer*, workspace-level `CLAUDE.md` that
   summarized it (read first, and the actual source later documents had copied
   their claim from) was never touched — so it kept asserting a `sorry` existed
   for over a week after it didn't.
2. A workspace `README.md` paragraph asserted a phase was still open; it had
   actually been folded into an adjacent phase and finished, but the summary
   paragraph was never revisited to say so.

**Why it wasn't caught sooner**: status was duplicated across files with no
single source of truth and no mechanism keeping the copies in sync — exactly
the failure mode `memory.md`'s "single source of truth for status" rule exists
to prevent *within* one project, but nothing enforced it *across* the
project/workspace-summary boundary.

**Caught now by**: nothing mechanical yet — currently only a process rule
(`SKILL.md` END §2c: "if this phase changed a status claim duplicated
elsewhere, update that copy in the same commit"). This is the clearest
candidate in this list for a hook that doesn't exist yet:

**Proposed addition**: a `check-status-consistency.sh` that greps sibling
`CLAUDE.md`/`README.md`/`memory.md` files for sorry-count or phase-status
assertions (e.g. `\d+ sorr(y|ies)`, `Phase \w+.*(done|complete|open)`) and flags
when a summary file's claim is older (by git blame date) than the file it
summarizes. Not built here because a robust version needs a convention for
*where* such claims are allowed to live, which this workflow doesn't yet
standardize — worth deciding before automating a check against it.

---

## Incident 4 — a proof-sketch comment cited a bridging lemma that was never written

**What happened**: a `sorry`'d lemma's own comment claimed the missing piece
("a decomposition iso ... available in `Equivalence.lean`") already existed
elsewhere in the codebase. When someone finally went to use it, a direct grep
found no such lemma had ever been written — the comment was aspirational, not
a real lead, and had sat unchecked long enough to look like documented fact.

**Why it wasn't caught sooner**: nothing required a citation like that to be
verified before being trusted; it read as settled because it was written in
the same confident register as the rest of the file.

**Caught by**: process rule only (`SKILL.md` RUN: grep for a cited lemma and
confirm it compiles before relying on it as a bridge). Not mechanically
enforced — a hook could in principle flag `-- available in <file>`-style
comments and check the reference resolves, but the signal is too free-text to
do reliably; left as a discipline item, not a hook, deliberately (see
"Considered and rejected" below for the reasoning pattern).

---

## Incident 5 — git hooks not reinstalled after a fresh clone

**What happened**: `.git/hooks/` is never tracked by git, so every fresh clone
of every project silently loses the `pre-commit`/`pre-push` protection until
someone remembers to re-run the two-line install command. This was a standing
checklist bullet (START §New-project setup) with no enforcement — easy to skip
under time pressure, and skipping it is invisible (nothing complains that the
hooks are missing).

**Caught now by**: `hooks/claude-code/session-check.sh`, run as a `SessionStart`
hook — compares `.git/hooks/pre-commit`/`pre-push` against the tracked copies
and prints an install command if they're missing or stale. This is the
clearest example in this workflow of a checklist bullet moving from "documented
in prose, enforced by nobody" to "checked automatically every session."

---

## Considered and rejected

Two workspace-wide conventions were fixed as *rules in `CLAUDE.md`* rather than
hooks, on purpose:

- **Descriptive names instead of opaque labels** (no bare `(a)`/`(b)`/`Type 1` in
  place of a named concept). A grep-based hook flagging new parenthetical
  letter labels was considered and rejected: too many false positives (legal
  citations, list markers, math notation) for the enforcement value, and the
  judgment of "is this label actually a scheme that needs a name" isn't
  mechanical. Kept as a CLAUDE.md rule with a worked example instead.
- **kebab-case top-level project folder names, no typos.** A pre-commit hook on
  the workspace root that flags a newly-added top-level directory not matching
  `^[a-z0-9]+(-[a-z0-9]+)*$` *would* be cheap and low-false-positive — this one
  is a reasonable candidate to actually build, unlike the label-naming rule
  above. Not included in this package because it's a workspace-root concern
  (one check per workspace, not per project) rather than part of the portable
  per-project bundle; add it directly to a workspace's own root `.git/hooks/`
  if adopting this convention.

The general pattern: a hook is worth building when the check is both mechanical
*and* low-false-positive. "Opaque label" and "cited lemma actually exists" both
failed the second condition and stayed prose; "default target set," "git hooks
installed," and "build actually green" all passed both and got automated.

---

## Related, deliberately separate skills

This file only covers incidents about *multi-project orchestration* (session/phase
discipline, status duplicated across control files, the workspace's own git-hook
mechanics). Two adjacent bodies of incident history are kept in their own skills
instead of folded in here, because they're a different axis of the problem and don't
apply to every project that adopts this workflow:

- **`lean-harness`** — single-project Lean *proof-quality* discipline: axiom hygiene,
  what dependency/usage claims are safe to trust, linter blind spots, instantiating a
  theorem at a canonical example, docstring/frozen-artifact drift. Applies to any Lean
  project regardless of whether it uses this workflow's control-file convention.
- **`palomar-comparator`** — submission-format discipline specific to projects
  structured as Palomar Challenge/Solution/`comparator.json` submissions (proof-term
  auxiliary numbering, the Challenge-sorry-count exception, statement-surface size
  caps). Doesn't apply to a project that isn't a Palomar submission.

Both are registered as skills at the workspace root they were extracted from
(`.claude/skills/lean-harness`, `.claude/skills/palomar-comparator`) rather than
copied into this portable package, since they cite specific sibling project paths
this package is deliberately generalized away from. Adapt them the way this package's
own `README.md` describes adapting `SKILL.md`, if reusing them elsewhere.

## Open proposals (not yet built)

Ranked roughly by how much of the observed damage each would have prevented:

1. **Status-consistency checker** (incident 3) — highest value, not yet
   designed past the sketch above; needs a convention decision first.
2. **Idle/periodic rebuild** (incident 2's residual gap) — a `Stop`-hook or
   scheduled CI rebuild independent of push timing, to shrink the window drift
   can hide in.
3. **kebab-case top-level naming hook** (from "Considered and rejected") — cheap,
   workspace-root-specific, straightforward to add if a workspace wants it.
4. **Cited-reference existence check** (incident 4) — lowest confidence of
   paying off; likely stays a discipline item rather than a hook.
