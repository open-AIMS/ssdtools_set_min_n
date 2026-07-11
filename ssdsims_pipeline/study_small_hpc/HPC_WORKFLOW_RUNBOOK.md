# HPC `targets` + `crew.cluster` Pipeline Runbook

A step-by-step, reusable guide for running a `targets` simulation pipeline on a
SLURM HPC via a `crew.cluster` controller, then pulling the results back to WSL
and building figures/tables locally.

It is written generically so it can be copied to a future project, but every step
also shows the **concrete commands from the `study_small_hpc` run** (July 2026) as
a worked example. Replace the example values (host, paths, layout hash) with your
own.

---

## 0. Architecture in one paragraph

`targets` builds a dependency graph of "shards". A `crew.cluster::crew_controller_slurm()`
controller launches **each worker as its own `sbatch` job**; workers connect back
over TCP to the **driver** process (`Rscript run.R`), which must run on a **submit/
login node**. Results are written as local Parquet under a seed-/layout-keyed dir
(`results/seed=<seed>/layout=<hash>/...`) — no cloud upload. You then copy the one
collated `summary.parquet` back and build the figure/tables anywhere the R packages
are available.

Key files in the workflow directory:

| File | Role |
|------|------|
| `_targets.R` | Defines the controller (worker resources) + the pipeline |
| `scenario.R` | The science; sourced by the others; caches fits to `cache/` |
| `run.R` | Driver: `tar_make()` then prints the summary |
| `make_figure.R` | Reads `summary.parquet`, builds the figure |
| `check_prereqs.R` | Verifies packages, `sbatch` on PATH, cost estimate |

---

## Part A — Run the pipeline on the HPC

### A1. Get the code onto the HPC

Via git (if the HPC can reach your remote) or `scp` from WSL:

```sh
# from WSL, example
scp -r ssdsims_pipeline/study_small_hpc \
  rfisher@hpc-l001.aims.gov.au:~/ssdtools_set_min_n/ssdsims_pipeline/
```

> **Caution:** if you hand-edit files on the HPC (e.g. bump `workers`/`memory`),
> a later `scp` of the whole file from WSL will clobber those edits. Either edit
> one line in place on the HPC, or keep WSL as the single source of truth.

### A2. SSH to the **login** node

```sh
ssh rfisher@hpc-l001.aims.gov.au       # login node = can submit sbatch jobs
cd ~/ssdtools_set_min_n/ssdsims_pipeline/study_small_hpc
```

Confirm you can submit jobs from here: `command -v sbatch` should resolve.

### A3. Redirect temp space **before** running (CRITICAL)

Login-node `/tmp` is often small and shared. When it fills, `callr` (used by
`tar_make()`) fails to serialise a subprocess result and the run dies with
`gzfile ... No space left on device`. Point R's tempdir at your large home/scratch
filesystem, and clear old junk:

```sh
df -h /tmp $HOME                       # check: is / (holding /tmp) nearly full?
export TMPDIR="$HOME/scratch/rtmp"     # a filesystem with real space
mkdir -p "$TMPDIR"
export TMP="$TMPDIR" TEMP="$TMPDIR"
rm -rf /tmp/Rtmp* 2>/dev/null          # only removes your own leftovers
```

> R fixes `tempdir()` at startup from `TMPDIR`, so this **must** be exported in the
> shell *before* `Rscript`, not set inside R.

### A4. Check prerequisites, then run

```sh
Rscript check_prereqs.R    # packages, sbatch on PATH, controller, scenario, cost
Rscript run.R              # tar_make() — submits workers as SLURM jobs
```

`run.R` prints the summary parquet path and the results dir on success, e.g.:

```
summary parquet : results/seed=42/layout=5b3e1f4f4da3/summary.parquet
results dir     : results/seed=42/layout=5b3e1f4f4da3
```

**Re-running is safe and cheap** — completed shards are cached, so a re-run after
a crash skips the finished work (`N skipped`) and only rebuilds what failed.

### A5. Worker resources — where to tune (`_targets.R`)

Inside `crew_controller_slurm()` / `crew_options_slurm()`:

