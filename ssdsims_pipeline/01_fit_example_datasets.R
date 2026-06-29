# Fits the BCANZ default distributions (gamma, lgumbel, llogis, lnorm,
# lnorm_lnorm, weibull) to the 20 ssddata "v1" example datasets used
# throughout this report, and reproduces Figure 1 (Images/fitted_dists.png)
# from those fits: a 20-panel CDF plot, one panel per dataset, each showing
# the data points, the six individual fitted CDFs, and the model-averaged
# ("multi") CDF.
#
# This step does not use ssdsims/targets/crew at all - it operates on the
# *observed* data, not simulated data, so there is nothing to parallelise.
# Run this once; study_small/ and study_large/ each do their own fitting of
# whichever datasets they need (independently, with their own caching), so
# this script is not a dependency of either.
#
# Usage:
#   Rscript 01_fit_example_datasets.R

suppressPackageStartupMessages({
  library(ssdtools)
  library(ssddata)
  library(ggplot2)
  library(patchwork)
})

# The 20 individual single-chemical datasets extracted from ssddata (the
# "v1" set: every named ssddata dataset except the combined `*_data`
# collections and `ssd_fits`). Hardcoded rather than sourced from
# ssddata::ssd_data_sets(set = "v1") (a ssddata@dev-only helper) so this
# script does not depend on the dev branch installed for the EnviroTox data
# (see ../study_large/scenario.R) - these 20 names are present in both.
dataset_names <- c(
  "aims_aluminium_marine", "aims_gallium_marine", "aims_molybdenum_marine",
  "anon_a", "anon_b", "anon_c", "anon_d", "anon_e",
  "anzg_metolachlor_fresh",
  "ccme_boron", "ccme_cadmium", "ccme_chloride", "ccme_endosulfan",
  "ccme_glyphosate", "ccme_silver", "ccme_uranium",
  "csiro_chlorine_marine", "csiro_cobalt_marine", "csiro_lead_marine",
  "csiro_nickel_fresh"
)

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

cache_path <- "cache/example_dataset_fits.rds"

if (file.exists(cache_path)) {
  fits <- readRDS(cache_path)
} else {
  fits <- lapply(dataset_names, function(nm) {
    data <- get(nm, envir = asNamespace("ssddata"))
    ssd_fit_dists(data, dists = ssd_dists_bcanz())
  })
  names(fits) <- dataset_names
  saveRDS(fits, cache_path)
}

# ---- Figure 1: 20-panel CDF plot -------------------------------------------

panels <- lapply(dataset_names, function(nm) {
  ssd_plot_cdf(fits[[nm]], average = NA) +
    ggtitle(nm) +
    theme(
      plot.title = element_text(size = 8),
      axis.title = element_blank(),
      axis.text = element_text(size = 6)
    )
})

fig1 <- patchwork::wrap_plots(panels, ncol = 4, guides = "collect") +
  patchwork::plot_annotation(
    title = "Figure 1. CDF plots and fitted ssdtools CDFs for the 20 example datasets"
  )

if (!dir.exists("output")) dir.create("output", recursive = TRUE)
ggsave("output/fitted_dists.png", fig1, width = 12, height = 10, dpi = 150)

cat("Wrote output/fitted_dists.png and cache/example_dataset_fits.rds\n")
