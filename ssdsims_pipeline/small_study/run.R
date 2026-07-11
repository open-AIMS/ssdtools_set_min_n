#!/usr/bin/env Rscript

# Driver for the mixture-excluded small_study. Runs locally via the crew local
# controller in _targets.R. Usage (from ssdsims_pipeline/small_study/):
#   Rscript run.R                 # nsim = 50 (default)
#   SMALL_STUDY_NSIM=2 Rscript run.R   # fast pilot

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
