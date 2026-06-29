#!/usr/bin/env Rscript

# make_figure_weights.R - reproduces Images/weights_collated.png (Figure 4):
# the AICc weight of (A) each dataset's own source/generating distribution,
# and (B) the lnorm_lnorm mixture specifically, as a function of N, faceted
# by source distribution.
#
# AICc weights are a `fit`-step property (not `hc`/proportion-dependent), so
# this reads the `fit` shard Parquet directly rather than the hc `summary`:
# each shard's `fit_blob` column holds an ASCII-serialised `fitdists` object
# (ssdsims' own encode_obj()/decode_obj() seam, R/targets-runner.R - not
# exported, but it is exactly `serialize(x, ascii = TRUE)`/`unserialize()`,
# reproduced inline below). Decoding it back to a live `fitdists` object lets
# us call `ssdtools::ssd_gof(fit, wt = TRUE)` directly - no refitting, just
# reading the AICc weights the fit step already computed.
#
# Run after run.R (Rscript run.R) has built the pipeline.

suppressPackageStartupMessages({
  library(ssdsims)
  library(ssdtools)
  library(dplyr)
  library(arrow)
  library(ggplot2)
  library(patchwork)
})

source("scenario.R") # defines `scenario`, `source_dist`

results_dir <- ssdsims::scenario_results_dir(scenario)
fit_dir <- file.path(results_dir, "fit")
if (!dir.exists(fit_dir)) {
  stop("No fit shards found at ", fit_dir, " - run `Rscript run.R` first.")
}

cat("Reading fit shards from", fit_dir, "...\n")
# This scenario can produce tens of thousands of small Parquet files (one per
# dataset x sim x nrow). Arrow's dataset discovery over that many small files
# can take a while, especially under disk/CPU contention from other work on
# the machine - if this step seems to hang, that's most likely it, not a bug.
fit_tbl <- arrow::open_dataset(
  fit_dir,
  partitioning = c("dataset", "sim", "nrow", "rescale"),
  hive_style = TRUE,
  format = "parquet"
) |>
  dplyr::select(dataset, sim, nrow, fit_blob) |>
  dplyr::collect()

cat(sprintf("Decoding %d fit shards and computing AICc weights...\n", nrow(fit_tbl)))

dists_bcanz <- ssd_dists_bcanz()

weight_rows <- vector("list", nrow(fit_tbl))
for (i in seq_len(nrow(fit_tbl))) {
  fit_obj <- unserialize(charToRaw(fit_tbl$fit_blob[[i]]))
  gl <- ssdtools::glance(fit_obj, wt = TRUE)
  wts <- setNames(rep(0, length(dists_bcanz)), dists_bcanz)
  wts[gl$dist] <- gl$wt
  weight_rows[[i]] <- as.list(wts)
  if (i %% 5000 == 0) cat(sprintf("  %d / %d\n", i, nrow(fit_tbl)))
}

weights <- bind_rows(weight_rows)
fit_tbl <- bind_cols(fit_tbl[, c("dataset", "sim", "nrow")], weights) |>
  left_join(source_dist, by = "dataset") # adds a `source_dist` label column

# ---- Panel A: weight of each dataset's own source distribution ------------

wt_mat <- as.matrix(fit_tbl[dists_bcanz])
source_col <- wt_mat[cbind(seq_len(nrow(fit_tbl)), match(fit_tbl$source_dist, dists_bcanz))]

panel_a <- fit_tbl |>
  transmute(nrow, source_dist, weight = source_col, panel = "A: weight of source (generating) distribution")

# ---- Panel B: weight of the lnorm_lnorm mixture, regardless of source -----

panel_b <- fit_tbl |>
  transmute(nrow, source_dist, weight = lnorm_lnorm, panel = "B: weight of lnorm_lnorm mixture")

plot_df <- bind_rows(panel_a, panel_b) |>
  mutate(source_dist = factor(source_dist, levels = dists_bcanz))

fig4 <- ggplot(plot_df, aes(x = nrow, y = weight)) +
  geom_jitter(width = 0.05, height = 0, size = 0.4, alpha = 0.3) +
  scale_x_log10() +
  facet_grid(panel ~ source_dist) +
  labs(x = "N", y = "AICc weight") +
  theme_bw(base_size = 9)

if (!dir.exists("../output")) dir.create("../output", recursive = TRUE)
ggsave("../output/weights_collated.png", fig4, width = 12, height = 7, dpi = 150)

cat("Wrote ../output/weights_collated.png\n")
