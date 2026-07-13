## WSL local `targets` + `crew` Pipeline Runbook

A step-by-step guide for running the **mixture-excluded** `small_study` simulation
locally on the WSL workstation with a `crew` **local** controller, then building
its figure and summary table in place.

It is the local companion to the HPC runbook (`../study_small_hpc/HPC_WORKFLOW_RUNBOOK.md`).
Where that run puts the full six-distribution BCANZ study on a SLURM cluster, this
one runs a smaller, tractable variant on a single machine — no scheduler, no
cluster, no result transfer. The concrete commands below are the actual
`small_study` run (July 2026).

### 0. Architecture in one paragraph

`targets` builds a dependency graph of "shards". A `crew::crew_controller_local()`
controller runs the workers as **local processes on this machine** (not SLURM
jobs), all driven by `Rscript run.R` in the same directory. Results are written as
local Parquet under a seed-/layout-keyed dir
(`results/seed=<seed>/layout=<hash>/...`), exactly as on the HPC — but here the
driver, the workers, and the outputs all live on one box, so there is nothing to
submit and nothing to pull back.

Key files in the workflow directory (`ssdsims_pipeline/small_study/`):

| File | Role |
|------|------|
| `_targets.R` | Defines the **local** controller (8 workers) + the pipeline |
| `scenario.R` | The science — the reduced, no-mixture candidate set; caches fits to `cache/` |
| `run.R` | Driver: `tar_make()` then prints wall time + results dir |
| `make_figure.R` | Reads `summary.parquet`, writes the coverage figure + summary CSV |
| `README.md` | Short orientation and the why of the mixture exclusion |

### Part A — Run the pipeline locally

#### A1. Setup — R packages

The pipeline needs `ssdsims` (install from source — it is not on CRAN) plus a
Parquet reader (`duckplyr`) and the usual analysis packages. Everything the
targets need is declared in `_targets.R`:
`ssdsims`, `ssddata`, `ssdtools`, `dplyr`, `duckplyr`; `make_figure.R` additionally
uses `ggplot2`.

```sh
# one-off, from WSL
Rscript -e 'remotes::install_local("/mnt/c/Rworking/ssdsims", dependencies = TRUE, upgrade = "never")'
# dependencies = TRUE also pulls duckplyr, dqrng, etc. (compiles duckdb — slow).
```

Confirm which R you are using first — the WSL R (`which R`), not the Windows one.

#### A2. Scenario definition — the no-mixture science

`scenario.R` mirrors `study_small`'s science with **one deliberate change**: it
drops the 5-parameter `lnorm_lnorm` mixture from the candidate set.

```r
dists_nomix <- setdiff(ssd_dists_bcanz(), "lnorm_lnorm")  # 5 unimodal 2-param dists
```

The rest matches `study_small`: for each of the 41 `ssddata` (ANZG + CCME)
datasets it fits the reduced set, takes the top-AICc distribution as the "true"
generating model (`ssd_gen()` samples from it), then re-fits with model averaging
(`est_method = "multi"`) over the same reduced set and computes weighted-sample
bootstrap CIs. Fits and "true" HC values are cached to `cache/fits.rds` and
`cache/true_hc.rds` on the first run and reused thereafter.

Scenario parameters (verify against `scenario.R` before relying on them):

| Parameter | `small_study` value | Set where |
|-----------|---------------------|-----------|
| `dists` | 5 unimodal (no `lnorm_lnorm`) | `ssd_distset(BCANZ_no_mix = dists_nomix)` |
| `nsim` | `30` (override with `SMALL_STUDY_NSIM`) | `Sys.getenv("SMALL_STUDY_NSIM", unset = "30")` |
| `nrow` | `5, 6, 7, 8` | focused on the N = 5-vs-6 question |
| `proportion` | `0.01, 0.05, 0.1, 0.2` | HC1, HC5, HC10, HC20 |
| `nboot` | `200` | weighted-sample bootstrap |
| `est_method` / `ci_method` | `multi` / `weighted_samples` | recommended methods |
| `seed` | `42` | reproducibility |

> The header comment in `run.R` says "nsim = 50 (default)"; the **actual** default
> in `scenario.R` is `30` (`SMALL_STUDY_NSIM` unset → `"30"`), which is what the
> committed outputs were built with (1,230 = 30 sims × 41 datasets per N cell).
> Treat `scenario.R` as authoritative.

#### A3. How this differs from the HPC configuration

Same simulation machinery (`ssd_scenario_targets()`), different controller **and**
a smaller, mixture-free scenario:

