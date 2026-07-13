# Stage 0b finding — sampling design, Figure 4 irrecoverability, and the ccme_boron tie

> **Investigation-only output.** This memo records a read-only investigation; no
> pipeline or report files were changed to produce it. It establishes provenance
> facts the report's §6 rests on. The sampling-design and metadata facts are
> reproducible from [`../scenario.R`](../scenario.R) and
> [`../make_dataset_weights.R`](../make_dataset_weights.R) against the committed
> per-source CSVs and the (git-ignored) `cache/`.

## The sampling design is single-source, not a mixture of sources

Each of the 41 `ssddata` datasets is resampled from **its own top-AICc-weighted
BCANZ distribution** — its "source" distribution — not from a mixture and not from a
pool of sources. `ssd_gen()`, given a multi-distribution `fitdists` object, selects
the top-weighted distribution and draws from it (see `scenario.R` and `?ssd_gen`).

This matters for reading §6: at N = 5 the `lnorm_lnorm` mixture receives near-unit
re-fitted weight **across all five unimodal source distributions** — sources that
generated no bimodal structure whatever. The degeneracy is therefore independent of
what generated the data; it is a property of the criterion at `n = k`, not evidence
of bimodality. Of the 41 datasets only one (`anzg_iron_marine`) has the mixture as
its source, so the per-source `lnorm_lnorm` panel is a single dataset and must not
be over-read.

## The 2024 addendum's Figure 4 cannot be reconstructed

The report's own per-source analogues of the addendum's Figures 3 and 4 **can** be
rebuilt from committed artifacts (`source_weights_summary.csv`,
`bias_by_source_summary.csv`). The **original** addendum Figure 4 cannot: its
simulation code is no longer available and cannot be recovered from any co-author.
The original figure shows the mixture near zero for unimodal sources at all N — the
opposite of what the pipeline now produces. Because the original code is lost, it is
**not determinable** whether that reflects the fitting engine of the day, the sample
sizes at which the mixture was evaluated, or both. The discrepancy is unresolved and
is reported as unresolved.

That inability to regenerate a published result is itself the argument for the
reproducible pipeline: a result that cannot be regenerated cannot be diagnosed. This
is deliberately **not** a claim that the pipeline "caught a bug the original study
missed," nor a claim of a defect in the 2024 work.

## The ccme_boron rounding-then-argmax metadata bug

A second, smaller instance of the same provenance point surfaced in this study's own
metadata. `dataset_aicc_weights.csv` originally stored AICc weights **rounded to 3
decimals** and derived each dataset's source distribution with `which.max()` over
the rounded columns. For `ccme_boron`, gamma (0.356574) and weibull (0.357472) both
round to `0.357` — a rounding tie, difference ~9e-4 — and `which.max()` over the
column order (gamma before weibull) picked **gamma**. But `ssd_gen()` / `scenario.R`
select the source at **full precision**, which picks **weibull** — the distribution
the pipeline actually sampled from (recorded in `cache/true_hc.rds`). So the
committed metadata silently disagreed with the run.

This was a rounding-then-argmax bug, not a genuine tie. It was fixed in
`make_dataset_weights.R`, which now writes weights at full precision, derives the
source with an explicit deterministic tie-break reproducing `cache/true_hc.rds`, and
**asserts 41/41 agreement**. Corrected source counts (of 41 datasets): gamma 4,
lgumbel 15, llogis 5, lnorm 10, lnorm_lnorm 1, weibull 6. Like the larger Figure 4
discrepancy, it was only catchable because the run and its metadata were both
inspectable.
