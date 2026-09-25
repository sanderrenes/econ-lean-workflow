---
name: lean-econ-workflow
description: >-
  Start→run→end workflow for formalizing economics in Lean 4 (mechanism design,
  welfare, game theory, open games, or any similar multi-project Lean formalization
  effort) using a per-project CLAUDE.md / memory.md / progress.md / plan.md
  discipline with phase-based work and a Phase End Workflow. Use when beginning,
  continuing, or wrapping up a session on any Lean formalization project that
  follows this discipline, or when setting up a new one.
---

# Lean Proofs in Economics — Start / Run / End Workflow

> Portable version. This is a copy of the `lean-econ-workflow` skill generalized for
> reuse outside its origin workspace — no project names are hardcoded. If you're
> adopting this for a new workspace, see `README.md` in this folder for setup steps,
> and `LESSONS.md` for the incidents that shaped each rule below (read that before
> skipping a step — most of these exist because skipping them already broke
> something once).

A reusable summary of how work proceeds on a Lean 4 formalization project. Each
project is an **independent Lake project** with four control files and
**phase-based** work. This skill captures the full lifecycle.

## The four control files (every project has these)

| File | Role |
|------|------|
| `CLAUDE.md` | Per-project instructions: identity, protocol, build, assumptions. Read at session start. |
| `memory.md` | Live state: current phase, completed declarations, open sorries, blockers, token log, assumptions. **Single source of truth for status.** |
| `progress.md` | Append-only log: summary table (`Phase | Date | Tokens | Cumulative | Sorries`) + structured commit blocks. |
| `plan.md` | Phase-by-phase step list (the project's slice of any master plan). If the backlog is empty (all assigned phases/TODOs complete), keep the file but replace its body with a one-line "no open plan" note pointing at `memory.md`/`progress.md` — don't just delete it, since a missing `plan.md` is indistinguishable from one nobody got around to writing. |

An optional fifth file, `decisions.md`, holds an append-only design-decision log: one entry
per decision a reader of the code couldn't reconstruct from the code itself, stating the
**alternative rejected and why** — a decision without its discarded alternative is just a
description. Newest entry last. Create it lazily, on the first decision worth recording; an
empty `decisions.md` is boilerplate nobody needs.

Cross-cutting design decisions spanning multiple projects may live in a shared
`DESIGN_*.md` at the workspace root — when present, it is **authoritative for
resolving ambiguities** (see RUN §Ambiguities).

## What's a hook vs. what's in this file

This workflow deliberately splits into two layers, and mixing them up is itself a
recorded mistake (see `LESSONS.md`, "documentation drift"):

- **Hooks** (`hooks/`) enforce *mechanical, checkable-by-a-script* facts: a build
  actually ran, a `sorry` got logged, a git hook is installed, a default target is
  set. If a rule can be checked without judgment, it belongs in a script, not in
  prose someone has to remember to re-read. Scripts don't forget; people re-reading
  a long CLAUDE.md at hour six of a session do.
- **This file and `CLAUDE.md`** hold everything a script can't verify: what counts
  as "done" for this domain (honesty constraints, assumption tracking), how to
  resolve an ambiguity the plan doesn't answer, what the project's dependency
  structure is, which theorems are load-bearing. These require the judgment a
  hook can't apply.

When you find yourself writing a new prose rule of the form "always check X before
Y" and X is mechanically checkable, write a hook instead (or in addition) — see
`LESSONS.md` for two rules that stayed prose-only for months and caused real
incidents before anyone automated them.

---

## START — at the beginning of a session

1. **Read `memory.md` first.** Do not proceed without it. If missing, warn and offer to
   reconstruct from git log + existing `.lean` files; do not write Lean until restored.
2. **Read `CLAUDE.md`.** Confirm project goal and the active phase.
3. **Check tools.** Report status of:
   - `lean --version` (toolchain matches `lean-toolchain`),
   - `lake build` resolves (path dependencies present and built),
   - key Mathlib imports available.
   If Lean is unavailable, say so clearly — you can still review the plan, draft `.lean`
   for later, or update `memory.md`, but proofs cannot be verified.
4. **Report**: current phase, last completed declaration, open blockers/sorries.
5. **Ask** before writing Lean: *"Continue from where we left off, or change assumptions/goals?"*
   Wait for explicit confirmation.

Steps 1–3 are exactly what `hooks/claude-code/session-check.sh` checks
mechanically — wire it up as a `SessionStart` hook (see `README.md`) so this
report is generated instead of reconstructed from memory each time.

### New-project setup (one-time, if the project is freshly scaffolded)
Run the **Setup TODOs** recorded in `memory.md`, typically:
- `git init` + initial commit of the scaffolding (each project is its own repo);
- `lake update` to resolve local path dependencies (generates `lake-manifest.json`) —
  build upstream path-dependency projects first;
- confirm the project's `lean_lib`/`lean_exe` in `lakefile.lean` carries `@[default_target]`
  (or the equivalent `defaultTargets = [...]` in `lakefile.toml`). Without it, bare `lake build`
  silently reports `Build completed successfully (0 jobs)` and never compiles anything.
  **This is now checked mechanically** by `scripts/check-default-target.sh` (run from both
  `hooks/git/pre-push` and `hooks/claude-code/session-check.sh`) — see `LESSONS.md` incident 1
  for why this needed a hook rather than staying a checklist bullet;
- `lake build` to confirm a green, 0-sorry baseline before Phase 1 — check the job count in
  the output is nonzero, not just that the command exits 0;
- install the shared git hooks — `.git/hooks/` isn't itself tracked by git, so this step is
  needed again after every fresh clone:
  ```bash
  cp hooks/git/pre-commit hooks/git/pre-push .git/hooks/
  chmod +x .git/hooks/pre-commit .git/hooks/pre-push
  ```
  - `pre-commit` flags new `sorry`s in staged `.lean` files unless `memory.md` documents them.
    It only greps the diff — it does not compile, so it is cheap but not a build guarantee.
  - `pre-push` runs a real `lake build` (and, first, `check-default-target.sh`) and blocks the
    push on failure. This is the line of defense against a `memory.md`/`progress.md` entry
    claiming "done" for code that has silently gone stale against an upstream API change and no
    longer compiles — see `LESSONS.md` incident 2 for the real case that motivated this.
  - **The `session-check.sh` Claude Code hook now also flags a missing/stale install** of these
    git hooks at `SessionStart`, rather than relying on this checklist bullet being remembered —
    see `LESSONS.md` incident 5.
- if the project will live on GitHub, add a CI workflow (checkout + a Lean build action). If
  the project has a local Lake path dependency on a sibling repo, the workflow needs multiple
  checkout steps — one per dependency, checked out into the matching relative path.

---

## RUN — during a phase

A **phase** is the unit of work (usually one `.lean` file / one plan project). Within it:

- **One declaration at a time.** Definition or theorem, smallest viable step.
- **Compiler-guided.** Use the Lean LSP / `lake build` / single-file `lake env lean <File>`
  to drive proofs; prefer Mathlib lemmas; search before reinventing.
- **Update `memory.md` immediately** after each completed proof — move it to **Completed**,
  note the proof pattern if non-obvious.
- **Never mark `done` with a `sorry`.** Any intentional `sorry` is logged under **Open Sorries**
  in `memory.md` with a reason and date.
- **Before citing another file's lemma as an existing bridge to a hard result, `grep` for it
  and confirm it actually exists and compiles.** A proof-sketch comment claiming "the missing
  piece is available in `X.lean`" is not evidence the piece exists — see `LESSONS.md`
  incident 4, where such a comment sat unchecked and cost real investigation time before
  someone verified the cited lemma had never been written.

### Domain-specific discipline (economics; adapt for other domains)
- **Track assumptions explicitly.** Model-specific hypotheses (quasilinearity, single-crossing,
  positive welfare weights, full-support priors, finiteness, equilibrium-existence
  assumptions, ...) — carry them as named hypotheses, list them in `memory.md` "Assumptions
  in Force", and never silently strengthen.
- **Honesty constraint.** Never let a statement that is false or `sorry`'d in generality become
  load-bearing. If a clean theorem is only true under a model restriction, state and use the
  restricted version; document the false general form rather than asserting it. Record such
  facts in a `BLOCKERS.md` if one exists, and log the decision itself (keep sorry'd vs. delete
  vs. restrict scope, and why) in `decisions.md`.
- **Declarative vs. executable.** If the project is declarative, results may be `noncomputable`
  and use classical choice; do not add `Decidable`/enumeration machinery for its own sake.

### Resolving ambiguities
When a question the plan doesn't answer arises, resolve it **against existing decisions**, not in
isolation: consult the shared `DESIGN_*.md` consistency rules if present (precedence: headline
decisions > structural > resolved questions > local convenience; prefer reuse of proved API;
respect the honesty and assumption constraints). If a choice contradicts a higher-tier decision,
the higher tier wins or must be explicitly reopened with the user.

---

## END — Phase End Workflow
*(run when a phase's deliverables are complete and the build is green — 0 new sorries)*

0. **Run `lake build` clean, from the project root, before anything else in this section.**
   Don't rely on editor squiggles or the pre-commit hook — the hook only greps for `sorry`,
   it does not compile. Check the job count is nonzero (`Build completed successfully (0 jobs)`
   means the default target is misconfigured and nothing was actually checked — see START
   §New-project setup). A phase isn't done until this passes with a real, nonzero build and
   0 new sorries.
1. **Update `memory.md`**:
   - Move the phase's theorems/definitions into **Completed**.
   - Confirm **0 sorries** or record each placeholder with a reason.
   - Note new proof patterns and any assumptions/hypotheses invoked.
   - Set **Current Phase** to the next phase.
2. **Update `progress.md`**:
   - Append a summary-table row: `| phase | date | ~Nk | ~cumulative | sorry-count |`.
   - Append a structured commit block (fields below).
2b. **Update `decisions.md`** if the phase made a nontrivial, non-obvious design choice
   (an API shape, a rejected alternative, a restriction adopted for honesty reasons) — append
   an entry with the alternative rejected and why. Skip if nothing decision-worthy happened.
2c. **If this phase changed a status claim that's duplicated elsewhere** (an outer/parent
   `CLAUDE.md`, a workspace-level `README.md` summarizing this project), update that copy in
   the *same* commit. A status claim copied into a second file and not updated when the first
   changes is the single most common way this workflow has gone stale in practice — see
   `LESSONS.md` incident 3.
3. **Git Commit Protocol**:
   ```bash
   git add *.lean <Lib>/**/*.lean memory.md progress.md plan.md decisions.md
   git commit -m "phase(N): <one-line summary>

   Phase: <N> (<plan id, e.g. P3>)
   Completed: <theorems/definitions>
   Sorries: <count> open (<names>)
   Tokens: ~<N>

   <notes on approach / blocked items / hypotheses carried>"
   ```
   First line: `phase(N): ` prefix, imperative, ≤72 chars; body fields all required.
4. **(Optional) Graph versioning**: if the project keeps a `dep-graph-*.mermaid`, snapshot it
   per commit and refresh `dep-graph-current.mermaid`.
5. **Confirm next-phase prerequisites** (upstream names proved, dependencies built) before starting.

### Mid-phase session end
If a working session ends before a phase completes, still update `memory.md` (current proof
state) and `progress.md` (partial row), but the **full** Phase End Workflow (and the
`phase(N)` commit) runs only at phase completion.

---

## Quick checklist

```
START  □ read memory.md  □ read CLAUDE.md  □ check tools  □ report  □ ask to continue
       (new project) □ default_target set  □ pre-commit + pre-push hooks installed  □ CI added
RUN    □ one decl at a time  □ compiler-guided  □ update memory.md per proof
       □ no undocumented sorry  □ assumptions tracked  □ honesty constraint  □ ambiguity → design doc
       □ verify cited bridging lemmas actually exist before relying on them
END    □ lake build clean  □ memory.md updated  □ progress.md row + commit block
       □ decisions.md if applicable  □ duplicated status claims elsewhere updated too
       □ phase(N) git commit  □ 0 sorries confirmed  □ next-phase prereqs checked
```

See `LESSONS.md` for the incidents each rule above was written in response to, and for
proposed additions not yet built into a hook.
