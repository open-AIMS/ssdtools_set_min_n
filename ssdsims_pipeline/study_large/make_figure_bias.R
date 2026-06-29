#!/usr/bin/env Rscript

# make_figure_bias.R - reproduces Images/all_sims_bias.png (Figure 3):
# relative bias of HC estimates as a function of N (zoomed to N = 5:16, the
# focus of this report), faceted by HC proportion (columns) and by each
# dataset's source/generating distribution (rows).
#
# Run after run.R (Rscript run.R) has built the pipeline.

suppressPackageStartupMessages({
  library(ssdsims)
  library(dplyr)
  library(arrow)
  library(ggplot2)
})

source("scenario.R") # defines `scenario`, `true_hc`

results_dir <- ssdsims::scenario_results_dir(scenario)
summary_path <- file.path(results_dir, "summary.parquet")
if (!file.exists(summary_path)) {
  stop("No summary.parquet found at ", summary_path, " - run `Rscript run.R` first.")
}

summary_tbl <- tibble::as_tibble(arrow::read_parquet(summary_path))

hc_tasks <- ssd_scenario_hc_tasks(scenario)[, c("hc_id", "dataset", "nrow")]

results <- summary_tbl |>
  left_join(hc_tasks, by = "hc_id") |>
  left_join(true_hc[, c("dataset", "proportion", "source_dist", "true_est")],
    by = c("dataset", "proportion")) |>
  mutate(bias = (est - true_est) / true_est) |>
  filter(nrow <= 16) # Figure 3's zoomed view; weights_collated.png (Figure 4)
                      # uses the full nrow sweep instead.

plot_df <- results |>
  mutate(
    nrow = factor(nrow, levels = sort(unique(nrow))),
    proportion = factor(proportion, levels = sort(unique(proportion))),
    source_dist = factor(source_dist, levels = ssdtools::ssd_dists_bcanz())
  )

fig3 <- ggplot(plot_df, aes(x = nrow, y = bias)) +
  geom_boxplot(outlier.size = 0.4) +
  facet_grid(source_dist ~ proportion) +
  labs(x = "N", y = "bias ([est-true]/true)") +
  theme_bw(base_size = 9)

if (!dir.exists("../output")) dir.create("../output", recursive = TRUE)
ggsave("../output/all_sims_bias.png", fig3, width = 10, height = 9, dpi = 150)

cat("Wrote ../output/all_sims_bias.png\n")
