#!/usr/bin/env Rscript
options(warn = 2)

# Driver: build the 20-dataset bias/coverage/CI-width scenario through a
# local crew controller, then point at make_figure.R to build the plot.
#
# Usage (from inside ssdsims_pipeline/study_small/):
#   Rscript run.R

library(targets)

source("scenario.R")

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
