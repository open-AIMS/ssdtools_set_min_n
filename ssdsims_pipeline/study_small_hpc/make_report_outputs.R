#!/usr/bin/env Rscript

# make_report_outputs.R - reporting outputs for the study_small_hpc run:
#
#   1. study_small_report_figure.png - a 3-panel figure (relative
#      bias, relative CI width, coverage) vs N, faceted by HC proportion, with
#      bias on a SYMMETRIC-log and width on a LOG10 y-axis. The small-N /
#      small-proportion extremes (bias up to ~6.7e8, width up to ~7.8e9) flatten
#      make_figure.R's shared linear facet_grid to near-zero; log axes make the
#      box structure legible instead.
#
#   2. study_small_summary_table.csv - median relative bias, its IQR,
#      median relative CI width, and coverage, by proportion x N.
#
#   3. source_weights_summary.csv - mean re-fitted AICc weight per
#      (source_dist, nrow, distribution), averaged over datasets and sims. Feeds
#      the two per-source distribution-weight figures (2024 addendum Fig 4).
#
#   4. bias_by_source_summary.csv - median relative bias (+Q25/Q75), median
#      relative CI width, and coverage per (source_dist, nrow, proportion). Feeds
#      the per-source bias/coverage figures (2024 addendum Fig 3).
#
#   5. fit_weights_quantiles.csv - q10/q25/q50/q75/q90 of the re-fitted AICc
#      weight ACROSS the 500 simulations, per (dataset, nrow, distribution). This
#      is the ONLY committed source of between-simulation spread for the weight
#      figures: source_weights_summary.csv (3) and the committed
#      fit_weights_summary.csv both average that spread away. It is derived from
#      the git-ignored per-sim fit_weights_observed.csv and committed so the report
#      can render the spread from a clean clone (Stage 1 committed-derived pattern).
#
# For (3) and (4) source_dist is taken from cache/true_hc.rds (via scenario.R) -
# the distribution ssd_gen() actually sampled from - NOT from dataset_aicc_weights.csv.
#
# Why a separate script from make_figure.R: the three panels need DIFFERENT
# y-transforms, and facet_grid cannot carry a per-row scale. So each panel is a
# standalone ggplot combined with patchwork. make_figure.R (the exact Figure 2
# reproduction) is left unchanged.
#
# Bias is signed (min exactly -1 when est = 0; ~45% of rows negative) with a
# huge positive tail, so a symmetric ("pseudo") log is used - a plain log would
# drop every negative. Width is strictly positive (no zeros/NAs), so log10 is
# fine. See the exploration that established this in the session notes.

suppressPackageStartupMessages({
  library(ssdsims)
  library(dplyr)
  library(ggplot2)
  library(patchwork)
})

# Scope warn = 2 to the scenario "science" only (see run.R / _targets.R); plot
# and table code below must run under the default handler, or benign ggplot
# deprecation/scale warnings would abort the script.
old_warn <- options(warn = 2)
source("scenario.R") # defines `scenario`, `true_hc`
options(old_warn)

results_dir <- ssdsims::scenario_results_dir(scenario)
summary_path <- file.path(results_dir, "summary.parquet")
if (!file.exists(summary_path)) {
  stop("No summary.parquet found at ", summary_path,
    " - pull it from the HPC first (see HPC_WORKFLOW_RUNBOOK.md).")
}

summary_tbl <- tibble::as_tibble(dplyr::collect(
  duckplyr::read_parquet_duckdb(
    summary_path,
    options = list(hive_partitioning = FALSE)
  )
))

hc_tasks <- ssd_scenario_hc_tasks(scenario)[, c("hc_id", "dataset", "sim", "nrow")]

props <- sort(unique(summary_tbl$proportion))

