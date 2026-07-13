## Session: study_small_hpc report revision — Stage 3 (restructure & rewrite, content only)
Date: 2026-07-13
Model: Claude Fable 5 (claude-fable-5)

### Stage 3 scope

Content-only restructure and rewrite of `study_small_hpc/study_small_report.qmd`:
reorganise into the Stage-3 outline, add per-source figures from committed
artifacts, add Purpose/Background sections so the report stands alone, replace the
factually broken "Refitted vs. true distribution weights" section, and land the
central irrecoverability framing. NOT a style/tone pass (Stage 5) and NOT a
recommendations rewrite (Stage 4). No pipeline re-run — every figure derives from
committed CSVs.

Settled facts carried in from Stage 0/0b (see instructions): sampling is
single-distribution per dataset; the AICc degeneracy is long-standing (byte-identical
across ssdtools 1.0.6/2.0.0/2.6.0), what changed is the fitting engine (~60% mixture
fits at n=5 in the 2024-era engine vs near-universal now); the 2024 Figure 4 cannot
be reconstructed (original code lost); the `ccme_boron` metadata bug was a
rounding-then-argmax error, not a genuine tie.

### Prompts and Responses

**User:** [Stage 3 instructions — restructure and rewrite the report, content only.]

**Claude:** Restructured and rewrote `study_small_report.qmd` (content only, no
style pass, no pipeline re-run).

- **New sections written:** *Purpose and scope* (with the author-role note from the
  Stage-1 TODO), *Background* (recommendations #5/#6 read from
  `Images/original_recommendations.png`; the ANZG minimum of 5, the ssdtools v1.0 /
  BC minimum of 6, the current ANZG minimum of 6 — all cited), and *The `ssdsims`
  pipeline* (targets/crew.cluster design, sharding, reproducibility/provenance/
  portability). *Methods* now states the single-source design correctly, fixes the
  `\widehat{\text{HC}}_x` rendering, and states what is and is not replicated from
  the addendum (41 ssddata datasets, not the 353-dataset EnviroTox corpus).
- **Broken section removed:** deleted *Refitted vs. true distribution weights* and
  its observed-vs-true scatter (premised on a non-existent weight-vector truth).
  The AICc mechanism explanation (−60 correction, $n \ge k+2$) was kept and moved
  under the new *What the pipeline surfaced: the AICc degeneracy* framing.
- **New figures (all from committed CSVs, plotted inline):**
  Fig 4A analogue (source-distribution weight vs N, faceted by source) and
  Fig 4B analogue (lnorm_lnorm weight vs N, faceted by source) from
  `source_weights_summary.csv`; Fig 3 analogue (median relative bias vs N, faceted
  by source) from `bias_by_source_summary.csv`. Facet labels carry `n_datasets` so
  the thin panels (esp. the single-dataset lnorm_lnorm source) are flagged in the
  plots. Inline mixture-weight numbers (0.95 across 41 datasets; 0.96 unimodal-only
  at N=5) computed from the CSV, matching the report's existing 95.5% figure.
- **Central framing (Task 4):** the AICc degeneracy is long-standing (byte-identical
  across ssdtools 1.0.6/2.0.0/2.6.0) but became near-universal under the current
  fitting engine (~95% at N=5 vs ~60% in the 2024-era engine); the original Figure 4
  cannot be reconstructed because the original code is lost, so the discrepancy is
  reported as unresolved — the irrecoverability being the argument for the pipeline.
  Explicitly not softened to "caught a bug" nor overstated as a defect. The
  `ccme_boron` rounding-then-argmax metadata bug added as a second small illustration.
- **Restructure:** outline sections 1–11 in order; *Findings and recommendations*
  left as a heading placeholder for Stage 4; Appendices A/B via `{{< include >}}` of
  the HPC and WSL runbooks; Appendix C carries the run-diagnostics section, the
  WSL-cost table, and the reproduce-diagnostics subsection unchanged. All bracketed
  cross-references updated to the new headings.

`make_report_outputs.R` was not changed — it already writes the two per-source CSVs
(Stage 1), and the established pattern is CSV-in-script / plot-inline-in-qmd, so the
new figures are plotted inline like the figure they replace.

**Verification:** `quarto render study_small_report.qmd` succeeds; all five bracketed
cross-references resolve to real headings (confirmed by `href`/`id` in the HTML); 14
CSL bibliography entries render with no broken citation placeholders; both runbook
includes render under their appendix headings; no hardcoded numbers introduced in
prose (all quantities are inline `r` expressions over committed CSVs or values
already present in the report).

---

