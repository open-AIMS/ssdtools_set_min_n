## Session: study_small_hpc report revision — Stage 1 (scaffolding & data artifacts)
Date: 2026-07-13
Model: Claude Fable 5 (claude-fable-5)

### Context from Stages 0 and 0b (investigation-only, not logged at the time)

Stages 0 and 0b were read-only investigations of the `study_small_hpc` report and
its artifacts; no files were changed, so no prompt log was created. Their
conclusions, carried into this stage:

- **Stage 0** reviewed `study_small_report.qmd` and its committed inputs and
  confirmed the report renders from committed CSVs/PNGs (the heavy
  `summary.parquet`, `cache/`, and `fit_weights_observed.csv` are git-ignored).
- **Stage 0b** found a provenance mismatch: `dataset_aicc_weights.csv` labels
  `ccme_boron`'s source distribution as `gamma`, whereas `cache/true_hc.rds`
  (what `ssd_gen()` actually sampled from) labels it `weibull`. Cause: a
  rounding tie — gamma and weibull both round to 0.357 in the 3-dp CSV — broken
  toward `gamma` by `which.max()` over the CSV's column order, while
  full-precision `glance()` (weibull 0.35747 > gamma 0.35657, diff ~9e-4)
  breaks toward `weibull`. Stage 0b also established that the 2024 addendum's
  per-source Figures 3 and 4 can be reconstructed from existing artifacts.

### Stage 1 scope

Scaffolding and data artifacts only — no report restructure or prose rewrite
(that is Stage 3). Tasks: session log (0); reconcile the `ccme_boron` tie and
regenerate `dataset_aicc_weights.csv` at full precision (1); committed derived
CSVs for the per-source figures (2); bibliography + YAML wiring (3); factual
fixes in `min_sample_size.Rmd` and the Warne 2025 citation (4); a WSL workflow
runbook + include-safety for both runbooks (5); a Stage-3 TODO placeholder (6).

### Prompts and Responses

**User:** [Stage 1 instructions — see scope above.]

**Claude:** Executed Tasks 0–6, one commit per task. Details appended below as
each task completes.

---