results <- summary_tbl |>
  left_join(hc_tasks, by = "hc_id") |>
  left_join(true_hc[, c("dataset", "proportion", "true_est")],
    by = c("dataset", "proportion")) |>
  mutate(
    bias = (est - true_est) / true_est,
    width = (ucl - lcl) / true_est,
    covered = as.integer(true_est >= lcl & true_est <= ucl),
    N = factor(nrow, levels = sort(unique(nrow))),
    small_n = nrow <= 6,
    # Facet label per HC proportion: 0.01 -> "HC1", 0.05 -> "HC5", etc.
    prop_lab = factor(proportion,
      levels = props, labels = paste0("HC", 100 * props))
  )

# ---- figure -----------------------------------------------------------------

fill_small <- scale_fill_manual(
  values = c(`TRUE` = "#F8766D", `FALSE` = "#00BFC4"), guide = "none")
base_theme <- theme_bw(base_size = 10)
no_x <- theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())

# A: relative bias, symmetric-log y (sigma = 1: near-linear within +/-1, where
# the medians and IQRs sit, then log-compresses the extreme tails).
panel_a <- ggplot(results, aes(N, bias, fill = small_n)) +
  geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
  geom_boxplot(outlier.size = 0.3, linewidth = 0.3) +
  facet_grid(. ~ prop_lab) +
  scale_y_continuous(
    trans = scales::pseudo_log_trans(sigma = 1, base = 10),
    breaks = c(-1, 0, 1, 10, 1e2, 1e4, 1e6, 1e8),
    labels = scales::label_number(scale_cut = scales::cut_short_scale())
  ) +
  fill_small + base_theme + no_x +
  labs(x = NULL, y = "Relative bias\n(est - true)/true")

# B: relative CI width, log10 y (strictly positive).
panel_b <- ggplot(results, aes(N, width, fill = small_n)) +
  geom_boxplot(outlier.size = 0.3, linewidth = 0.3) +
  facet_grid(. ~ prop_lab) +
  scale_y_log10(labels = scales::label_log()) +
  fill_small + base_theme + no_x +
  theme(strip.text = element_blank()) +
  labs(x = NULL, y = "Relative CI width\n(ucl - lcl)/true")

# C: coverage per dataset (fraction of that dataset's sims covering true HCx),
# linear y with the nominal 0.95 reference.
coverage_df <- results |>
  group_by(dataset, N, small_n, prop_lab) |>
  summarise(coverage = mean(covered), .groups = "drop")

panel_c <- ggplot(coverage_df, aes(N, coverage, fill = small_n)) +
  geom_hline(yintercept = 0.95, linetype = 2, linewidth = 0.3, colour = "grey40") +
  geom_boxplot(outlier.size = 0.3, linewidth = 0.3) +
  facet_grid(. ~ prop_lab) +
  scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
  fill_small + base_theme +
  theme(strip.text = element_blank()) +
  labs(x = "N (sample size)", y = "Coverage\n(fraction covering true)")

fig <- panel_a / panel_b / panel_c +
  plot_annotation(
    title = "HCx estimation vs sample size (red = N <= 6)",
    subtitle = "Bias: symmetric-log; CI width: log10; coverage: linear, dashed line = nominal 0.95"
  )

# Write the two headline artefacts into this folder (tracked) so report.qmd
# renders from a clean checkout, matching the committed-CSV convention here. The
# heavy summary.parquet they derive from stays git-ignored on the HPC results dir.
ggsave("study_small_report_figure.png", fig,
  width = 10, height = 9, dpi = 150)
cat("Wrote study_small_report_figure.png\n")

# ---- table ------------------------------------------------------------------

summary_table <- results |>
  group_by(proportion, nrow) |>
  summarise(
    n_sims = n(),
    coverage = mean(covered),
    bias_median = median(bias),
    bias_q25 = quantile(bias, 0.25),
    bias_q75 = quantile(bias, 0.75),
    width_median = median(width),
    .groups = "drop"
  ) |>
  arrange(proportion, nrow)

write.csv(summary_table, "study_small_summary_table.csv", row.names = FALSE)
cat("Wrote study_small_summary_table.csv\n\n")

# Console preview, rounded for readability (CSV keeps full precision).
print(
  summary_table |>
    mutate(across(c(coverage, bias_median, bias_q25, bias_q75), \(x) round(x, 3)),
      width_median = round(width_median, 2)),
  n = Inf
)

