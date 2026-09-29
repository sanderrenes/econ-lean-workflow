# Lessons behind the lean harness

The postmortem record behind `SKILL.md`. Each rule that looks like overkill exists because
skipping it already cost real time in the workspace this package was extracted from — a set of
Lean 4 / Mathlib formalizations of mechanism design, welfare economics and game theory (revenue
equivalence and the taxation principle as one adjunction, Bayesian and open games, Sperner and
Brouwer, Palomar-registry submissions). Project names are left out; the mathematics is kept where
it is the lesson.

Format: **what happened → why nothing caught it → what catches it now** (or that nothing does).

---

## Statement-level failures (the kernel was happy; the statement was wrong)

### The transfer order that wouldn't close
Mechanisms `⟨q, t⟩` were ordered componentwise — the order a pair invites. The proof that the
transfer functor preserves order carried a `sorry` for a long time; nothing called it, so nothing
broke. Proving it needed the value function convex in the allocation: true for auctions
(`v = θ·a`), **false** for optimal taxation (`v = θ·h(y) − g(y/θ)`). Only quantifying over *both*
settings exposed the `sorry` as structural. Ordering by surplus instead (rent as the state
variable) needed only single crossing — and flipped the adjunction's direction, which had been
guessed wrong. **Caught by**: nothing automated. Zero-sorries kept the obligation alive; a human
read it as "the statement is wrong". → §1 rule 2, §2.

### The envelope transfer, defined wrongly twice
Version one hid a `sorry` inside a type (a subtype membership proof). Version two differentiated
along the diagonal (total derivative) where the partial with the allocation held fixed was
needed. Both fixes came from re-reading the mathematics, not from error messages: the kernel
checks the proof against the definition you wrote, and cannot see the definition isn't the
economics. → §5.

### The textbook hypothesis that excluded the case of interest
The envelope theorem's two-sided derivative hypothesis is standard. At a posted price with
reserve `p` — the canonical optimal auction — surplus is `max(θ − p, 0)`: a kink. The theorem
silently excluded every reserve-price auction. **Fix**: a one-sided derivative, plus
`postedPrice_not_hasDerivAt` as a theorem. **Caught by**: instantiating at the canonical example,
which nobody is forced to do. → §5.

### The vacuous adjunction
The adjunction quantified a Lipschitz and a continuity hypothesis over *every* object. Both fail
somewhere: a constant mechanism realizes every allocation level while `v = θ·a` is exactly
`|a|`-Lipschitz, and a left-continuous reserve auction is IC-IR yet breaks continuity at the
reserve. The theorem was true of an empty class. **Fix**: regular subcategories (conditions on
the allocation rule), an instance plus a witness object, and the failures stated as theorems
(`no_uniform_lipschitz`, `no_uniform_hW`). The `witnessless` linter machinery, previously unused,
became load-bearing. → §5, §4.

### Incentive compatibility used by no theorem
The envelope condition was *assumed*, so IC reached nothing until the IC ⇒ envelope bridge
(Milgrom–Segal) was built. Confirmed by deleting the IC sandwich lemma and watching the build
break. → §5 ("a hypothesis that makes the key assumption dead").

### Hypotheses kept "to document the setting"
Corollaries carried single-crossing and integrability hypotheses nobody used; transfer invariance
needs neither. Dropping them strengthened the statements. A reader assumes every hypothesis is
load-bearing. → §5.

### An unused typeclass dictated a modelling choice
`[AddCommGroup A]` and `[IsOrderedAddMonoid A]` sat on 27 declarations, used by no proof — a
leftover from a deleted field. They forced the allocation space to be ℝ instead of `[0,1]`, and a
docstring kept justifying the choice by the requirement. Found by asking how a probability of
winning could be an abelian group; removed and verified by deletion; `unusedArguments` flagged
1 of 27. → §4, §5.

### Theorems whose statement was `True`
Three "failure case" theorems were `: True := trivial`. They typechecked, appeared in the
declaration list, and made the file look like it covered failure cases. All 16 default linters
passed them. **Now**: rewritten as prose; `linter.trueStatement` (zero false positives over 132
declarations). → §4.

### Uniqueness by structure eta
"Existence and uniqueness" pinned the transfer to a formula inside an `∃!`, so uniqueness held for
any formula and used no IC. Now uniqueness goes through the envelope characterization. → §5.

### The label that wasn't the theorem
A statement comparing two mechanisms — never producing a tax schedule — was called "the taxation
principle", while the prose promised implementability by an income schedule; an equivalence of
categories carried the same label. Both had been treated as instances of one master theorem. The
taxation principle proper is one mechanism and IC alone; the rest was renamed. → §5, §7.

### Stated in expectation, proved pointwise
A result integrated against a finite measure that carried no hypotheses and did no work. The
conclusion is now pointwise; the expected-revenue form is a corollary. → §5.

### "This is a reasonable assumption", attached to a `sorry`
A stalled adjunction proof met a boundary mismatch; a draft assumed it away with exactly that
comment. The real cause was a reparametrization map in the morphisms; dropping it made the
categories thin and dissolved the problem, with the cost disclosed. → §2.

