## Session: study_small_hpc report revision — Stage 4c (Tighten and commit the forensics)
Date: 2026-07-13
Model: Claude Fable 5 (claude-fable-5)

### Stage 4c scope

Tighten the committed AICc forensics from Stage 4b and commit both stages.

Tasks:
1. Raise the Monte Carlo in `aicc_degeneracy_reprex.R` from 150 to 1,000 replicates;
   report a binomial CI alongside each rate in `aicc_fit_rate_comparison.csv` and
   surface it in the rendered table.
2. Remove the provisional ~60% / ~97% figures (from a lost scratch run) from the
   report and issue entirely; quote only CSV-derived numbers.
3. The irreproducibility of those provisional figures is worth at most one clause;
   do not make a set-piece of it.
4. Verify `AICc ≈ 116.2` at n = 7 in `aicc_version_comparison.csv` matches the
   issue's "~116 on a natural 7-point extension"; fix the issue wording if the
   reprex uses a different 7-point dataset.
5. Commit Stage 4b and 4c in logical commits; confirm the render.

### Prompts and Responses

**User:** [Stage 4c instructions — see scope above.]

**Claude:**

**Task 1 (1,000 replicates + CIs).** Set `n_mc <- 1000L`. In experiment b, added a
Clopper-Pearson exact binomial 95% CI (base R `binom.test`, no new dependency) on
both the fitted rate and the win rate, written to new CSV columns
`present_ci_lwr/upr` and `wins_ci_lwr/upr`. Re-ran the reprex (deterministic,
`set.seed(42)`). New figures: 1.0.6 native 67.4% (95% CI 64.4–70.3), 1.0.6 lenient
68.0% (65.0–70.9), 2.0.0 / 2.6.0 native 97.9% (96.8–98.7); mean weights 0.674 /
0.680 / 0.979. Surfaced the CI in the report's fit-rate table (each rate now shows
"67.4 [64.4, 70.3]") and in the prose via inline `r`.

**Task 2 (remove provisional figures).** The report and issue already read the
fit-rate numbers from the CSV via inline `r` and a rendered table (Stage 4b), so no
`~60/~97` literals remained there; the only survivors were the reprex header comment
(lines 26–27), now reworded to point at the CSV rather than quote a stale number.
Updated the issue's hardcoded fit-rate table and the `findings/stage0-aicc-degeneracy.md`
memo to the 1,000-replicate CSV numbers with CIs. All quoted fit-rate figures are now
CSV-derived.

**Task 3 (register).** Added nothing self-referential about the provisional numbers'
irreproducibility. The report's §6 already carries the irrecoverability argument via
the addendum's Figure 4 and the `ccme_boron` rounding-then-argmax example; a third
instance would be laboured. Left at zero clauses (within "at most one").

**Task 4 (n = 7 consistency).** Confirmed consistent. The reprex's 7-point dataset is
`c(0.1, 0.3, 1, 3, 10, 30, 100)`, which the issue prose names explicitly; its AICc is
116.16–116.18 (native/lenient) → rounds to the 116.2 the issue quotes. Experiment a
is deterministic and unaffected by the replicate count, so this CSV was unchanged. No
wording fix needed.

**Task 5 (commit + render).** Committed Stage 4b/4c in logical commits (reprex + CSVs;
findings memos; report + issue wiring; prompt logs). `quarto render` succeeds (exit 0);
the rendered HTML carries the new CI table, the CI prose, and the 1,000-sample count.

---
