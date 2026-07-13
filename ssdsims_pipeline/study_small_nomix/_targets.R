# _targets.R - local crew pipeline for the mixture-excluded study_small_nomix.
# Same machinery as ../study_small, just the reduced-candidate-set scenario.
# Run via: Rscript run.R

library(targets)
library(tarchetypes)

# Scope warn = 2 to the scenario "science" only (see ../study_small_hpc/run.R).
old_warn <- options(warn = 2)
source("scenario.R")
options(old_warn)

controller <- crew::crew_controller_local(
  name = "study-small-nomix",
  # 8, not one-per-core: 18 local workers each loading ssdtools/duckdb and
  # running weighted-sample bootstraps exhausted RAM on the 31 GB dev box and
  # crashed workers (crew reports it as repeated crashes on whichever task was
  # in flight). 8 leaves comfortable headroom; raise if the machine has more RAM.
  workers = 8L,
  seconds_idle = 30
)

tar_option_set(
  packages = c("ssdsims", "ssddata", "ssdtools", "dplyr", "duckplyr"),
  controller = controller,
  error = "continue"
)

ssd_scenario_targets(scenario)