### A false general theorem, and the "missing lemma" that never existed
An abstract welfare-consistency theorem sat with two `sorry`'d lemmas for weeks as "accepted".
Its forward direction has a two-line counterexample (a constant welfare functional), and its
proof sketch cited a decomposition iso "available in `Equivalence.lean`" that had never been
written. **Resolution**: deleted, after grep *and* rebuild across all sibling projects showed
nothing depended on it; the counterexample recorded in `BLOCKERS.md`; the true restricted
version (quasilinear model) proved under its own name. → §2, §3 ("cited lemmas must exist").

### Tests that could not fail on the point of the project
Every committed example of a new equilibrium notion with *coupled* payoffs would have passed
against the *uncoupled* payoff shape an existing tool already supported. A coupled coordination
game was added, with the deviating player's payoffs (0 vs 11) asserted as numbers. → §5.

## Evidence failures (a plausible method, a clean wrong answer)

### Two dependency probes that returned tidy, wrong results
`ConstantInfo.value?` returned `none` for theorems, so a proof-term walk reported every dependency
unused, without erroring. A token scan missed anonymous-constructor and projection uses and showed
the sole premise of the main functor as an unused leaf. (On a later toolchain `value?` did return
`some` — tested, not assumed; re-test after every bump.) → §3.

### A dependency claim in four documents, measured at zero
README, statement file, proof file and metadata all said one submission depended on another.
Measured: zero shared constants; the real shape was a fan-out from one lemma. One of the four was
the auditable statement file. → §3.

### The language server served a stale environment
After a good build the LSP tool reported the old signature and dependency count; the warning was
easy to miss. → §3: trust `lake build`/`lake env lean`; re-test tools after toolchain changes.

### An orphaned module rotted behind green builds
A diagram module was imported by nothing — not even the library root — so `lake build` never
compiled it, and it silently broke when an upstream structure's fields were renamed. Its status
note meanwhile claimed "1 + 2 sorries" that no longer existed. **Now**:
`scripts/check-orphan-modules.sh` (pre-push). Running it across the workspace on adoption day
found five more files, in two projects, outside their own package's build — two compiled only
through a downstream package, three compiled nowhere (grep across every sibling project found
no importer). → §1 rule 1.

### "Complete, 0 sorries" — modulo three axioms
A proof summary listed the main characterization theorem as "✅ Complete, Sorries: 0" while both
directions rested on admitted axioms for the envelope theorem and the IC/IR steps. Zero `sorry`
tokens is not zero gaps. **Now**: `scripts/check-axioms.sh`, and the pre-commit hook blocks a new
`axiom`. → §1 rule 3.

### Two "fully delivered" claims, each missing a stated item
One phase was marked COMPLETE while its plan item "connect back to the real grid mechanism" and
the plan's own worked-example requirement were missing (the extension was parametrized by an
*assumed* monotonicity, never discharged from IC); a later "closes the entire plan" missed that
the mechanism was never actually built from the proved facts. Found by re-reading the plan's
wording against the code. → §3.

### The status file was five months stale
A project's memory file listed about a dozen theorems as `sorry`'d — including one since deleted
— months after they were done; another project's docs said a theorem was "stated with `sorry` for
now" long after it was proved. **Rule**: status in the same commit as the Lean (pre-commit nudge);
"done" is read from the build. *Still present on adoption day*: the audit script's escape-hatch
grep found that exact stale docstring still in place. → §3, §7.

## Prose failures (nothing reads a comment)

### A full comment audit of a submission repository
~25 drifted comments; a module header citing a lemma that doesn't exist; four references cited in
docstrings but in no bibliography; a companion note with ~40 `File.lean:NNN` references all ~100
lines stale, in a file whose preamble promised every claim was read off the stated location; a
header saying the left adjoint preserves colimits about the right adjoint; a docstring claiming
equal revenue "under any distribution" for a theorem concluding equal transfers. Every case
traced to a signature-changing refactor whose docstring was not re-read. **Now**: line-number
references blocked; changed declaration headers listed at commit; the rest is §7's read-through.

### "Economists believe allocating more means charging more"
A fluent, false sentence in a talk draft — economists don't compare transfers across mechanisms at
all. Caught by the researcher pressing on a sentence that sounded right. → §8: the model supplies
fluency, not judgement.

