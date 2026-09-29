---
name: lean-harness
description: >-
  Verification discipline for an LLM-driven Lean 4 formalization, within one project:
  the quality gate (build, zero sorries, standard axioms, no silent weakening), what
  counts as evidence about a codebase and what doesn't, linter blind spots, vacuity and
  the instantiate-at-a-canonical-example defence, statement-shape traps, the
  post-completion audit, and keeping docstrings/notes/papers faithful to the Lean. Use
  when writing, reviewing, or claiming "done" on Lean proofs — especially economics
  formalizations — or before a result goes into a paper, talk, or submission. Companion
  to lean-econ-workflow (multi-project session/phase orchestration, above this) and
  palomar-comparator (submission format, beside it); proof-writing itself is the lean4
  plugin's job.
---

# Lean harness — keeping an LLM-driven Lean project honest

> Portable companion to `lean-econ-workflow` (this repository's root `SKILL.md`). No project
> names are hardcoded. `LESSONS.md` in this folder holds the incidents behind every rule, in
> postmortem form; `scripts/` and `hooks/` mechanize the parts that a script can decide.
> Read `LESSONS.md` once before skipping a rule here — each one exists because skipping it
> already cost something.

**Where this sits.** `lean-econ-workflow` runs sessions and phases across projects (control
files, START/RUN/END, build-before-push). This skill is *inside* one project: is a proof, once
written, actually trustworthy, and does everything that describes it say what it proves?
`palomar-comparator` (if you use it) covers the Palomar Challenge/Solution submission format.
The actual proving — drafting, searching Mathlib, the compiler loop, golfing — belongs to the
`lean4` plugin (`/lean4:draft`, `/lean4:prove`, `/lean4:review`, ...) and the `lean-lsp` MCP.
Nothing here re-implements those.

---

## 0. Why this exists

An LLM writes Lean far better than it judges Lean. It knows the lemma names and the tactic
idiom. What it will not reliably do is **let a failure speak**. Chat models are trained to get a
task accepted as complete, and there are three ways to do that: finish the task, *simplify the
task*, or *get the human to accept a half-finished result*. Faced with an obligation that will
not close, the path of least resistance is the second or third — comment the block out, weaken
the statement until it compiles, report a dependency analysis that silently returned nothing.

Every one of those **destroys the finding**. In the originating project the most valuable object
in the repository was a `sorry` that would not close; it was not a proof gap but the formalism
refusing a wrong definition, and it became the main result (`LESSONS.md`, "the transfer order
that wouldn't close").

| Part | Job | Where it stops |
|---|---|---|
| **Model** | Translator: writes the Lean | Fluent and unreliable; makes failures go away |
| **Kernel** | Checks the proof against the statement | Cannot tell you the statement is the one you meant |
| **Linters** | Check the statement's shape | Caught 1 of 5 planted empty statements, 1 of 27 vacuous binders |
| **Git + hooks** | Keep every step and block the mechanical failures | Review is not automatable |
| **Researcher** | Goals, taste, the diagnosis | The only part that checks *meaning* |

The kernel is incorruptible about the question it is asked, and the author chooses the question.
**This harness guards that seam.** It is not a style guide; nothing in it is about pretty Lean.

---

## 1. The quality gate — every commit

1. **`lake build` clean, with a nonzero job count.** No errors. `(0 jobs)` means nothing was
   compiled (lean-econ-workflow's `check-default-target.sh`). A file no build root imports is
   never compiled either — `scripts/check-orphan-modules.sh`.
2. **Zero sorries.** If a proof needs a `sorry`, **the statement is wrong** until shown
   otherwise — fix the statement, or stop and say so (§2). The one exception is a Palomar
   `Challenge.lean`, and it is an exception *with a number*: its `sorry` count equals its
   advertised holes (`theorem_names` + `definition_names`). An unbounded "Challenge files are
   exempt" lets a stray `sorry` hide in a restated definition.
3. **Axioms are exactly `[propext, Classical.choice, Quot.sound]`** on everything advertised.
   A custom `axiom` is a `sorry` wearing a hat and needs explicit human approval;
   `native_decide` adds `Lean.ofReduceBool` and trusts the compiler, so keep it out of anything
   advertised. A status line "0 sorries, complete" on a theorem whose closure rests on admitted
   axioms is a false claim (`LESSONS.md`, "complete, modulo three axioms").
   `scripts/check-axioms.sh` mechanizes this.
4. **Never weaken a theorem to make it compile without saying so** — the weakening is the
   *headline* of the commit message, and it goes in `decisions.md` with the alternative rejected.

Rule 2 is the load-bearing one. A `sorry` typechecks; a quietly weakened theorem typechecks
*perfectly* and looks greener than the honest one. Neither is visible in a build log. **Zero
sorries is what turns "I could not prove this" into "this statement is false" — the only way a
formalization tells you something you did not already believe.**

---

## 2. When a proof will not close

- **First hypothesis: the statement is wrong**, not the tactic. Say so and stop before
  engineering around it. A `sorry` that resists closing across *genuinely different
  instantiations* (the auction setting and the tax setting, not two auctions) is the strongest
  version of this signal: quantifying over settings is what exposes a structural defect that
  any single setting is consistent with.
- **Never delete or comment out an obligation to make the build green.** Until proven
  otherwise it is the most valuable object in the repository.
- **Never close it with an unproved "reasonable assumption".** A draft that adds a hypothesis
  with a comment like "this is a reasonable assumption" is a weakening in disguise. Weaken the
  statement openly, or change the definitions so the problem dissolves, and disclose the cost.
- **If the general statement is false, prove the counterexample and keep the true
  restriction.** Record the false general form and its counterexample (in `decisions.md` /
  `BLOCKERS.md`), state and prove the restricted version, and only then decide whether the
  `sorry`'d general statement is deleted or kept — log that choice with its rejected
  alternative. Deleting is right when the statement is *false*, not merely hard, and after
  checking nothing depends on it (by deletion and rebuild, §3).
- **Suggested fixes are proposals, not decisions.** When blocked, the model will offer a way
  around the block. Whether that way preserves what the theorem was *for* is the researcher's
  call. It is also possible to have been given an impossible task; say so when that is the
  likeliest explanation.

---

## 3. Evidence: what may count as a fact about the codebase

**Never report a property of the codebase you have not tested.** The failure mode is not lying.
It is a plausible method returning a clean answer and nobody asking whether the method works. If
you cannot test a claim, say you have not tested it — "I have not verified this" is always
acceptable and is exactly what models are bad at offering.

Methods that returned **confident, tidy, wrong** answers in practice:

- **Proof-term walks built on `ConstantInfo.value?`** — returns `none` for theorems on some
  toolchains, so every dependency looks unused, without an error. Re-test on the current
  toolchain before trusting any closure probe.
- **Token/grep scans for uses** — anonymous constructors (`{ h := f.hAlloc }`), field
  projections (`m.hIC`) and instance resolution never name the declaration. A grep-built graph
  once showed the sole premise of the main functor as an unused leaf.
- **The language server / editor diagnostics** — served a stale environment after a good build
  (old signature, old dependency count), with a warning easy to miss. Trust `lake build` /
  `lake env lean <file>` over squiggles and over LSP answers after any `lakefile`, toolchain, or
  structure change; restart the server.
- **A cached build** — an up-to-date `.olean` can hide that the source no longer compiles against
  the current dependencies. Before a completion claim, rebuild with the package's own outputs
  deleted (`scripts/audit-completion.sh --clean`).
- **A status file** — "done" is checked against the build, not the log. Status files in these
  projects have claimed sorries months after they were proved, "0 sorries" on files never
  compiled, and "phase COMPLETE" while the plan's own items were missing.

**The reliable test is deletion.** Comment the declaration (or binder, or hypothesis) out, run
`lake build`, see what breaks. It cannot lie. Use it before claiming anything is unused,
load-bearing, vacuous, or safe to remove — and before claiming one result depends on another
(a dependency asserted in four documents once had zero shared constants when measured).

**Cited lemmas must exist.** Before relying on a comment that says "the missing piece is
available in `X.lean`", grep for it and confirm it compiles. Aspirational comments read exactly
like documented fact.

**Completion claims are checked against the plan's own wording**, item by item, not against a
summary of it. Two "fully delivered" claims in one project were each missing an item the plan
stated explicitly (a connection back to the real structure; a worked example the plan's
verification section asked for).

---

## 4. Tooling — what it catches, and exactly what it does not

```
lake build                        # errors, elaboration warnings, sorry warnings
lake exe runLinter <YourLib>      # Batteries environment linters, whole library (advisory)
#print axioms <decl>              # axiom hygiene (scripts/check-axioms.sh)
#lint                             # per-file; runs env linters incl. witnessless
```

**Measured blind spots** (test results, not impressions):

- `unusedArguments` catches vacuous binders on `def`s only — **never on `structure`s,
  `instance`s or `theorem`s**, which is where definitions live. It caught 1 of 27. A *chain*
  hides itself: `[AddCommGroup A]` was load-bearing for `[IsOrderedAddMonoid A]`, which was
  load-bearing for nothing; only removing the outer link exposes the next.
- Of five planted empty statements the default linters caught one:

  | Planted | Caught |
  |---|---|
  | `theorem foo (n : ℕ) : n = n := rfl` | yes — `synTaut`, literal `e = e` only |
  | `theorem foo : True := trivial` | **no** |
  | `(h1 : n < 3) (h2 : 5 < n) : n = 42` (contradictory hypotheses) | **no** |
  | a theorem carrying a hypothesis it never uses | **no** |
  | `(h : 0 < n) : n = n ∨ n ≠ n` | **no** |

**Every automated check checks syntax. Every real failure was semantic.** Nothing checks a
statement's meaning, and nothing reads a comment. That gap is the work.

### Two advisory linters — `lean/Linters.lean`

Self-contained (imports `Lean` and `Batteries.Tactic.Lint` only). Copy it into the library and
import it from the base module; a linter only runs in files that import it.

- **`linter.trueStatement`** — compiler warning on any declaration whose conclusion is `True`
  after stripping `∀`s. Zero false positives over 132 declarations in the originating project.
  Opt out per declaration: `set_option linter.trueStatement false in`.
- **`witnessless`** — `@[env_linter]` reporting theorems tagged `@[needs_witness]` with no
  `@[witness_for thm]` declaration. It does not detect vacuity (undecidable); it checks the
  weaker honest thing — you said a witness was owed and have not produced one.

**Both advisory on purpose.** A `True` statement is occasionally an honest placeholder; a gate
that cannot always be obeyed gets disabled wholesale, taking the signal with it. "Zero sorries"
can be a gate because a `sorry` is never right.

### CI

`lake new ... math` scaffolds `.github/workflows/`: `lean_action_ci.yml` (build on every push/PR —
the one check on a machine you don't control; keep it), `update.yml` (manual Mathlib bump; leave
`schedule:` off unless you want unattended bumps), `create-release.yml`. CI reconfirms rule 1
only. With a local path dependency on a sibling repo, CI needs one checkout per dependency into
the matching relative path.

---

## 5. Statement checks — where the real failures were

These are the traps that compiled cleanly, passed every linter, and were found only by someone
reading the statement and asking what it said.

**Instantiate the headline theorem at the object the field actually cares about, and prove that
object satisfies every hypothesis.** An envelope theorem stated with the textbook two-sided
derivative excluded every reserve-price auction — the canonical optimal auction has surplus
`max(θ − p, 0)`, a kink. Nobody is forced to check canonical examples, which is why this
survives in published work. **Force it**: tag the theorem `@[needs_witness]`, prove the witness
`@[witness_for]`, and prove the *failure* too when the textbook form excludes the case
(`postedPrice_not_hasDerivAt` became a theorem). A theorem about an empty class of objects
proves nothing; "satisfiable" must be a theorem, not an assumption.

Then check each of these against the statement *as `#check` prints it*:

| Trap | What it looked like | The check |
|---|---|---|
| **Hypotheses quantified over every object** | An adjunction assumed a Lipschitz bound and a continuity condition for *every* mechanism; both provably fail somewhere in the class, so the theorem was about the empty set. | Put conditions on the thing that varies (the allocation rule), not universally over objects; prove the failure (`no_uniform_…`) as a theorem. |
| **A hypothesis that makes the key assumption dead** | An envelope condition was *assumed*, so incentive compatibility itself was used by no theorem. | Delete the economically central hypothesis and rebuild: if nothing breaks, the theorem does not use it. |
| **Unused hypotheses "to document the setting"** | Corollaries carried single-crossing and integrability hypotheses nobody used. A reader assumes every hypothesis is load-bearing. | Remove by deletion-and-rebuild; dropping one *strengthens* the theorem. |
| **An unused typeclass dictating the model** | `[AddCommGroup A]` on 27 declarations, used by no proof, forced the allocation space to be ℝ instead of `[0,1]` — found by asking how a winning probability could be an abelian group. | Every binder earns its place by deletion. Ask what each typeclass *says* about the economic object. |
| **Uniqueness by structure eta** | An `∃!` pinned the transfer to a formula inside the witness, so uniqueness held for any formula and used no incentive compatibility. | Ask what the uniqueness is *through*; it must go through the model's constraints. |
| **Expectation vs pointwise** | A result integrated against a finite measure that carried no hypotheses and did no work. | State the strongest form (pointwise) and derive the expected form as a corollary. |
| **A label that is not the theorem** | A two-mechanism comparison was named "the taxation principle", and never produced a tax schedule; an equivalence of categories carried the same label. | The name, docstring and conclusion must match the literature result at that strength. |
| **Total vs partial derivative; `sorry` inside a type** | An envelope transfer differentiated along the diagonal where the partial (allocation held fixed) was needed; an earlier version hid a `sorry` in a subtype membership proof. | Re-derive the definition from the maths, not the error messages. The kernel saves you from an invalid proof of the theorem you wrote, not from proving the wrong theorem. |
| **Tests that miss the point** | Every committed example of a coupled-payoff equilibrium would have passed against the *uncoupled* payoff shape the project existed to go beyond. | At least one test must exercise the feature that is the project's reason to exist, with the discriminating number asserted, not just a Bool. |
| **A predicate everything satisfies** | — (checked for, and found absent, in a Sperner audit) | Show each defined condition is *real*: an object that fails it (a constant labeling is not rainbow). |

---

## 6. Before claiming "done": the completion audit

A "0 sorry, build green" claim can be hollow in four ways: stale artefacts, hidden escape
hatches, vacuous truth, and a perfectly checked proof of a subtly different statement. Before
the claim goes into a status file others rely on, a paper, a talk or a submission:

1. `scripts/audit-completion.sh --clean` — escape-hatch grep, Palomar sorry count, orphaned
   modules, rebuild from deleted outputs with job and sorry-warning counts, axioms.
2. **Non-vacuity** — construct an inhabitant of each hypothesis set (§5), and show each defined
   predicate is a real condition.
3. **Faithfulness** — read the statements as Lean elaborates them. Where feasible, transliterate
   the definitions into an independent script that reuses no Lean reasoning and brute-force the
   statement on small cases; a structural sanity check (e.g. a triangulation's cell count must
   be `kⁿ`) catches a degenerate encoding that random cases would not.
4. Write it up with `templates/VERIFICATION.md.template`, including how to reproduce it.

The mechanical half takes a minute. Steps 2–3 are the point.

---

## 7. Prose: where the economics lives, and nothing checks it

In an economics formalization the Lean signature carries little of the content; "single crossing
makes `T` a functor", "IR orients the adjunction", "this is Myerson's Theorem 2" all live in
docstrings, module headers and notes. **The comment↔code correspondence is the economics↔Lean
correspondence, and it has no gate.** One audit of a submission repository found ~25 drifted
comments, a module header citing a lemma that never existed, four references cited in docstrings
but in no bibliography, a header saying the *left* adjoint preserves colimits about the right
adjoint, and a companion note whose ~40 `File.lean:NNN` references were all ~100 lines stale.

- **Signature changed ⇒ re-read its docstring in the same commit.** Every drifted comment in
  that audit traced to a signature-changing refactor whose docstring was not re-read. Weakening a
  hypothesis and leaving the docstring describing the old one is a silently weakened theorem in
  prose. (The pre-commit hook lists changed declaration headers as a nudge.)
- **Name declarations, never line numbers**, in any prose (notes, plans, papers, talks). A stale
  line number still looks precise. (Blocked by the pre-commit hook.)
- **Provenance agrees in four places**: informal source → docstring → Lean signature →
  machine-readable metadata (`formalization.yaml` or equivalent). When a docstring gains a
  citation, the bibliography gains it in the same commit; when an advertised declaration is
  added, renamed or promoted, the metadata, README result table and module "main declarations"
  list move with it.
- **Every declaration a paper or note cites is grep-verified to exist** (exact name, including
  Unicode subscripts) before the document circulates; theorem numbers are checked against the
  compiled PDF, not the source.
- **Semantic read-through** — does each paragraph describe what the theorem proves, *at that
  strength*? ("…hence the same expected revenue under any distribution" on a theorem concluding
  pointwise transfer equality; "`q` is monotone **and** `t = …`" when only the formula is
  concluded.) Do it at draft time, after any signature-touching refactor, and as a periodic sweep
  (`/lean4:review` is read-only and suited to it). Not mid-proof.
- **Presentation artefacts are frozen.** A finished talk or paper is an argument, not a living
  document: do not "bring it up to date" unasked. When the Lean overtakes one of its claims,
  **log the divergence the day it appears** in the TODO/status file and leave the artefact alone.
  `scripts/frozen-guard.sh` blocks the edit; nothing checks the logging half.
- **Decision log: record the rejected alternative, before implementing.** A decision without its
  discarded alternative is a description, and the next cold-started session will re-litigate it;
  a log written afterwards is a rationalization.

---

## 8. The division of labour — state it honestly

In the originating project the model did **not** discover that the definition was wrong. It
**could not close the obligation**, and the harness forbade pretending otherwise. *Then* the
human worked out why, and the why was a domain insight the model did not have. **The machine
supplied the obstruction; the human supplied the diagnosis.** Taste is fallible too — the first
guess at the adjunction's direction was wrong, and an unarguable obligation corrected it, not a
feeling. Say it that way: the interesting claim is never "the AI proved a theorem", it is that a
formalization refused a definition nobody had been asked to justify.

---

## 9. Standing instructions to the agent

- When a proof will not close, first suspect the statement. Say so and stop.
- Never delete or comment out an obligation to make a build green.
- Never report a codebase property you have not tested; prefer deletion-and-rebuild. Say which
  part you did not test.
- Never silently weaken. If the statement shrank, that is the commit message's headline.
- When a signature changes, re-read its docstring and the prose that cites it, same commit.
- Never mark done from the log; mark done from the build — and from the plan's own wording.
- Commit at the end of every unit of work, never mid-phase with a broken build; the message
  states what changed *and what it cost*.
- **The agent does not push.** The human authorizes `git push` (permission rule; see
  `hooks/claude-code/settings.snippet.json`).

---

## 10. What is a hook and what is judgement

A hook is worth having when the check is mechanical **and** low-false-positive. The rest stays a
rule, because a script cannot make the call.

| Mechanized (a script decides) | Where |
|---|---|
| Build green with nonzero jobs | lean-econ-workflow `pre-push` + `check-default-target.sh` |
| No undocumented new `sorry` | lean-econ-workflow `pre-commit` |
| No new `axiom` / `admit` / `sorryAx` / `debug.skipKernelTC`; warn on `native_decide`, `implemented_by`, `unsafe`, `opaque` | `hooks/git/pre-commit` |
| Merge-conflict markers in *any* staged file | `hooks/git/pre-commit` |
| No `File.lean:NNN` references in prose | `hooks/git/pre-commit` |
| Frozen artefacts not edited | `hooks/git/pre-commit` → `scripts/frozen-guard.sh` |
| Nudge: changed declaration headers → re-read docstrings; `.lean` staged without the status file | `hooks/git/pre-commit` (advisory) |
| Every library file compiled by the package's own build | `hooks/git/pre-push` → `scripts/check-orphan-modules.sh` |
| Standard axioms on advertised targets | `hooks/git/pre-push` → `scripts/check-axioms.sh` |
| Statements whose conclusion is `True`; owed witnesses | `lean/Linters.lean` (advisory) |
| The agent never pushes | Claude Code permission rule |

| Judgement (a rule, because no script can decide) | Section |
|---|---|
| A `sorry` that will not close means the statement is wrong | §2 |
| Never weaken silently; no "reasonable assumption" hypotheses | §1, §2 |
| Deletion is the only dependency test; say what you did not test | §3 |
| Instantiate at the canonical example; prove hypotheses hold there | §5 |
| Statement-shape traps (quantification, uniqueness, expectation, labels) | §5 |
| Docstring and prose say what is proved, at that strength | §7 |
| Log decisions with the rejected alternative, before implementing | §7 |
| Log every divergence from a frozen artefact the day it appears | §7 |

---

## 11. Adopting this in a project

Files (copy; the project's copies are tracked):

| From here | To the project |
|---|---|
| `hooks/git/pre-commit` | `scripts/git-hooks/harness-pre-commit` |
| `hooks/git/pre-push` | `scripts/git-hooks/harness-pre-push` |
| `scripts/*.sh` | `scripts/` |
| `lean/Linters.lean` | `<YourLib>/Linters.lean`, imported from the base module |
| `templates/VERIFICATION.md.template` | `VERIFICATION.md` when you run the audit |

- **With lean-econ-workflow**: its `pre-commit`/`pre-push` call the `harness-*` hooks when they
  exist, so the normal install (`cp scripts/git-hooks/pre-commit scripts/git-hooks/pre-push
  .git/hooks/`) covers both; `pre-push` runs the harness only after a green build.
- **Without it**: install `harness-pre-commit`/`harness-pre-push` as `.git/hooks/pre-commit`/
  `pre-push` directly, and run `lake build` yourself before pushing (the harness pre-push does
  not build).
- **Opt-in configuration**: `scripts/axiom_targets.txt` (`<Module> <decl>` per line; a Palomar
  `comparator.json` is used automatically if present), `scripts/frozen_paths.txt` (one glob per
  line).
- **Claude Code**: merge `hooks/claude-code/settings.snippet.json` (denies `git push` to the
  agent).
- **New project order**: scaffold (`lake new <pkg> math`); pin `lean-toolchain` and the Mathlib
  `rev` to the *same* release; set the default target; install hooks; copy the linters; get the
  gate green on a trivial declaration (`lake build`, `#print axioms`, `runLinter` triaged to
  zero or a written accepted list, CI green) **before** real work. A gate adopted after the mess
  exists is a gate that gets waived.
