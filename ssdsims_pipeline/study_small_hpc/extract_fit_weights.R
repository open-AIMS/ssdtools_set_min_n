#!/usr/bin/env Rscript

# extract_fit_weights.R - run ON THE HPC (needs `module load R/4.4.1` so the
# pipeline's package library, incl. duckplyr/ssdsims, is on the path).
#
# The hc `summary.parquet` does not contain the per-distribution AICc weights of
# the re-fitted models - those live only in the `fit` shards, one ~1.2 MB
# ASCII-serialised `fitdists` object per (dataset, sim, nrow) in the `fit_blob`
# column (fit shards are partitioned by `sim` only; dataset/nrow are carried in
# `fit_id`). This decodes each blob, reads the AICc weights the fit step already
# computed via `ssdtools::glance(wt = TRUE)`, and writes a compact CSV keyed by
# (dataset, sim, nrow) so the small result - not the 55 GB of shards - is what
# gets pulled to WSL.
#
# Usage (from study_small_hpc/ on the HPC):
#   module load R/4.4.1
#   Rscript extract_fit_weights.R            # all sims
#   Rscript extract_fit_weights.R 2          # first 2 sim files (timing test)

suppressPackageStartupMessages({
  library(ssdsims)
  library(ssdtools)
  library(dplyr)
  library(duckplyr)
})

source("scenario.R") # defines `scenario` (uses cache/, no refit)

args <- commandArgs(trailingOnly = TRUE)
max_sims <- if (length(args)) as.integer(args[[1]]) else Inf

dists <- ssd_dists_bcanz()

# fit_id -> (dataset, sim, nrow); the fit shards carry only fit_id + blob.
fit_tasks <- ssdsims::ssd_scenario_fit_tasks(scenario)[, c("fit_id", "dataset", "sim", "nrow")]

fit_dir <- file.path(ssdsims::scenario_results_dir(scenario), "fit")
files <- Sys.glob(file.path(fit_dir, "sim=*", "part.parquet"))
if (is.finite(max_sims)) files <- utils::head(files, max_sims)
cat(sprintf("Decoding %d fit-shard file(s) from %s\n", length(files), fit_dir))

# Decode is embarrassingly parallel across shard files. Cores come from
# EXTRACT_CORES (default SLURM_CPUS_PER_TASK, else 1). Each fork opens its own
# duckdb connection inside process_file(), so nothing is shared across the fork.
ncores <- as.integer(Sys.getenv("EXTRACT_CORES",
  unset = Sys.getenv("SLURM_CPUS_PER_TASK", unset = "1")))
cat(sprintf("Using %d core(s)\n", ncores))

process_file <- function(f) {
  d <- dplyr::collect(duckplyr::read_parquet_duckdb(
    f, options = list(hive_partitioning = FALSE)))
  rows <- lapply(seq_len(nrow(d)), function(i) {
    fit <- unserialize(charToRaw(d$fit_blob[[i]]))
    gl <- ssdtools::glance(fit, wt = TRUE)
    v <- setNames(rep(0, length(dists)), dists)
    v[gl$dist] <- gl$wt
    c(list(fit_id = d$fit_id[[i]]), as.list(v))
  })
  dplyr::bind_rows(rows)
}

t0 <- Sys.time()
out <- parallel::mclapply(files, process_file, mc.cores = ncores)
errs <- vapply(out, function(x) inherits(x, "try-error"), logical(1))
if (any(errs)) stop("failed on ", sum(errs), " shard file(s); first: ",
  conditionMessage(attr(out[[which(errs)[1]]], "condition")))

res <- dplyr::bind_rows(out) |>
  dplyr::left_join(fit_tasks, by = "fit_id") |>
  dplyr::select(dataset, sim, nrow, dplyr::all_of(dists)) |>
  dplyr::arrange(dataset, nrow, sim)

write.csv(res, "fit_weights_observed.csv", row.names = FALSE)
cat(sprintf("Wrote fit_weights_observed.csv: %d rows, %.1f min total\n",
  nrow(res), as.numeric(Sys.time() - t0, units = "mins")))