### Our own talk went stale
A finished talk was frozen on purpose. Follow-on Lean work overturned three of its claims ("the
adjunction has no consumer", "`T ⊣ Q` on all of **Mech**", "the equivalence is the taxation
principle"), and none was logged. A cold-started session rebuilt the state from four repositories;
a wrong claim could have gone into the next talk. The freeze did its job (no unrequested edit);
the logging half was skipped. **Now**: `frozen-guard.sh` blocks the edit; logging stays a
discipline. → §7.

### Merge-conflict markers committed into three files
A botched stash-pop left `<<<<<<<` in a README, a `lakefile.toml` and the root module. The cleanup
scan checked `.lean/.toml/.json`, not `.md`. A scan must name all files, not the ones you expect
to be affected. **Now**: pre-commit scans every staged file. → §10.

## Proof-engineering traps recorded along the way

Not harness rules — Lean facts that cost several compiler rounds each, kept so the next session
recognizes them. The `lean4` plugin is the place for general proving technique.

- `have h := by tac1; tac2` on one line parses as `have h := by (tac1; tac2)`: the `by` block
  swallows the following tactic. Break the line.
- A `Fin → ℕ → ℝ` cast chain does not reduce at `show`'s transparency; prove helper lemmas by
  `simp [defn]` and `rw` them in, rather than relying on defeq.
- `interval_cases` needs an explicit upper bound in context; derive it with `omega` first.
- Universe-polymorphic definitions may need an explicit `unfold` before `Iff.rfl` closes.
- `nlinarith` cannot see through an unexpanded opaque sum; expand or name it first.
- A sign error in a revenue/virtual-value identity was found by tracing by hand, not by the
  compiler — when many rounds of error-driven edits don't converge, re-derive on paper.

## Tooling faults found while building this package

- The workspace copy of `check-axioms.sh` parsed only the first line of `#print axioms` output.
  A list Lean wraps across lines would parse as empty and pass — the "clean, wrong answer" failure
  this harness warns about, in the harness itself. Fixed here by flattening the output first, and
  an unparseable answer now blocks instead of warning. (Tested against a stub printing a wrapped
  list; whether current Lean wraps a three-axiom list in practice was not tested.)
- The Palomar sorry-count rule, as first written ("= number of advertised theorems"), is wrong for
  a submission with a definition hole: that hole is `:= sorry` too. The invariant is
  `theorem_names` + `definition_names`.

---

## Coverage of the talk's "everything that went wrong" appendix

The talk ("Optimal Pricing is a Left Adjoint", TU Delft) lists its incidents under short codes.
Where each one is handled:

| Talk | Incident here | Handled by |
|---|---|---|
| A1 | The transfer order that wouldn't close | SKILL §1–2 (rule) |
| A2 | The envelope transfer, defined wrongly twice | SKILL §5 (rule) |
| A3 | An unused typeclass dictated a modelling choice | SKILL §4–5 (rule; deletion test) |
| B1 | The textbook hypothesis that excluded the case of interest | SKILL §5; `witnessless` |
| B2 | The vacuous adjunction | SKILL §5; `witnessless` |
| B3 | Incentive compatibility used by no theorem | SKILL §5 (deletion test) |
| B4 | Hypotheses kept "to document the setting" | SKILL §5 |
| C1 | Theorems whose statement was `True` | `linter.trueStatement` |
| C2 | Uniqueness by structure eta | SKILL §5 |
| C3 | The label that wasn't the theorem | SKILL §5, §7 |
| C4 | Stated in expectation, proved pointwise | SKILL §5 |
| C5 | "This is a reasonable assumption" | SKILL §2 |
| D1 | "Economists believe allocating more means charging more" | SKILL §8 |
| D2 | Docstring `= 0` vs definition `≥ 0` | SKILL §7; pre-commit nudge |
| D3 | Full comment audit | SKILL §7; pre-commit (line numbers, header nudge) |
| E1 | The status file was five months stale | SKILL §3; pre-commit nudge; lean-econ-workflow |
| E2 | A dependency claim in four documents | SKILL §3 |
| E3 | Two dependency probes, tidy wrong answers | SKILL §3 |
| E4 | The language server served a stale environment | SKILL §3 |
| E5 | Conflict markers in three files | pre-commit (all file types) |
| E7 | Our own talk went stale | `frozen-guard.sh` + SKILL §7 |
| F1 | Comparator `Const does not match` (proof auxiliaries) | `palomar-comparator` skill — submission format, not general Lean |
| F2 | Challenge files must contain `sorry` | SKILL §1 rule 2 (counted exception); `audit-completion.sh` |

The talk's hook table (appendix 3) also lists: *build clean and zero sorries at every commit* —
here the build runs at push, not commit, because a full `lake build` per commit is slow enough to
get bypassed; *advisory linters after every edit* — here they run at elaboration (compiler
warning) and `#lint`, not via an editor hook; *restated-declaration check between statement file
and development* — Palomar-specific, left to `palomar-comparator`; *the model never pushes* —
`hooks/claude-code/settings.snippet.json`.

## Open proposals (not built)

1. **`docstringIdentifiersResolve` linter** — warn when a backticked, declaration-shaped token in
   a doc-comment doesn't resolve in the environment. Would have caught the non-existent lemma in a
   module header and every name left dangling by a rename. Syntactic, cheap, advisory; not written
   yet because it needs a false-positive policy for prose words with underscores.
2. **`docstringCitationsListed` linter** — warn when `Author (YYYY)` in a doc-comment is absent
   from the module's `## References` block.
3. **Paper ↔ Lean citation check** — every `\texttt{decl}` / backticked name in a `.tex` or `.md`
   note resolves in the built environment. Done by hand for the companion notes; a script against
   `#check` output would make it repeatable.
4. **Periodic rebuild independent of push** (shared with lean-econ-workflow) — shrinks the window
   in which an orphaned or stale module can hide.