| Aspect | HPC (`study_small_hpc`) | WSL (`small_study`) |
|--------|-------------------------|---------------------|
| Controller | `crew.cluster::crew_controller_slurm()` — each worker a `sbatch` job | `crew::crew_controller_local()` — local processes |
| Where the driver runs | HPC login/submit node | this WSL machine |
| Workers | up to 120 SLURM jobs | `8` local processes |
| Candidate set | full BCANZ (6 dists, incl. `lnorm_lnorm`) | 5 unimodal (no mixture) |
| `nsim` / `nrow` / `nboot` | 500 / `5,6,7,8,10,16,26` / 1000 | 30 / `5,6,7,8` / 200 |
| Shard granularity | coarsened (`partition_by` bundles per-sim) | default (no `partition_by`) |
| Temp space / memory tuning | `TMPDIR` export, 8 GB/worker | none needed |
| Getting results | rsync `summary.parquet` + `cache/` back | already local |

The worker count is `8`, not one-per-core: `_targets.R` notes that ~18 local
workers each loading `ssdtools`/`duckdb` and running weighted-sample bootstraps
exhausted RAM on the 31 GB dev box and crashed workers. `8` leaves headroom; raise
it only if the machine has more RAM. `error = "continue"` is set so a single failed
shard does not abort the whole run.

#### A4. Invocation

```sh
cd ssdsims_pipeline/small_study
SMALL_STUDY_NSIM=2 Rscript run.R   # fast pilot: check it builds end to end
Rscript run.R                      # full run (nsim = 30)
Rscript make_figure.R              # writes small_study_coverage.png + summary CSV
```

`run.R` scopes `options(warn = 2)` to sourcing `scenario.R` only (so a benign
read/plot warning elsewhere cannot turn fatal — the same pattern as the HPC run),
then calls `tar_make()` and prints the wall time and results dir on completion.
Re-running is cheap: completed shards are cached, so a re-run rebuilds only what
changed.

#### A5. Runtime and resource profile

- **Wall time:** ~30 min for the full `nsim = 30` run on 8 local workers
  (`scenario.R` sizing note: ~0.2 min per (dataset, sim) HC task × 41 datasets ×
  30 sims ≈ 246 core-min ÷ 8 workers ≈ 30 min).
- **Concurrency:** `workers = 8L`, `seconds_idle = 30`. RAM-bound, not core-bound,
  on the 31 GB box — hence 8 rather than one-per-core.
- **Pilot:** `SMALL_STUDY_NSIM=2` completes in a couple of minutes and is the right
  smoke test after any change to `nboot`, `proportion`, or the distribution set.

### Part B — Outputs and how to inspect results

#### B1. What the run produces

| Output | Tracked? | What it is |
|--------|----------|------------|
| `small_study_summary_table.csv` | **committed** | coverage, median rel. bias, median rel. CI width, `n` per (proportion, N) |
| `small_study_coverage.png` | **committed** | per-dataset coverage boxplots by N, faceted by HC proportion |
| `cache/fits.rds`, `cache/true_hc.rds` | git-ignored | cached real-data fits and "true" HC values |
| `results/seed=42/layout=<hash>/summary.parquet` | git-ignored | the collated per-sim HC results |
| `_targets/` | git-ignored | the `targets` metadata/object store |

The two committed files are the shareable outputs; `cache/`, `results/`, and
`_targets/` are local working state (git-ignored) and are rebuilt by re-running.

#### B2. Inspecting results

`make_figure.R` prints a by-N table (coverage / median bias / median width) to the
console and writes the CSV + PNG. To read the summary CSV directly:

```r
read.csv("small_study_summary_table.csv")
# 16 rows = 4 proportions × 4 N; compare the N = 5 and N = 6 coverage rows to the
# full-mixture study_small(_hpc) results — the point of this run.
```

To go beyond the summary, load `summary.parquet` and join it as `make_figure.R`
does (recover the dataset via `hc_id`, attach the "true" HC values from `cache/`):

```r
summary_tbl <- tibble::as_tibble(dplyr::collect(
  duckplyr::read_parquet_duckdb("results/seed=42/layout=<hash>/summary.parquet",
    options = list(hive_partitioning = FALSE))))
hc_tasks <- ssdsims::ssd_scenario_hc_tasks(scenario)[, c("hc_id","dataset","sim","nrow")]
source("scenario.R")   # also defines true_hc (from cache/)
# then join summary_tbl -> hc_tasks (by hc_id) -> true_hc (by dataset, proportion)
```

> If the local `scenario.R` has drifted, the `layout=<hash>` in the results path
> changes and `make_figure.R` won't find the pulled data. Check the expected path
> with:
> `Rscript -e 'source("scenario.R"); cat(ssdsims::scenario_results_dir(scenario), "\n")'`

### Quick checklist for next time

1. [ ] `ssdsims` + `duckplyr` installed in the WSL R; `which R` is the WSL one.
2. [ ] `SMALL_STUDY_NSIM=2 Rscript run.R` pilot builds end to end.
3. [ ] `Rscript run.R` (full `nsim = 30`, ~30 min on 8 workers).
4. [ ] `Rscript make_figure.R` → `small_study_coverage.png` + `small_study_summary_table.csv`.
5. [ ] Compare N = 5 vs N = 6 coverage against the full-mixture `study_small(_hpc)` result.