| Knob | What it controls | This run's value |
|------|------------------|------------------|
| `workers` | Max concurrent SLURM worker jobs | `120` |
| `seconds_idle` | How long an idle worker lingers before shutdown | `1800` |
| `memory_gigabytes_per_cpu` | RAM per worker (see A/OOM below) | `8` |
| `cpus_per_task` | CPUs per worker | `1` |
| `time_minutes` | Wall-clock limit per worker job | `720` |
| `partition` | SLURM partition | `"cpuq"` |
| `script_lines` | Extra `#SBATCH`/`module load` lines | `--nice=6000`, module loads |

---

## Part B — Diagnosing the failures we actually hit

### B1. `gzfile ... No space left on device` → temp space

Cause: login-node `/tmp` filled during the final combine.
Fix: the `TMPDIR` export in **A3** + `rm -rf /tmp/Rtmp*`, then re-run.

### B2. A benign warning became a fatal error → `options(warn = 2)`

If the driver/pipeline files start with a global `options(warn = 2)`, it promotes
*any* warning (including the disk warning above) to a hard error. Scope it to just
the science instead of leaving it global:

```r
old_warn <- options(warn = 2)
source("scenario.R")      # the part where a numeric warning is a real problem
options(old_warn)         # restore before pipeline execution / I/O / serialisation
```

### B3. `the crew worker of task '...' crashed N consecutive time(s)` → OOM

A "worker crash" is the SLURM job dying, not an R error (so `error = "continue"`
does not rescue it). It's almost always **out of memory**. Diagnose with `sacct`
(use an **absolute** start time — some SLURM builds reject `now-8hours`):

```sh
sacct --starttime "$(date -d '8 hours ago' '+%Y-%m-%dT%H:%M:%S')" \
  --format=JobID,JobName%20,State,ExitCode,MaxRSS,ReqMem,Elapsed --units=G \
  | grep -iE 'OUT_OF_MEMORY|FAILED|CANCELLED|NODE_FAIL|TIMEOUT'

seff <JobID>     # one-line memory-efficiency summary for a single job
```

Read the columns:

| Signal | Meaning | Fix |
|--------|---------|-----|
| `State = OUT_OF_MEMORY`, or `MaxRSS` ≈ `ReqMem`, `ExitCode 137` (128+9) | Over-memory kill | Raise `memory_gigabytes_per_cpu` |
| `ExitCode 139` (128+11) | Segfault in the computation | Isolate that shard; not a memory fix |
| `State = TIMEOUT` | Exceeded `time_minutes` | Raise `time_minutes` |

In this run every worker showed `MaxRSS ≈ 2.0 G` against a `2Gc` request → OOM.
Raising `memory_gigabytes_per_cpu` from `2` to `8` fixed it. (The kill masks the
true peak, so give generous headroom rather than a marginal bump.)

### B4. `there is no package called 'arrow'` when building the figure

The HPC lacked `arrow`. Since the pipeline already depends on `duckplyr`, read the
summary Parquet with that instead (no extra package to install):

```r
summary_tbl <- tibble::as_tibble(dplyr::collect(
  duckplyr::read_parquet_duckdb(
    summary_path,
    options = list(hive_partitioning = FALSE)   # summary.parquet is a flat file
  )
))
```

---

## Part C — Pull results back to WSL and report locally

### C1. Confirm SSH works from WSL (keys live per-environment)

Windows and WSL have **separate** `~/.ssh`. Probe non-interactively (fails fast
instead of hanging on a password prompt):

```sh
ssh -o BatchMode=yes -o ConnectTimeout=12 rfisher@hpc-l001.aims.gov.au 'echo SSH_OK; hostname'
```

If this prints `SSH_OK`, key auth works from WSL and you can run the pull here.

### C2. Find the **real** remote path (home may not be `/home/<user>`)

```sh
ssh rfisher@hpc-l001.aims.gov.au '
  echo "HOME=$HOME"
  find ~/ssdtools_set_min_n/ssdsims_pipeline/study_small_hpc/results -name summary.parquet 2>/dev/null
  du -sh ~/ssdtools_set_min_n/ssdsims_pipeline/study_small_hpc/results 2>/dev/null
'
```

