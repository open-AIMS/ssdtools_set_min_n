# ssdsims_pipeline

Reproduces the images in `../Images/` using the new
[`ssdsims`](https://github.com/poissonconsulting/ssdsims) simulation
framework, run fully locally on this machine via `crew::crew_controller_local()`
(no SLURM, no Azure upload), following the pattern in
[poissonconsulting/ssdsims-org#18](https://github.com/poissonconsulting/ssdsims-org/pull/18)'s
`test_run/crew-ssdsims-local/`.

Each study below is **one** `ssd_define_scenario()` call run through
`ssd_scenario_targets()` directly (not `ssd_design_targets()`/`ssd_design()`),
matching the original report's two separate simulation studies.

These are new, standalone scripts. Nothing here is wired into
`../min_sample_size.Rmd` - that integration is a separate step.

## Layout

```
ssdsims_pipeline/
|-- 01_fit_example_datasets.R   Figure 1 (fitted_dists.png) - plain ssdtools,
|                                no simulation framework needed
|-- study_small/                Figure 2 (ssdata_sims_collated.png):
|   |-- scenario.R                 the 20 ssddata datasets, ci = TRUE
|   |-- _targets.R                 crew local controller + ssd_scenario_targets()
|   |-- check_prereqs.R            run first: packages, scenario, cost estimate
|   |-- run.R                      tar_make() driver
|   `-- make_figure.R              post-process summary.parquet -> the figure
|-- study_large/                 Figures 3 & 4 (all_sims_bias.png,
|   |                            weights_collated.png): 20 ssddata + EnviroTox
|   |                            datasets, ci = FALSE
|   |-- scenario.R
|   |-- _targets.R
|   |-- check_prereqs.R
|   |-- run.R
|   |-- make_figure_bias.R         Figure 3, from summary.parquet
|   `-- make_figure_weights.R      Figure 4, from the fit shards directly
                                    (AICc weights are a fit-step property)
|-- cache/                      per-study .rds caches (fits, true HCx, etc.)
`-- output/                     generated PNGs land here (not ../Images/)
```

`cache/` and `results/` (the `targets`/Parquet stores) are local working
state, not committed. `output/` holds the regenerated PNGs side-by-side with
the originals in `../Images/` for comparison - nothing in `../Images/` is
overwritten.

## Step 1 - Figure 1 (no simulation)

```sh
cd ssdsims_pipeline
Rscript 01_fit_example_datasets.R
```

Fits the BCANZ default distributions (gamma, lgumbel, llogis, lnorm,
lnorm_lnorm, weibull) to the 20 ssddata "v1" example datasets and writes
`output/fitted_dists.png`.

## Step 2 - Figure 2: the 20-dataset study

```sh
cd ssdsims_pipeline/study_small
Rscript check_prereqs.R   # packages, crew, scenario, live cost estimate
Rscript run.R              # builds the pipeline (tar_make())
Rscript make_figure.R      # writes ../output/ssdata_sims_collated.png
```

To run this same study on the HPC via SLURM instead of locally, see
[`study_small_hpc/`](study_small_hpc) - identical `scenario.R`/`make_figure.R`,
but the `_targets.R` controller is `crew.cluster::crew_controller_slurm()`
and the driver runs on a submit node.

`scenario.R` fits each of the 20 datasets, takes each one's own
top-AICc-weighted BCANZ distribution as its "true" generating model (the
same selection `ssd_gen()` makes internally for a multi-distribution
`fitdists` input - see `?ssd_gen`), and resamples from it across
`nrow = c(5, 6, 7, 8, 10, 16, 26)` with bootstrap CIs
(`ci_method = "weighted_samples"`, the recommended method). `nsim = 15L`
(vs. the original study's `nsim = 1000`) was sized from a **measured** run,
not `ssd_estimate_cost()` (see Cost note below) - confirmed end-to-end at
`nsim = 3L` (~24 min wall on 10 workers, under unrelated CPU contention at
the time); `nsim = 15L` should land around ~40 min wall on 18 dedicated
workers. Bump `nsim`/`nboot` up further once you're happy with the pipeline.

**Validated:** a full `nsim = 3L` run completed end-to-end (`check_prereqs.R`
-> `run.R` -> `make_figure.R`), and the resulting plot already shows the
expected qualitative pattern (poor coverage and high bias/width at N = 5,
both stabilising from N = 6) even at that tiny `nsim`.

## Step 3 - Figures 3 & 4: the combined ssddata + EnviroTox study

```sh
cd ssdsims_pipeline/study_large
Rscript check_prereqs.R
Rscript run.R
Rscript make_figure_bias.R      # writes ../output/all_sims_bias.png
Rscript make_figure_weights.R   # writes ../output/weights_collated.png
```

Same approach as study_small, but `ci = FALSE` (matching the original
report, which did not attempt bootstrap CIs for this larger run) and over a
much larger dataset corpus (see below). One `nrow` sweep
(`5:16` plus `32, 64, 128, 256`) serves both figures: `make_figure_bias.R`
zooms to `nrow <= 16` (the report's focus), `make_figure_weights.R` uses the
full range to show AICc weight convergence at large N.

### EnviroTox data and a scope note

The EnviroTox chemicals are pulled from `ssddata::envirotox_acute`, filtered
to the `Yanagihara24` column (the original paper's criteria: bimodality
coefficient <= 0.555, >= 10 species, >= 3 trophic groups). **This column only
exists on the `open-AIMS/ssddata@dev` branch**, not the CRAN release - it was
installed locally via `remotes::install_local()` from a checkout of that
branch (see chat log for how this was set up on this machine; re-run that
install if `ssddata::envirotox_acute` doesn't have a `Yanagihara24` column).

That filter currently yields **285** EnviroTox chemicals, not the ~333 in
the original report (20 + 333 = 353) - likely EnviroTox database
version/aggregation differences between when the original report was written
and the current `ssddata@dev` data. So this study covers **305** datasets
(20 + 285), not 353. `make_figure_bias.R`/`make_figure_weights.R` will look
structurally like Figures 3/4 but are not a byte-for-byte reproduction.

### Cost, and what's actually validated here

This scenario is much bigger than study_small's (305 datasets). `nsim = 10L`
is a starting default in `scenario.R`, sized from a per-task rate measured
directly (~0.3-0.9s per fit task at `nsim = 1L`, 4,880 fit tasks) rather than
`ssd_estimate_cost()` (its calibration is centred on the bootstrap step,
`ci = TRUE`, which this scenario doesn't use).

**Not fully validated end-to-end**: development hit several hours of heavy,
*unrelated* CPU contention from another job on the same machine (one process
pinning 8 of 22 cores for 12+ hours), which made full-run timing unreliable
and a `make_figure_weights.R` test against partial results hang on Arrow's
dataset-discovery step (reading ~3,300 small Parquet files under contention).
What **is** confirmed:
- `scenario.R` builds correctly over the full 305-dataset corpus (one
  real bug found and fixed: `options(warn = 2)`, copied from the upstream
  example, turned ssdtools's own benign "lnorm_lnorm failed to fit" warning -
  expected on a handful of the 285 real-world EnviroTox datasets - into a
  fatal crash; removed from this study's scripts, kept in study_small's where
  it never triggered).
- The pipeline ran for ~12 hours under that contention and reached 3,348/4,880
  fit shards with zero task failures before being stopped - those shards are
  cached on disk (`results/`) and will be reused, not recomputed, by your next
  `Rscript run.R`.
- The `make_figure_weights.R` blob-decode step (`unserialize(charToRaw(...))`
  -> `ssdtools::ssd_gof()`) and the weight-matrix/plotting logic were each
  verified directly against small, fast, synthetic/fixture data.

Run `check_prereqs.R` and a `nsim = 1L`/`nsim = 2L` pilot yourself once the
machine isn't under other load, and time it, before trusting any nsim/runtime
number for this study.

## Tuning workers

Both `_targets.R` files set `crew::crew_controller_local(workers = 18L)`,
sized for the 22-core WSL machine this was developed on. Adjust to
`parallel::detectCores()` on whatever machine you run this on, and keep
`check_prereqs.R`'s `workers <- 18L` in sync so its wall-time estimate stays
accurate.
