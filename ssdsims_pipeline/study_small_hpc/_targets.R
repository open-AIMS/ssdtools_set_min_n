options(warn = 2)

# _targets.R - the 20-dataset bias/coverage/CI-width scenario (same science as
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
source("scenario.R")

# Controller: a transient SLURM worker pool. `seconds_idle = 30` frees an idle
# worker after 30s. `script_lines` are appended to each worker's sbatch script.
# Resource settings mirror the cluster's `cpuq` partition. Tune `workers` to
# the cluster and the shard count (20 datasets x nsim hc tasks).
controller <- crew.cluster::crew_controller_slurm(
  name = "study-small-hpc",
  workers = 32L,
  seconds_idle = 30,
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
    memory_gigabytes_per_cpu = 2,
    # ci = TRUE + nboot = 1000 makes each hc task the long pole (~2.2-2.5 min
    # measured locally); 180 min per worker job is generous headroom.
    time_minutes = 180L
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
