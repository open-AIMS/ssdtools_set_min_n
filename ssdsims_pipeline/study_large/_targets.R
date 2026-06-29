# _targets.R - the combined ssddata + EnviroTox scenario (bias + AICc
# weights), run fully locally via a `crew` local controller. No SLURM, no
# cloud upload - `ssd_scenario_targets()` is called with no `upload =`
# argument, so results stay as local Parquet under
# study_large/results/seed=42/layout=<hash>/.
#
# Deliberately no `options(warn = 2)` here (unlike study_small) - fitting
# BCANZ to 305 real-world datasets legitimately hits ssdtools's own internal
# "lnorm_lnorm failed to fit" warning for a handful of them; ssdtools handles
# that gracefully (drops the distribution for that dataset), and warn = 2
# would turn that benign, already-handled warning into a fatal crash.
#
# Run via: Rscript run.R

library(targets)
library(tarchetypes)

source("scenario.R")

# Tune `workers` to this machine; keep in sync with check_prereqs.R.
controller <- crew::crew_controller_local(
  name = "study-large",
  workers = 18L, # tune to parallel::detectCores() on this machine; keep in sync with check_prereqs.R
  seconds_idle = 30
)

tar_option_set(
  packages = c("ssdsims", "ssddata", "ssdtools", "dplyr", "duckplyr"),
  controller = controller,
  error = "continue"
)

ssd_scenario_targets(scenario)
