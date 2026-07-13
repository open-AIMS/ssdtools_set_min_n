# AICc small-sample correction is degenerate for distributions with `npars >= nobs - 1` (e.g. `lnorm_lnorm` at small N)

## Summary

For a candidate distribution with `k` parameters and `n` observations, `glance()`
reports the small-sample-corrected AICc

```
AICc = AIC + 2*k*(k+1) / (n - k - 1)
```

The correction term's denominator `n - k - 1` is **non-positive when `n <= k + 1`**,
so AICc is undefined/degenerate there:

- `n = k + 1`  →  denominator `0`  →  `AICc = +Inf` (the distribution is silently dropped from model averaging).
- `n <= k`     →  denominator `< 0`  →  the correction becomes a large **negative** number, so AICc is *lowered* — the criterion **rewards** the over-parameterised model instead of penalising it, and it takes essentially all of the AICc weight.

This bites the 5-parameter `lnorm_lnorm` mixture in `ssd_dists_bcanz()` at the
smallest sample sizes: at `n = 5` (= `k`) the mixture is handed `wt ≈ 1`, and at
`n = 6` (= `k + 1`) it gets `wt = 0` via `AICc = Inf`. Only from `n = 7`
(`n >= k + 2`) is its AICc finite and properly penalising.

## Reproducible example

Reproduces on **ssdtools 2.6.0** (CRAN). `ssd_fit_dists()` enforces a minimum of
6 rows by default, so `nrow = 5` is passed to allow the `n = 5` fit (as the
minimum-sample-size simulation study does):

```r
library(ssdtools)
packageVersion("ssdtools")
#> [1] '2.6.0'

dat <- data.frame(Conc = c(0.1, 0.3, 1, 3, 10))  # n = 5
fit <- ssd_fit_dists(dat, dists = ssd_dists_bcanz(), nrow = 5)
glance(fit, wt = TRUE)[, c("dist", "npars", "nobs", "aic", "aicc", "delta", "wt")]
```

```
# A tibble: 6 x 7
  dist        npars  nobs   aic  aicc delta        wt
  <chr>       <int> <int> <dbl> <dbl> <dbl>     <dbl>
1 gamma           2     5  23.3  29.3  61.3 4.79e-14
2 lgumbel         2     5  23.1  29.1  61.1 5.35e-14
3 llogis          2     5  23.3  29.3  61.4 4.70e-14
4 lnorm           2     5  22.9  28.9  60.9 5.99e-14
5 lnorm_lnorm     5     5  28.0 -32.0   0   1.00e+ 0   # <- k = n: AICc = AIC - 60, wins with wt = 1
6 weibull         2     5  23.2  29.2  61.2 5.17e-14
```

The 5-parameter mixture has the *worst* AIC (28.0) but the *best* AICc (−32.0),
because its correction term is `2*5*6 / (5 - 5 - 1) = -60`.

For contrast, at `n = 6` the same mixture gives `AICc = Inf` (`wt = 0`), and from
`n = 7` (`n >= k + 2`) its AICc is finite and heavily penalised, so its weight is
negligible (`wt ≈ 1e-14`; the exact `aicc` is data-dependent — e.g. ~116 on a
natural 7-point extension of the data above).

## Why it matters

With `est_method = "multi"` (AICc model averaging), a single degenerate weight
propagates straight into the HCx estimate. In a simulation study over 41 ssddata
datasets, **95.5% of the N = 5 model-averaged estimates collapsed onto the
`lnorm_lnorm` mixture** purely because of this reward, which produces large,
unstable bias at N = 5 that disappears at N = 6 (where the mixture weight is
forced to 0). It looks like a property of the estimator, but it is an artefact of
the criterion being evaluated outside its valid range.

The existing `nrow >= 6` guard in `ssd_fit_dists()` only partially masks this: it
blocks `n = 5` by default, but (a) it is a blunt global check rather than a
per-distribution one, (b) at the allowed `n = 6` the 5-parameter mixture is still
degenerate (`AICc = Inf`), and (c) any workflow that lowers the minimum (e.g. to
study N = 5) re-exposes the reward.

## Not a regression in the criterion — a change in the fit engine

The AICc formula above, and its degeneracy, are **byte-identical across ssdtools
1.0.6, 2.0.0 and 2.6.0**. The defect is a long-standing property of the criterion,
not a regression introduced in any release. What changed between the 1.0.x and 2.x
series is the *fitting engine*: the over-parameterised mixture is fitted to `n = 5`
data far more often under 2.x, so a reward that was always latent now fires in
almost every fit.