Example: home was `/export/home/q-z/rfisher` (not `/home/rfisher`), and the full
`results/` was **63 GB / 2375 files** — all the intermediate shards.

### C3. Pull **only** what reporting needs — not the whole `results/`

You need the collated `summary.parquet` (~34 MB) and `cache/` (`fits.rds` +
`true_hc.rds`, ~11 MB). **Do not** rsync all of `results/` (63 GB of shards).

```sh
cd /mnt/c/Rworking/ssdtools_set_min_n/ssdsims_pipeline/study_small_hpc
REMOTE=/export/home/q-z/rfisher/ssdtools_set_min_n/ssdsims_pipeline/study_small_hpc
HASH=layout=5b3e1f4f4da3

mkdir -p "results/seed=42/$HASH" cache
rsync -az --info=progress2 \
  "rfisher@hpc-l001.aims.gov.au:$REMOTE/results/seed=42/$HASH/summary.parquet" \
  "results/seed=42/$HASH/"
rsync -az "rfisher@hpc-l001.aims.gov.au:$REMOTE/cache/" "cache/"
```

> The repo's `pull_results.sh` pulls the *entire* `results/` tree — fine when it's
> small, but for a 63 GB store the targeted rsync above is the right call.
> Run scripts on `/mnt/c` with `bash script.sh` (the exec bit doesn't stick there),
> and run the pull **from WSL**, not from an SSH session on the HPC.

### C4. Install the R packages locally (one-off)

The figure/scenario scripts need `ssdsims` (your own package, install from source)
and a Parquet reader (`duckplyr`). Everything else (`ssdtools`, `dplyr`, `ggplot2`,
`patchwork`, `tibble`) is usually already present.

```sh
Rscript -e 'remotes::install_local("/mnt/c/Rworking/ssdsims", dependencies = TRUE, upgrade = "never")'
# dependencies = TRUE also installs duckplyr, dqrng, etc. (compiles duckdb — slow).
# Use dependencies = NA for Imports-only if you want a leaner install.
```

### C5. Verify the layout hash matches before relying on the data

`make_figure.R` derives the results dir from the **local** `scenario.R`. If it has
drifted from the HPC copy, the hash won't match and it won't find the pulled data.
Check:

```sh
Rscript -e 'source("scenario.R"); cat(ssdsims::scenario_results_dir(scenario), "\n")'
# Must end in the same layout=<hash> you pulled (e.g. layout=5b3e1f4f4da3).
```

### C6. Build the figure / tables

```sh
Rscript make_figure.R      # writes ../output/<figure>.png
```

For a ready-made reporting figure (bias on symmetric-log, width on log10) plus a
summary table, run:

```sh
Rscript make_report_outputs.R
# -> ../output/study_small_report_figure.png + study_small_summary_table.csv
```

To build your own, load `summary.parquet` (C4's reader) and join to the task
metadata and the "true" HC values:

```r
summary_tbl <- tibble::as_tibble(dplyr::collect(
  duckplyr::read_parquet_duckdb("results/seed=42/layout=5b3e1f4f4da3/summary.parquet",
    options = list(hive_partitioning = FALSE))))
hc_tasks <- ssdsims::ssd_scenario_hc_tasks(scenario)[, c("hc_id","dataset","sim","nrow")]
source("scenario.R")   # also defines true_hc (from cache/)
# then join summary_tbl -> hc_tasks (by hc_id) -> true_hc (by dataset, proportion)
```

---

## Quick checklist for next time

1. [ ] Code on the HPC login node; `sbatch` resolves.
2. [ ] `export TMPDIR=$HOME/scratch/rtmp` (roomy fs) **before** `Rscript`.
3. [ ] `Rscript check_prereqs.R` → `Rscript run.R`.
4. [ ] Crash? → `df -h /tmp` (space), `sacct`/`seff` (memory), scope `warn = 2`.
5. [ ] Tune `memory_gigabytes_per_cpu` / `time_minutes` / `workers` in `_targets.R`.
6. [ ] From WSL: probe SSH, find real remote path, rsync **only** `summary.parquet` + `cache/`.
7. [ ] Install `ssdsims` + `duckplyr` locally; verify layout hash; build figure/tables.
