#!/usr/bin/env Rscript

# Driver for the mixture-excluded study_small_nomix. Runs locally via the crew local
# controller in _targets.R. Usage (from ssdsims_pipeline/study_small_nomix/):
#   Rscript run.R                 # nsim = 30 (default)
#   STUDY_SMALL_NOMIX_NSIM=2 Rscript run.R   # fast pilot

library(targets)

old_warn <- options(warn = 2)
source("scenario.R")
options(old_warn)

started <- Sys.time()
tar_make()
elapsed <- as.numeric(Sys.time() - started, units = "mins")

cat(sprintf("\nwall time   : %.1f min\n", elapsed))
cat(sprintf("results dir : %s\n", ssdsims::scenario_results_dir(scenario)))
cat("Next: Rscript make_figure.R\n")
