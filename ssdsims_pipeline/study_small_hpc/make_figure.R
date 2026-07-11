#!/usr/bin/env Rscript

# make_figure.R - reproduces Images/ssdata_sims_collated.png (Figure 2) from
# the study_small run: relative bias, scaled CI width, and coverage as a
# function of N, faceted by HC proportion.
#
# Run after run.R (Rscript run.R) has built the pipeline.
#
# Notes on the summary table: ssdtools::ssd_hc() can fall back from the
# requested est_method/ci_method ("multi"/"weighted_samples") to a
# single-distribution percentile bootstrap at very small N when model
# averaging is unstable (observed at nrow = 5 during development - itself
# a small illustration of why N = 5 is the boundary this report is about).
# Every hc task still yields exactly one row per requested proportion
# regardless of which method was actually used, so no `dist`/`ci_method`
# filtering is needed below - every row is used as-is.

suppressPackageStartupMessages({
  library(ssdsims)
  library(dplyr)
  library(ggplot2)
  library(patchwork)
})

# Scope warn = 2 to the scenario "science" only, then restore the default - see
# run.R / _targets.R for why (a persistent global turns benign read/plot
# warnings fatal).
old_warn <- options(warn = 2)
source("scenario.R") # defines `scenario`, `true_hc`
options(old_warn)

results_dir <- ssdsims::scenario_results_dir(scenario)
summary_path <- file.path(results_dir, "summary.parquet")
if (!file.exists(summary_path)) {
  stop("No summary.parquet found at ", summary_path, " - run `Rscript run.R` first.")
}

# Read the single summary Parquet via duckplyr (already a pipeline dependency),
# mirroring run.R - avoids the arrow package, which isn't installed on the HPC.
# hive_partitioning = FALSE because summary.parquet is a flat, unpartitioned file.
summary_tbl <- tibble::as_tibble(dplyr::collect(
  duckplyr::read_parquet_duckdb(
    summary_path,
    options = list(hive_partitioning = FALSE)
  )
))

hc_tasks <- ssd_scenario_hc_tasks(scenario)[, c("hc_id", "dataset", "sim", "nrow")]

results <- summary_tbl |>
  left_join(hc_tasks, by = "hc_id") |>
  left_join(true_hc[, c("dataset", "proportion", "true_est")],
    by = c("dataset", "proportion")) |>
  mutate(
    bias = (est - true_est) / true_est,
    width = (ucl - lcl) / true_est,
    covered = as.integer(true_est >= lcl & true_est <= ucl)
  )

# ---- panels A/B: bias and width, pooled across datasets and sims per N ----

bias_df <- results |>
  transmute(nrow, proportion, metric = "A: bias ([est-true]/true)", value = bias)

width_df <- results |>
  transmute(nrow, proportion, metric = "B: width ((ucl-lcl)/true)", value = width)

# ---- panel C: coverage, proportion of sims covering true HCx, per dataset --

coverage_df <- results |>
  group_by(dataset, nrow, proportion) |>
  summarise(value = mean(covered), .groups = "drop") |>
  transmute(nrow, proportion, metric = "C: coverage (fraction of sims & datasets)", value)

plot_df <- bind_rows(bias_df, width_df, coverage_df) |>
  mutate(
    small_n = nrow <= 6,
    nrow = factor(nrow, levels = sort(unique(nrow))),
    proportion = factor(proportion, levels = sort(unique(proportion)))
  )

fig2 <- ggplot(plot_df, aes(x = nrow, y = value, fill = small_n)) +
  geom_boxplot(outlier.size = 0.5) +
  facet_grid(metric ~ proportion, scales = "free_y") +
  scale_fill_manual(values = c(`TRUE` = "#F8766D", `FALSE` = "#00BFC4"), guide = "none") +
  labs(x = "N", y = NULL) +
  theme_bw(base_size = 10)

if (!dir.exists("../output")) dir.create("../output", recursive = TRUE)
ggsave("../output/ssdata_sims_collated.png", fig2, width = 10, height = 8, dpi = 150)

cat("Wrote ../output/ssdata_sims_collated.png\n")
