# lean-econ-workflow (portable package)

## What this is

[Lean 4](https://lean-lang.org/) is a proof assistant and dependently-typed
programming language: it lets you state a mathematical claim as a type and write
a program (a "proof term") that the compiler's kernel checks really has that
type. If it type-checks, the claim is proved — mechanically verified, not just
plausible. [Mathlib](https://leanprover-community.github.io/mathlib4_docs/) is
Lean's large community-maintained math library, and most formalization work
consists of stating a result and connecting it to Mathlib's existing lemmas.

**This package is a workflow for *formalizing economics results in Lean*** —
mechanism design, welfare theorems, game theory, revenue equivalence, and similar
— using an LLM coding agent as the day-to-day driver. It is a Start→Run→End
discipline for multi-project, multi-session work: the four control files
(`CLAUDE.md`/`memory.md`/`progress.md`/`plan.md`), phase-based commits, and the
git/Claude Code hooks that keep an agent honest about build status across
sessions. Nothing here is economics-specific except the "Domain-specific
discipline" section of `SKILL.md` (assumption-tracking, the honesty constraint),
which is written to be adapted to a different domain if needed.

This folder is a self-contained, generalized copy: no project names from its
origin workspace are hardcoded. Copy or symlink it into a new project/workspace
to adopt the workflow there.

## What this is *not*

- **Not a Lean-teaching or Lean-proving skill.** This workflow assumes an agent
  that already knows how to write and debug Lean/Mathlib proofs, and only
  governs the surrounding process (session discipline, status files, commit
  hygiene, phase structure). For the actual proof work — planning a
  formalization, searching Mathlib, driving the compiler loop, golfing a
  finished proof — use a dedicated Lean skill instead, e.g.
  [cameronfreer/lean4-skills](https://github.com/cameronfreer/lean4-skills)
  (`/lean4:draft`, `/lean4:prove`, `/lean4:autoprove`, `/lean4:golf`, ... —
  installed as the `lean4` plugin in this environment). This package's own
  `SKILL.md` cites those commands rather than re-implementing them.
- **Not an MCP server.** Interacting with a running Lean/Lake process — goal
  state, diagnostics, search, `#print axioms` output — needs a live language-
  server connection, which this package doesn't provide. That's
  [`lean-lsp-mcp`](https://github.com/oOo0oOo/lean-lsp-mcp) (`uvx lean-lsp-mcp`),
  the MCP server the `mcp__lean-lsp__*` tools in this environment come from.
  This package's hooks shell out to `lake`/`lean` directly for cheap, scriptable
  checks (build status, axiom list) — they don't need or duplicate the MCP.
- **Not proof-quality or submission-format discipline.** Whether a given proof
  is *trustworthy* (axiom hygiene, vacuous hypotheses, linter blind spots) is
  the sibling `lean-harness` skill's job; whether a project is *ready to submit*
  to the [Palomar](https://palomar-registry.org/) registry — the public,
  permanent submission format built around a `Challenge.lean` statement surface,
  a `Solution.lean`, and a `comparator.json` that an independent Comparator tool
  audits before publication — is the sibling `palomar-comparator` skill's job.
  See "Related skills" below.

## What's in here

| Path | What it is | Where it goes |
|---|---|---|
| `SKILL.md` | The workflow itself (START/RUN/END, the four control files). Also explains the hooks-vs-docs split. | Claude Code skill dir, e.g. `.claude/skills/lean-econ-workflow/SKILL.md` |
| `CLAUDE.md.template` | Per-project instructions template — fill in and drop at each project's root. | `<project>/CLAUDE.md` |
| `hooks/git/pre-commit`, `hooks/git/pre-push` | Git hooks: flag undocumented new `sorry`, require a real green `lake build` before push. | Copy into each project's own `scripts/git-hooks/` (tracked by git), then `cp` into `.git/hooks/` per clone (see below — `.git/hooks/` itself is never tracked). |
| `scripts/check-default-target.sh` | Catches the "`lake build` silently reports 0 jobs" trap. Called by `pre-push` and `session-check.sh`. | Copy into each project's `scripts/`. |
| `hooks/claude-code/session-check.sh` | Claude Code `SessionStart` hook — runs the mechanical parts of START §1-3 automatically (memory.md present, git hooks installed and current, default target set, lake on PATH). | Copy anywhere convenient (e.g. `.claude/hooks/`) and point `settings.json` at it. |
| `hooks/claude-code/settings.snippet.json` | Example `hooks.SessionStart` config wiring `session-check.sh` in. | Merge into `.claude/settings.json`. |
| `LESSONS.md` | Postmortem: five incidents that shaped these rules, which ones now have automated checks, and open proposals that don't yet. | Read once before adopting; keep in this folder for reference. |

## Adopting this for a new project

1. Copy this whole folder into the new workspace (or symlink it if you want
   updates to propagate — the hooks and skill are workspace-agnostic).
2. Per project:
   - Copy `CLAUDE.md.template` to `<project>/CLAUDE.md` and fill in the
     placeholders (identity, dependencies, decisions in force).
   - Copy `hooks/git/pre-commit` and `hooks/git/pre-push` into
     `<project>/scripts/git-hooks/` (this copy *is* tracked by git — it's the
     source the per-clone install step below copies from).
   - Copy `scripts/check-default-target.sh` into `<project>/scripts/`.
   - After cloning (every clone, since `.git/hooks/` is never tracked):
     ```bash
     cp scripts/git-hooks/pre-commit scripts/git-hooks/pre-push .git/hooks/
     chmod +x .git/hooks/pre-commit .git/hooks/pre-push
     ```
3. Register `SKILL.md` as a Claude Code skill (drop it at
   `.claude/skills/lean-econ-workflow/SKILL.md`, workspace- or project-level).
4. Wire in the `SessionStart` hook: merge `hooks/claude-code/settings.snippet.json`
   into `.claude/settings.json`, adjusting the `command` path to wherever you
   put `session-check.sh`. (The `update-config` skill, if available, can do
   this wiring for you.)
5. Create `memory.md`, `progress.md`, `plan.md` per the table in `SKILL.md`.

## Related skills

This package deliberately does three of the jobs a Lean-economics project needs
and leaves the rest to other tools/skills, so each piece can be adopted, updated,
or swapped independently:

| Concern | Handled by | Notes |
|---|---|---|
| Writing/debugging the Lean proofs themselves | [`lean4-skills`](https://github.com/cameronfreer/lean4-skills) plugin | External; this package's `SKILL.md` cites its `/lean4:*` commands rather than re-implementing them. |
| Live Lean/Lake process interaction (goals, diagnostics, search) | [`lean-lsp-mcp`](https://github.com/oOo0oOo/lean-lsp-mcp) | External MCP server; `mcp__lean-lsp__*` tools. |
| Multi-project session/phase orchestration | **this package** | Control files, START/RUN/END, git/Claude Code hooks. |
| Single-project proof-quality discipline (axiom hygiene, vacuity, linter blind spots) | `lean-harness` skill | Sibling skill, see `LESSONS.md`'s "Related, deliberately separate skills". |
| Preparing/auditing a project for Palomar-registry submission | `palomar-comparator` skill | Sibling skill; only relevant if the project is structured as a Palomar `Challenge`/`Solution`/`comparator.json` submission. |

## Keeping this in sync with the origin workspace

This package was extracted from a live workspace's `.claude/skills/lean-econ-workflow/`
and `scripts/git-hooks/`. If that workspace's workflow changes in a way that
isn't specific to its own project list, port the change here too — and vice
versa: a new incident anywhere is a candidate `LESSONS.md` entry regardless of
which copy it was found in.
