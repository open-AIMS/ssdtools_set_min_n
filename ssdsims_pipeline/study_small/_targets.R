options(warn = 2)

# _targets.R - the 20-dataset bias/coverage/CI-width scenario, run fully
# locally: a `crew` local controller (mirai-backed persistent workers), no
# SLURM, no cloud upload. `ssd_scenario_targets()` is called with no
# `upload =` argument, so results stay as local Parquet files under the
# seed-/layout-keyed `scenario_results_dir()` root (`results/seed=42/
# layout=<hash>/...`, i.e. study_small/results/).
#
# Run via: Rscript run.R

library(targets)
library(tarchetypes)

# `scenario` is defined in scenario.R, referenced as a global by the shard
# targets, so editing scenario.R invalidates the dependent shards.
source("scenario.R")

# Tune `workers` to this machine (parallel::detectCores()); this repo was
# developed on a 22-core WSL box, leaving a few cores free for other work.
controller <- crew::crew_controller_local(
  name = "study-small",
  workers = 18L, # tune to parallel::detectCores() on this machine; keep in sync with check_prereqs.R
  seconds_idle = 30
)

tar_option_set(
  packages = c("ssdsims", "ssddata", "ssdtools", "dplyr", "duckplyr"),
  controller = controller,
  error = "continue"
)

ssd_scenario_targets(scenario)