A Monte Carlo check (1000 samples of `n = 5` drawn from a unimodal lognormal source,
`meanlog = 0`, `sdlog = 1`) shows the fit rate — and hence the mean mixture weight —
jumping with the engine while the criterion stays fixed (rates carry a
Clopper-Pearson exact binomial 95% CI):

| ssdtools | settings | `n = 5` mixture fitted (95% CI) | Mean `n = 5` mixture weight |
|---|---|---|---|
| 1.0.6 | native  | 67.4% (64.4–70.3) | 0.674 |
| 1.0.6 | lenient | 68.0% (65.0–70.9) | 0.680 |
| 2.0.0 | native  | 97.9% (96.8–98.7) | 0.979 |
| 2.6.0 | native  | 97.9% (96.8–98.7) | 0.979 |

The mean weight tracks the fit rate directly because a fitted `n = 5` mixture almost
always wins the `-60` AICc reward: when it fits it takes `wt ≈ 1`, when it fails to
fit it takes `wt = 0`, so the average weight is essentially the fraction of samples
in which it was fitted at all. The `1.0.6 lenient` row is a control: relaxing the fit
options (`computable = FALSE`, `at_boundary_ok = TRUE`, `min_pmix = 0`) does not lift
the 1.0.x fit rate, so the jump is the engine, not the acceptance criteria.

The degeneracy itself is invariant to both version and fit arguments. Fitting the
5-point reprex above and its natural 6- and 7-point geometric extensions
(`c(0.1, 0.3, 1, 3, 10, 30)` and `c(0.1, 0.3, 1, 3, 10, 30, 100)`), the mixture's
full-precision AICc weight is:

| ssdtools | settings | wt (`n = 5`) | wt (`n = 6`) | wt (`n = 7`) | AICc (`n = 7`) |
|---|---|---|---|---|---|
| 1.0.6 | native  | 1.000 | 0 | 9.4e-15 | 116.2 |
| 1.0.6 | lenient | 1.000 | 0 | 9.4e-15 | 116.2 |
| 2.0.0 | native  | 1.000 | 0 | 9.4e-15 | 116.2 |
| 2.0.0 | lenient | 1.000 | 0 | 9.3e-15 | 116.2 |
| 2.6.0 | native  | 1.000 | 0 | 9.4e-15 | 116.2 |
| 2.6.0 | lenient | 1.000 | 0 | 9.3e-15 | 116.2 |

The weight is reconstructed from the `aicc` column as `exp(-Δ/2) / Σ exp(-Δ/2)`; the
`ssd_gof()` weight column is rounded to three decimals and would otherwise show the
`n = 7` weight as `0`. `AICc = +∞` at `n = 6`. Varying `computable`,
`at_boundary_ok` and `min_pmix` — the options that plausibly govern whether the
degenerate mixture is accepted — **does not drop the degenerate `n = 5` fit in any
version**: the reward fires across every version and both argument profiles, so the
behaviour cannot be worked around through fit arguments.

Both tables are reproducible from
[`aicc_degeneracy_reprex.R`](./aicc_degeneracy_reprex.R) in the repository, which
installs `ssdtools` 1.0.6 / 2.0.0 / 2.6.0 into isolated libraries and writes
`aicc_version_comparison.csv` (the weight table) and `aicc_fit_rate_comparison.csv`
(the Monte Carlo table).

The conclusion is that **a latent criterion defect became a dominant one because the
optimiser improved.** A more capable engine that fits the five-parameter mixture at
`n = 5` where the older engine would have failed is doing nothing wrong; it is the
criterion that rewards the resulting fit. The fix therefore belongs at the criterion
(below), not in the fit engine or its options.

## Suggested fix

Guard AICc at the criterion level, per distribution: when `nobs < npars + 2`,
return `AICc = Inf` (or `NA`) rather than the raw formula, so an unidentifiable
distribution can never receive finite — let alone rewarded — AICc weight. This
would make `n = 5` behave like `n = 6` already does for the mixture (weight 0 /
excluded), and could optionally emit a message noting the distribution was
dropped for insufficient data.

## Session info

- ssdtools 2.6.0 (CRAN) — reprex above
- Also observed on 2.6.0.9002 (dev) via the simulation pipeline
