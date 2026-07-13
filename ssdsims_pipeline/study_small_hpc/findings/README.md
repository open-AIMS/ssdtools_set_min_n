# Investigation findings — the provenance trail for §6

These memos record the read-only **Stage 0** and **Stage 0b** investigations that
established the facts the report's *"What the pipeline surfaced: the AICc
degeneracy"* section (§6) rests on. They were investigation-only outputs — no
pipeline or report files were changed while producing them — and originally lived
only in working notes / chat transcripts. Because the report's central argument is
about *lost analysis provenance*, they are committed here so the evidence for the
report's claims is part of the repository rather than an un-recoverable transcript.

The empirical claims in `stage0-aicc-degeneracy.md` are now reproducible from
[`../aicc_degeneracy_reprex.R`](../aicc_degeneracy_reprex.R), which writes
`../aicc_version_comparison.csv` and `../aicc_fit_rate_comparison.csv`; the tables
in that memo are read directly from those CSVs. The provenance and metadata facts
in `stage0b-provenance.md` are reproducible from `../make_dataset_weights.R` and the
committed per-source CSVs.

| Memo | Establishes |
|---|---|
| `stage0-aicc-degeneracy.md` | The AICc small-sample degeneracy of the 5-parameter mixture; its invariance to `ssdtools` version and fit arguments; and the fitting-engine change that made a latent defect dominant. |
| `stage0b-provenance.md` | The single-source sampling design; the irrecoverability of the 2024 addendum's Figure 4; and the `ccme_boron` rounding-then-argmax metadata bug. |
