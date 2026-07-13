## Session: study_small_hpc report revision — Stage 4 (Findings & recommendations)
Date: 2026-07-13
Model: Claude Fable 5 (claude-fable-5)

### Stage 4 scope

Write §8 (Findings and recommendations), which Stage 3 left as a placeholder, and
update `ssdtools-aicc-issue.md` with the Stage-0 fitting-engine evidence. Content
only — NOT a style/tone pass (Stage 5), NO pipeline re-run. Every quantity in §8 is
an inline `r` expression over a committed CSV or a value already established in the
report; no hardcoded numbers.

### Prompts and Responses

**User:** [Stage 4 instructions — Task 0 numerical check, Task 1 marginal-value of N,
Task 2 write §8 (four subsections), Task 3 update the AICc issue.]

**Claude:**

**Task 0 (numerical check).** Confirmed the two ~0.95 quantities are read from
distinct sources and are not conflated in the prose:
- `mix5` = 0.9545 = the *mean re-fitted AICc weight* of `lnorm_lnorm` at N=5, computed
  inline via `weighted.mean(mean_weight, n_datasets)` over `source_weights_summary.csv`
  (rounds to 0.95 in prose at lines 364/409).
- 95.5% = 78,272/82,000 = the *collapse rate* — the fraction of N=5 model-averaged fits
  in which the mixture is the argmax weight. Reproduced exactly from
  `fit_weights_observed.csv`: 19,568 of 20,500 N=5 fits have the mixture dominant
  (= wt > 0.5), 0.95454; ×4 HC proportions = 78,272/82,000.
  They coincide to 6 d.p. because at N=5 the mixture weight is essentially binary (≈0
  when the mixture fails to fit, ≈1 when it fits and the −60 reward wins), so its mean
  equals the fraction of dominated fits — a mechanistic coincidence, not a derivation
  of one from the other. In the prose they appear side-by-side (line 409) as two
  distinct facts and are never substituted for one another.

**Task 1 (marginal value of N).** Computed per-species marginal coverage gains and
relative-CI-width reductions across the N grid (full BCANZ run) and for the mixture-
excluded `study_small_nomix` run (N ∈ {5,6,7,8}). Full-BCANZ per-species coverage gain:
5→6 +22.2 pts (artefact-inflated), 6→7 +1.5, 7→8 +1.0, 8→10 +0.7, 10→16 +0.2,
16→26 +0.04 — sharply diminishing, and the large 5→6 figure is the AICc criterion
switching regimes, not sample size (nomix 5→6 gain is only +1.7 pts/species, comparable
to its 6→7 +1.7). Mean coverage never reaches the nominal 0.95 at any N (max mean 0.936
at N=26; max per-cell 0.941). CI-width reduction per species also diminishes
monotonically (−38%/species at 5→6 down to −3%/species at 16→26). Conclusion the data
support: **no change to the Warne et al. (2025) minimum of 6.** Coverage does not reach
nominal at any N tested; residual under-coverage is a bootstrap property, not fixable by
N; the nomix run only spans N∈{5,6,7,8}; and the 2024 addendum's null result ("no
distinct jumps … no clear criteria") still holds. Reproducing the null is a finding.

**Task 2 (write §8).** Four subsections, all numbers inline:
- 8.1 The AICc small-sample degeneracy — general rule n ≥ k+2; mixture degenerate at
  both N=5 (rewarded to ≈1) and N=6 (AICc=+Inf, weight 0); meaningful only from N≥7.
- 8.2 The consequence at the current guideline minimum — at N=6 the mixture is in the
  candidate set, appears in `glance()`, contributes exactly zero weight, no warning; a
  bimodal dataset cannot be flagged bimodal at the guideline minimum; the zero is a
  division-by-zero landing in a safe place, not a considered exclusion.
- 8.3 Implications for the minimum sample size — marginal-value table + prose: the sharp
  N=5/6 step is substantially a criterion artefact; N=6 minimum remains supportable but
  the sharp evidence does not say what it was taken to say; under-coverage persists to
  N=26; recommend no change.
- 8.4 Recommendations to `ssdtools` — per-distribution AICc guard (`nobs < npars + 2`
  → `AICc = Inf/NA`, optional message), cite the filed issue; note the global `nrow>=6`
  guard is blunt and re-exposed by any workflow lowering `nrow`.

**Task 3 (update AICc issue).** Added the fitting-engine evidence from Stage 0: the AICc
formula is byte-identical across ssdtools 1.0.6/2.0.0/2.6.0 (not a regression); what
changed is the fit engine (mixture fitted at n=5 ~60% under 1.0.x vs ~97% under 2.x;
mean mixture weight ≈0.60 → ≈0.97); version × arguments × weight table from Stage 0;
varying `computable`/`at_boundary_ok`/`min_pmix` does not drop the degenerate n=5 fit in
any version. Conclusion stated: a latent criterion defect became a dominant one because
the optimiser improved.

**Verification:** `quarto render study_small_report.qmd` succeeds; §8 contains no
hardcoded numbers (all inline `r`); citations resolve.

---
