# _targets.R - the 41-dataset bias/coverage/CI-width scenario (same science as
# ../study_small), but driven by a SLURM-backed `crew.cluster` controller
# instead of `crew::crew_controller_local()`. Each crew worker is a transient
# SLURM job; the driver (run.R) must itself run on an HPC submit/login node so
# it can `sbatch` the workers and the workers can connect back to it.
#
# No Azure / cloud upload: `ssd_scenario_targets()` is called with no
# `upload =` argument, so results stay on the cluster as local Parquet under
# the seed-/layout-keyed `scenario_results_dir()` root (study_small_hpc/
# results/seed=42/layout=<hash>/...). Pull them off with rsync/scp - see
# README.md.
#
# Run via (on the HPC submit node):  Rscript run.R
# Off-cluster smoke test (no SLURM):  swap in the commented local controller.

library(targets)
library(tarchetypes)

# `scenario` is defined in scenario.R, referenced as a global by the shard
# targets, so editing scenario.R invalidates the dependent shards. Identical
# to ../study_small/scenario.R (the backend change does not touch the science).
#
# Scope warn = 2 to the scenario "science" only, then restore the default. Left
# as a persistent global it stayed in effect for the whole tar_make() subprocess,
# so a benign gzfile "No space left on device" warning - raised by callr while
# serialising the subprocess result to a full /tmp - became a fatal crash.
old_warn <- options(warn = 2)
source("scenario.R")
options(old_warn)

# Controller: a transient SLURM worker pool tuned for the coarser sim-level
# shards in scenario.R (fewer, longer tasks). With heavy shards, a smaller
# worker pool and longer idle retention reduce queue churn and worker relaunches
# between fit/hc phases.
# `script_lines` are appended to each worker's sbatch script.
# Resource settings mirror the cluster's `cpuq` partition.
controller <- crew.cluster::crew_controller_slurm(
  name = "study-small-hpc",
  workers = 120L,
  seconds_idle = 1800,
  options_cluster = crew.cluster::crew_options_slurm(
    script_lines = c(
      "#SBATCH --nice=6000",
      # R was reported as already on PATH on the compute nodes; this module
      # load is harmless/redundant in that case - drop it if it conflicts.
      "module load R/4.4.1",
      "module load slurm"
    ),
    partition = "cpuq",
    cpus_per_task = 1L,
    # 2 GB was too tight: workers were over-memory-killed with MaxRSS pinned at
    # the 2 GB cap (sacct: FAILED, ExitCode 15:0), which crew reported as
    # repeated worker crashes on an hc shard. The kill masks the true peak, so
    # give generous headroom rather than a marginal bump.
    memory_gigabytes_per_cpu = 8,
    # Sim-level hc shards run ~1h40m each. A 12h wall lets a worker process
    # several shards before SLURM preempts it, cutting relaunch churn.
    time_minutes = 720L
  )
)

# Local fallback for off-cluster smoke tests (no SLURM). Uncomment this and
# comment out the SLURM controller above to run on a single machine:
# controller <- crew::crew_controller_local(
#   name = "study-small-hpc", workers = 8L, seconds_idle = 30
# )

tar_option_set(
  packages = c("ssdsims", "ssddata", "ssdtools", "dplyr", "duckplyr"),
  controller = controller,
  error = "continue"
)

# The whole pipeline: one target per shard, the per-step barriers, and the
# combined `summary`. No `upload =` - results stay local under results/.
ssd_scenario_targets(scenario)
