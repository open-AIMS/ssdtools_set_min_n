# study_small_hpc

Same study as [`../study_small/`](../study_small) - Figure 2
(`ssdata_sims_collated.png`), the 20-dataset bias/coverage/CI-width scenario -
but run on the **HPC via SLURM** instead of locally on WSL.

The only difference from `study_small` is the controller in `_targets.R`:
`crew::crew_controller_local()` is replaced with a SLURM-backed
[`crew.cluster::crew_controller_slurm()`](https://wlandau.github.io/crew.cluster/).
`scenario.R` and `make_figure.R` are byte-for-byte the science from
`study_small` - the backend change does not touch the simulation.

## Key constraint: run the driver on a submit node

`crew.cluster` launches **each worker as its own SLURM job** (`sbatch`), and
those workers connect back to the driver process over TCP. So `Rscript run.R`
**must run on an HPC submit/login node** - not from WSL, and not inside a
compute-node job that can't itself submit. Drive it from the login node (or a
small interactive `srun` session that has `sbatch` available).

## Worker resources

Set in `_targets.R` via `crew_options_slurm()`, mirroring the cluster's `cpuq`
partition: 1 cpu/task, 2 GB/cpu, 180 min wall per worker job, `--nice=6000`,
`workers = 8`, `seconds_idle = 900`.

Scenario sharding is also intentionally coarsened in `scenario.R` with
`partition_by = list(fit = c("dataset", "sim"), hc = c("dataset", "sim"))`, so
fit/hc work is bundled into fewer, longer-running shards instead of many tiny
ones. R is taken from PATH on the compute nodes; the
`module load R/4.4.1` line in `script_lines` is harmless/redundant in that case
and can be dropped if it conflicts. `module load slurm` keeps `sbatch`/`squeue`
available inside worker jobs. Tune `workers`, `time_minutes`, and the partition
to your allocation.

## Run

```sh
# on the HPC submit node, from inside ssdsims_pipeline/study_small_hpc/
Rscript check_prereqs.R   # packages, sbatch on PATH, controller, scenario, cost
Rscript run.R             # tar_make() - submits workers as SLURM jobs
Rscript make_figure.R     # writes ../output/ssdata_sims_collated.png
```

`check_prereqs.R` additionally verifies `crew.cluster` is installed and that
`sbatch` resolves on PATH (i.e. you really are on a submit node).

## Getting results back

No cloud upload - results stay on the cluster as local Parquet under the
seed-/layout-keyed root (`study_small_hpc/results/seed=42/layout=<hash>/...`).
Either run `make_figure.R` on the cluster and copy the single PNG back, or pull
the Parquet store down and build the figure locally with `pull_results.sh`:

```sh
# from this WSL workspace, inside ssdsims_pipeline/study_small_hpc/
export HPC_HOST=<host-or-ssh-alias>
export HPC_USER=<user>          # omit if HPC_HOST is a ~/.ssh/config alias
export HPC_REMOTE_DIR=/path/on/hpc/.../ssdsims_pipeline/study_small_hpc

./pull_results.sh -n            # dry run: show what would transfer
./pull_results.sh               # rsync results/ down into ./results/
./pull_results.sh --figure      # ...and then build the figure locally
```

The script reads the connection from those env vars (so no host details are
committed), rsyncs the remote `results/` into the local `results/`, and with
`--figure` runs `make_figure.R` afterwards. Needs `rsync` in WSL
(`sudo apt install rsync`); `make_figure.R` needs the R packages from
`check_prereqs.R` available locally.

## Off-cluster smoke test

`_targets.R` carries a commented-out `crew::crew_controller_local()` block.
Uncomment it (and comment out the SLURM controller) to dry-run the pipeline on
a single machine without SLURM - useful for catching scenario/figure bugs
before queueing real worker jobs. Shrink `nsim` in `scenario.R` first.
