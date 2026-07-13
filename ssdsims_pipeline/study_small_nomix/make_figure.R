#!/usr/bin/env Rscript

# make_figure.R - summarise the mixture-excluded study_small_nomix: coverage, median
# relative bias, and median relative CI width by HC proportion and N, with the
# N=5-vs-N=6 comparison front and centre. Writes a coverage figure and a summary
# CSV, and prints the by-N table. Run after run.R.

suppressPackageStartupMessages({
  library(ssdsims)
  library(dplyr)
  library(ggplot2)
})

old_warn <- options(warn = 2)
source("scenario.R") # scenario, true_hc
options(old_warn)

results_dir <- ssdsims::scenario_results_dir(scenario)
summary_path <- file.path(results_dir, "summary.parquet")
if (!file.exists(summary_path)) {
  stop("No summary.parquet at ", summary_path, " - run `Rscript run.R` first.")
}

summary_tbl <- tibble::as_tibble(dplyr::collect(
  duckplyr::read_parquet_duckdb(summary_path, options = list(hive_partitioning = FALSE))))

hc_tasks <- ssd_scenario_hc_tasks(scenario)[, c("hc_id", "dataset", "sim", "nrow")]

res <- summary_tbl |>
  left_join(hc_tasks, by = "hc_id") |>
  left_join(true_hc[, c("dataset", "proportion", "true_est")],
    by = c("dataset", "proportion")) |>
  mutate(
    bias = (est - true_est) / true_est,
    width = (ucl - lcl) / true_est,
    covered = as.integer(true_est >= lcl & true_est <= ucl)
  )

tab <- res |>
  group_by(proportion, nrow) |>
  summarise(coverage = mean(covered), median_bias = median(bias),
    median_width = median(width), n = n(), .groups = "drop") |>
  arrange(proportion, nrow)

# Write the shareable summary CSV/figure into this folder (tracked) rather than
# ../output (git-ignored scratch), matching study_small_hpc's committed-CSV layout.
write.csv(tab, "study_small_nomix_summary_table.csv", row.names = FALSE)

cat("=== coverage / median bias / median width by N (lnorm_lnorm mixture removed) ===\n")
print(tab |> mutate(across(c(coverage, median_bias, median_width), \(x) round(x, 3))), n = Inf)

props <- sort(unique(res$proportion))
cov_df <- res |>
  group_by(dataset, nrow, proportion) |>
  summarise(coverage = mean(covered), .groups = "drop") |>
  mutate(N = factor(nrow), prop = factor(proportion, levels = props,
    labels = paste0("HC", 100 * props)))

p <- ggplot(cov_df, aes(N, coverage)) +
  geom_hline(yintercept = 0.95, linetype = 2, colour = "grey40") +
  geom_boxplot(outlier.size = 0.4) +
  facet_wrap(~prop, nrow = 1) +
  scale_y_continuous(limits = c(0, 1)) +
  labs(x = "N", y = "Coverage (fraction covering true)",
    title = "study_small_nomix: coverage with the lnorm_lnorm mixture removed") +
  theme_bw(base_size = 10)
ggsave("study_small_nomix_coverage.png", p, width = 9, height = 3.5, dpi = 150)

cat("\nWrote study_small_nomix_coverage.png and study_small_nomix_summary_table.csv\n")
