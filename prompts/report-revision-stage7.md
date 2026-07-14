## Session: report-revision-stage7 (rebalance and reframe as standalone case study)
Date: 2026-07-14
Model: Claude Fable 5 (claude-fable-5)

### Prompts and Responses

**User:** Stage 7 — Rebalance and reframe the `study_small_report.qmd` so it reads as a
self-contained `ssdsims` simulation case study rather than a re-examination of the 2024
addendum. Three tasks: (1) reframe away from the addendum — strip "Analogue of the addendum's
Figure N" from captions, move the addendum comparison out of captions into prose, rewrite
Purpose/Scope and Background around the scientific + methodological question, reduce the
addendum-conclusions discussion to a few sentences in one place; (2) rebalance §6 (~40% of the
report) — move the two forensic tables (tbl-aicc-version, tbl-fit-rate) to a new appendix,
keep the mechanism + three figures + fitting-engine prose + irrecoverability + ccme_boron in
the body, and move tbl-source-reps to Methods (propose); (3) reuse the addendum's still-valid
interpretation in the report's own voice (diffuse weights at small n, gamma left-tail bias,
when the mixture legitimately earns weight, no distinct jump vs N). Do NOT re-run the pipeline
or change any number/conclusion/caveat. Verify HTML + docx render, cross-refs resolve.

**Claude:** Reframed and rebalanced `study_small_report.qmd` as a standalone case study.

Task 1 (reframe): Rewrote Purpose/Scope around the scientific question (minimum n for
reliable HC~x~; what the AICc criterion does at small n) plus the methodological
demonstration; Background now provides regulatory/scientific context (Fox 2024, addendum as
grey literature, Warne 2025) without sequel framing. Stripped every "Analogue of the
addendum's Figure N" from fig-3/fig-4a/fig-4b captions and rewrote them on the figures' own
terms. Moved the single addendum comparison out of the fig-4b caption/prose into one
consolidated place — a new short "Relation to the 2024 addendum" subsection at the end of
Findings stating the three points plainly (sharp N=5/N=6 step is substantially a criterion
artefact; the N=6 recommendation remains supportable; the earlier weights figure cannot be
reconstructed).

Task 2 (rebalance §6): Created "Appendix D — AICc degeneracy: version and fitting-engine
comparison" holding tbl-aicc-version and tbl-fit-rate with self-contained prose (what was
tested across ssdtools 1.0.6/2.0.0/2.6.0 and native/lenient profiles; invariance to version
and to computable/at_boundary_ok/min_pmix; N=5 mixture fit rate ~67%→~98%; references
aicc_degeneracy_reprex.R and the issue). §6 body keeps the mechanism (concise, with the
reprex), fig-4a/fig-4b/fig-3 with the near-zero-variance result, the fitting-engine
explanation in prose only (two headline rates as inline r expressions + pointer to Appendix
D), the irrecoverability paragraph (reframed as a reproducible-infrastructure argument), and
ccme_boron in two sentences. §6 fell from ~40% to ~30% of the body prose.

Task 3 (reuse addendum interpretation, in the report's voice): Added the diffuse-weights
reading of fig-4a at N≥7 (few observations can't discriminate distributions; weight
concentrates on the source as n grows); confirmed from bias_by_source_summary.csv that fig-3
still shows gamma-sourced data with by far the largest small-n bias (HC1 at N=5: 37.7 vs next
9.0) and stated it with the extreme-left-tail reading; stated the conditions under which the
mixture legitimately earns weight (genuine bimodality + large n, from N≥7 in fig-4b).

tbl-source-reps: moved to Methods as a "Source representation" subsection (recommendation —
easily reverted).

Fix required to render: the Stage 6 working-tree edits referenced inline hc1_bias_n5/n6/n10
without ever defining them, so the report had not rendered since Stage 6. Defined them in the
setup chunk from the committed summary CSV (HC1 median bias: +2.05 at N=5 etc.), matching the
values the prose intends. No number/conclusion/caveat changed.

Verification: `quarto render` exits 0; both study_small_report.html and study_small_report.docx
regenerate; 0 unresolved cross-references in either output; 5 figures and 7 tables renumber
correctly. Working tree clean (only the .qmd is a tracked change).

---
