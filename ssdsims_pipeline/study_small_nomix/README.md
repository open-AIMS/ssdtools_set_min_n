# study_small_nomix

A small, local, **tractable** variant of [`study_small`](../study_small) that
**removes the 5-parameter `lnorm_lnorm` mixture** from the candidate distribution
set.

## Why

In `study_small(_hpc)`, the model-averaged estimates at N = 5 are dominated by
the `lnorm_lnorm` mixture — not because it fits better, but because of an AICc
small-sample-correction degeneracy: the correction `2k(k+1)/(n-k-1)` *rewards* a
5-parameter model at n = 5 (denominator = −1) and is `+Inf` at n = 6 (denominator
= 0). See [`../study_small_hpc/ssdtools-aicc-issue.md`](../study_small_hpc/ssdtools-aicc-issue.md).

That raises the question this study answers: **is the "N = 5 is materially worse
than N = 6" result robust once the degenerate mixture is removed, or was the jump
largely an artefact of the mixture?** This could not be recovered from the
existing `study_small` outputs (coverage/width need the bootstrap CIs recomputed
with the reduced candidate set), so it needs its own small run.

## What differs from `study_small`

- `dists = ssd_distset(BCANZ_no_mix = setdiff(ssd_dists_bcanz(), "lnorm_lnorm"))`
  — the five 2-parameter unimodal distributions (gamma, lgumbel, llogis, lnorm,
  weibull), for which AICc is well defined at N ≥ 4.
- Sized down for local use: `nsim = 30`, `nrow = c(5, 6, 7, 8)`, `nboot = 200`.
  `nsim` is overridable with the `STUDY_SMALL_NOMIX_NSIM` env var for piloting.

## Run

```sh
cd ssdsims_pipeline/study_small_nomix
STUDY_SMALL_NOMIX_NSIM=2 Rscript run.R   # ~fast pilot to check it builds
Rscript run.R                      # full run (~30 min on 8 local workers)
Rscript make_figure.R              # study_small_nomix_coverage.png + summary CSV
```

`make_figure.R` prints coverage / median bias / median CI width by N and writes
`study_small_nomix_summary_table.csv` and `study_small_nomix_coverage.png` into this folder
(both committed) — compare the N = 5 and N = 6 rows to the full-mixture
`study_small` results.

Results (`cache/`, `results/`, `_targets/`) are local working state and are
git-ignored; the committed summary CSV is the shareable output.
