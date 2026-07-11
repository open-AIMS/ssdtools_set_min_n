#!/usr/bin/env Rscript

# Driver: build the 41-dataset bias/coverage/CI-width scenario through the
# SLURM-backed crew.cluster controller in _targets.R, then point at
# make_figure.R to build the plot. Must run on an HPC submit/login node so it
# can sbatch the workers and the workers can connect back.
#
# Usage (from inside ssdsims_pipeline/study_small_hpc/, on the submit node):
#   Rscript run.R

library(targets)

# Scope warn = 2 to the scenario "science" (the ssd_fit_dists / ssd_gen /
# ssd_hc calls in scenario.R, where a numeric warning signals a real problem),
# then restore the default handler. As a persistent global it also promoted a
# benign gzfile "No space left on device" warning - raised while serialising a
# subprocess result - into a fatal crash.
old_warn <- options(warn = 2)
source("scenario.R")
options(old_warn)

# Temp-space guard: HPC login nodes often have a tiny, shared /tmp. When it
# fills, callr's result serialisation (a gzfile write for each subprocess
# result) fails with "No space left on device". Point the tempdir inherited by
# the tar_make() callr subprocess at a roomier scratch location. R fixes THIS
# session's tempdir() at startup, so `export TMPDIR=...` before running for full
# cover (see README); setting it here still redirects the child processes
# spawned below, which is where the failure occurred.
scratch_tmp <- Sys.getenv(
  "SSDSIMS_TMPDIR",
  unset = Sys.getenv(
    "SCRATCH",
    unset = file.path(Sys.getenv("HOME"), "scratch", "rtmp")
  )
)
dir.create(scratch_tmp, showWarnings = FALSE, recursive = TRUE)
Sys.setenv(TMPDIR = scratch_tmp, TMP = scratch_tmp, TEMP = scratch_tmp)

started <- Sys.time()
tar_make()
elapsed <- as.numeric(Sys.time() - started, units = "secs")

summary_paths <- tar_read(summary)

cat("\n=== summary ===\n")
cat(sprintf("summary parquet : %s\n", paste(summary_paths, collapse = ", ")))
cat(sprintf("results dir     : %s\n", ssdsims::scenario_results_dir(scenario)))
cat(sprintf("wall time       : %.1fs\n", elapsed))

summary_tbl <- tibble::as_tibble(dplyr::collect(
  duckplyr::read_parquet_duckdb(
    summary_paths[[1L]],
    options = list(hive_partitioning = FALSE)
  )
))
cat(sprintf("hc rows         : %d\n", nrow(summary_tbl)))
cat("\nfirst rows:\n")
print(utils::head(summary_tbl, 10L))

cat("\nNext: Rscript make_figure.R\n")
