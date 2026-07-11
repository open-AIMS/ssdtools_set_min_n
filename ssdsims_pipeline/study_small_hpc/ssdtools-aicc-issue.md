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

For contrast, at `n = 6` the same mixture gives `AICc = Inf` (`wt = 0`), and at
`n = 7` it is properly penalised (`aicc ≈ 97`, `wt ≈ 1e-14`).

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
