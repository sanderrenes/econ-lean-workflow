# lean-econ-workflow (portable package)

A Start→Run→End workflow for multi-project Lean 4 formalization efforts (originally
built for a workspace of economics-formalization projects — mechanism design,
welfare, game theory — but nothing here is economics-specific except the "Domain-
specific discipline" section of `SKILL.md`, which is written to be adapted).

This folder is a self-contained, generalized copy: no project names from its
origin workspace are hardcoded. Copy or symlink it into a new project/workspace
to adopt the workflow there.

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

## Keeping this in sync with the origin workspace

This package was extracted from a live workspace's `.claude/skills/lean-econ-workflow/`
and `scripts/git-hooks/`. If that workspace's workflow changes in a way that
isn't specific to its own project list, port the change here too — and vice
versa: a new incident anywhere is a candidate `LESSONS.md` entry regardless of
which copy it was found in.