# ---- per-source summaries (2024 addendum Figs 3 & 4) ------------------------
#
# source_dist comes from cache/true_hc.rds (loaded by scenario.R as `true_hc`) -
# the distribution ssd_gen() sampled from - so these summaries do not depend on
# dataset_aicc_weights.csv. n_datasets is carried through so thin panels (the
# lnorm_lnorm source has a single dataset, anzg_iron_marine) are visible.
source_map <- unique(true_hc[, c("dataset", "source_dist")])

# (3) mean re-fitted AICc weight by (source_dist, nrow, distribution). Reads the
# committed per-dataset means (already averaged over the 500 sims) and averages
# those over the datasets sharing a source distribution.
source_weights_summary <- read.csv("fit_weights_summary.csv") |>
  left_join(source_map, by = "dataset") |>
  group_by(source_dist, nrow, distribution) |>
  summarise(
    mean_weight = mean(mean_weight),
    n_datasets = n_distinct(dataset),
    .groups = "drop"
  ) |>
  arrange(source_dist, nrow, distribution)

write.csv(source_weights_summary, "source_weights_summary.csv", row.names = FALSE)
cat(sprintf("Wrote source_weights_summary.csv (%d rows)\n", nrow(source_weights_summary)))

# (5) simulation-level quantiles of the re-fitted AICc weight per
# (dataset, nrow, distribution). fit_weights_observed.csv is the raw per-sim
# weight (one row per dataset x sim x nrow, one column per distribution) and is
# git-ignored; here we collapse only the 500 sims WITHIN each dataset into
# quantiles, keeping the dataset dimension so the figures can show both
# between-dataset points and the between-simulation range. Skipped with a warning
# if the observed file is absent (e.g. a clean clone) - the committed CSV still
# lets the report render.
obs_path <- "fit_weights_observed.csv"
if (file.exists(obs_path)) {
  dists_obs <- c("gamma", "lgumbel", "llogis", "lnorm", "lnorm_lnorm", "weibull")
  probs <- c(q10 = 0.10, q25 = 0.25, q50 = 0.50, q75 = 0.75, q90 = 0.90)

  fit_weights_quantiles <- read.csv(obs_path) |>
    tidyr::pivot_longer(all_of(dists_obs),
      names_to = "distribution", values_to = "weight") |>
    group_by(dataset, nrow, distribution) |>
    summarise(
      n_sims = n(),
      q10 = quantile(weight, probs[["q10"]]),
      q25 = quantile(weight, probs[["q25"]]),
      q50 = quantile(weight, probs[["q50"]]),
      q75 = quantile(weight, probs[["q75"]]),
      q90 = quantile(weight, probs[["q90"]]),
      .groups = "drop"
    ) |>
    arrange(dataset, nrow, distribution)

  write.csv(fit_weights_quantiles, "fit_weights_quantiles.csv", row.names = FALSE)
  cat(sprintf("Wrote fit_weights_quantiles.csv (%d rows)\n", nrow(fit_weights_quantiles)))
} else {
  warning("fit_weights_observed.csv not found; ",
    "fit_weights_quantiles.csv NOT regenerated (committed copy retained).")
}

# (4) bias / CI width / coverage by (source_dist, nrow, proportion), from the
# per-sim `results` built above (recovers dataset via hc_id -> hc_tasks).
bias_by_source_summary <- results |>
  left_join(source_map, by = "dataset") |>
  group_by(source_dist, nrow, proportion) |>
  summarise(
    n_sims = n(),
    n_datasets = n_distinct(dataset),
    coverage = mean(covered),
    bias_median = median(bias),
    bias_q25 = quantile(bias, 0.25),
    bias_q75 = quantile(bias, 0.75),
    width_median = median(width),
    .groups = "drop"
  ) |>
  arrange(source_dist, nrow, proportion)

write.csv(bias_by_source_summary, "bias_by_source_summary.csv", row.names = FALSE)
cat(sprintf("Wrote bias_by_source_summary.csv (%d rows)\n", nrow(bias_by_source_summary)))
