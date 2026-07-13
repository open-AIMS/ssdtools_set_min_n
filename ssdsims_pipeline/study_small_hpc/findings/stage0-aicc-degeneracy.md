# Stage 0 finding — the AICc small-sample degeneracy, and why it became dominant

> **Investigation-only output.** This memo records a read-only investigation; no
> pipeline or report files were changed to produce it. It establishes facts the
> report's §6 rests on. Every quantity below is reproducible from
> [`../aicc_degeneracy_reprex.R`](../aicc_degeneracy_reprex.R), which writes
> `../aicc_version_comparison.csv` and `../aicc_fit_rate_comparison.csv`. The same
> defect is filed upstream as [`../ssdtools-aicc-issue.md`](../ssdtools-aicc-issue.md).

## The mechanism

`glance()` / `ssd_gof()` report the small-sample-corrected

```
AICc = AIC + 2*k*(k+1) / (n - k - 1)
```

for a distribution with `k` parameters and `n` observations. The correction's
denominator `n - k - 1` is **non-positive when `n <= k + 1`**, so AICc is
degenerate there. For the 5-parameter `lnorm_lnorm` mixture in `ssd_dists_bcanz()`:

- `n = 5` (`= k`): correction `= 2*5*6 / (5 - 5 - 1) = -60`. AICc is *lowered* — a
  reward, not a penalty — so the mixture wins every comparison and takes AICc
  weight `≈ 1` despite having the **worst** raw AIC.
- `n = 6` (`= k + 1`): denominator `0`, `AICc = +Inf`, weight forced to exactly `0`.
- `n >= 7` (`n >= k + 2`): AICc is finite and heavily penalised; weight negligible.

The correction is only defined for `n >= k + 2`, i.e. **N ≥ 7 for a five-parameter
model**. So the N = 5 and N = 6 mixture weights are artefacts of the criterion, not
evidence about fit.

## Invariance to version and to fit arguments (experiment a)

Fitting the 5-point reprex `Conc = c(0.1, 0.3, 1, 3, 10)` and its natural geometric
extensions to 6 and 7 points, under `ssdtools` 1.0.6 / 2.0.0 / 2.6.0 and under both
each version's native defaults and the lenient settings (`computable = FALSE`,
`at_boundary_ok = TRUE`, `min_pmix = 0`), the mixture's full-precision AICc weight
is (from `aicc_version_comparison.csv`):

| ssdtools | settings | wt (n=5) | wt (n=6) | wt (n=7) | AICc (n=7) |
|---|---|---|---|---|---|
| 1.0.6 | native  | 1.000 | 0 | 9.4e-15 | 116.2 |
| 1.0.6 | lenient | 1.000 | 0 | 9.4e-15 | 116.2 |
| 2.0.0 | native  | 1.000 | 0 | 9.4e-15 | 116.2 |
| 2.0.0 | lenient | 1.000 | 0 | 9.3e-15 | 116.2 |
| 2.6.0 | native  | 1.000 | 0 | 9.4e-15 | 116.2 |
| 2.6.0 | lenient | 1.000 | 0 | 9.3e-15 | 116.2 |

The AICc formula and its degeneracy are **byte-identical across the three
versions**, and relaxing `computable`, `at_boundary_ok` and `min_pmix` does not drop
the degenerate N = 5 fit. The defect is in the criterion, evaluated outside its
valid range — it cannot be worked around through fit arguments or by choosing a
version. (Weights are reconstructed from the `aicc` column as
`exp(-Δ/2) / Σ exp(-Δ/2)`; the `ssd_gof()` weight column is rounded to 3 dp and
would show the N = 7 weight as `0`.)

## The fitting-engine change (experiment b)

The criterion is fixed; what changed between the 1.0.x and 2.x series is the **fit
engine**. 1000 samples of N = 5 drawn from a unimodal lognormal source
(`meanlog = 0`, `sdlog = 1`), fitted with `ssd_dists_bcanz()`, give (from
`aicc_fit_rate_comparison.csv`, with Clopper-Pearson exact binomial 95% CIs):

| ssdtools | settings | N=5 mixture fitted (95% CI) | mean N=5 mixture weight |
|---|---|---|---|
| 1.0.6 | native  | 67.4% (64.4–70.3) | 0.674 |
| 1.0.6 | lenient | 68.0% (65.0–70.9) | 0.680 |
| 2.0.0 | native  | 97.9% (96.8–98.7) | 0.979 |
| 2.6.0 | native  | 97.9% (96.8–98.7) | 0.979 |

The over-parameterised mixture is fitted at N = 5 in about two-thirds of samples
under the 2024-era engine (1.0.6) but in nearly every sample under the current
engine (2.x). The mean weight tracks the fit rate directly, because a fitted N = 5
mixture almost always wins the −60 reward (`wt ≈ 1` when it fits, `wt = 0` when it
fails). The `1.0.6 lenient` row is a control: relaxing the fit options does not lift
the 1.0.x rate, so the jump is the engine, not the acceptance criteria.

## Conclusion

**A latent criterion defect became a dominant one because the optimiser improved.**
A more capable engine that fits the 5-parameter mixture at N = 5 where the older
engine failed is doing nothing wrong; it is the criterion that rewards the resulting
fit. The fix belongs at the criterion — guard AICc per distribution, returning
`AICc = Inf` when `nobs < npars + 2` (see the filed issue) — not in the fit engine
or its options.

The report's headline N = 5 behaviour follows from this: 95.5% of the N = 5
model-averaged HC estimates in the 41-dataset run collapse onto the mixture the
criterion has erroneously rewarded.
