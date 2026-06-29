# scenario.R - the combined ssddata + EnviroTox study (reproduces
# Images/all_sims_bias.png and Images/weights_collated.png), sourced by
# _targets.R to build the crew-local targets pipeline.
#
# Same methodology as ../study_small/scenario.R (each dataset's own
# top-AICc-weighted BCANZ distribution is the "true" generating model,
# resampled via ssd_gen()), but over a larger combined corpus and with
# ci = FALSE - matching the original report, which did not attempt
# bootstrap CIs for this larger run due to compute cost.
#
# Dataset corpus: the same 20 ssddata "v1" datasets as study_small, plus
# the EnviroTox acute-toxicity chemicals meeting the Yanagihara et al.
# (2024) criteria (bimodality coefficient <= 0.555, >= 10 species, >= 3
# trophic groups), via the `Yanagihara24` column on `ssddata::envirotox_acute`
# - only present in the `ssddata@dev` branch (poissonconsulting/ssddata is
# the stable release; this report's EnviroTox data lives on
# open-AIMS/ssddata@dev, installed locally with
# `remotes::install_local(<path-to-ssddata@dev-checkout>)`).
#
# IMPORTANT - this does not reproduce the original report's N = 353 exactly:
# the Yanagihara24 filter on EnviroTox 2.0 here yields 285 chemicals, not
# the ~333 in the original paper (database version/aggregation differences),
# so this scenario covers 20 + 285 = 305 datasets, not 353.
#
# nrow sweep: a single sweep covering both target figures - fine-grained
# 5:16 (what Figure 3/all_sims_bias.png plots, zoomed to small N, the focus
# of this report) plus sparser high-N checkpoints 32/64/128/256 (what Figure
# 4/weights_collated.png plots, to show AICc weight convergence at large N).
# One scenario covers both rather than two (a `ssd_design()` of a "coarse"
# and a "dense" scenario, as the upstream large/ example does) per request.

library(ssdsims)
library(ssddata)
library(ssdtools)
library(dplyr)

v1_names <- c(
  "aims_aluminium_marine", "aims_gallium_marine", "aims_molybdenum_marine",
  "anon_a", "anon_b", "anon_c", "anon_d", "anon_e",
  "anzg_metolachlor_fresh",
  "ccme_boron", "ccme_cadmium", "ccme_chloride", "ccme_endosulfan",
  "ccme_glyphosate", "ccme_silver", "ccme_uranium",
  "csiro_chlorine_marine", "csiro_cobalt_marine", "csiro_lead_marine",
  "csiro_nickel_fresh"
)

proportions <- c(0.05, 0.1, 0.2)
nrow_sweep <- c(5:16, 32L, 64L, 128L, 256L)

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

# ---- assemble the 305-dataset corpus (cached) ------------------------------

data_cache <- "cache/all_data.rds"
lookup_cache <- "cache/envirotox_lookup.rds"

if (file.exists(data_cache)) {
  all_data <- readRDS(data_cache)
} else {
  if (!"Yanagihara24" %in% names(ssddata::envirotox_acute)) {
    stop(
      "ssddata::envirotox_acute has no `Yanagihara24` column - this needs ",
      "the open-AIMS/ssddata@dev branch installed, not the CRAN release. ",
      "See the comment at the top of this file."
    )
  }

  v1_data <- lapply(v1_names, function(nm) {
    get(nm, envir = asNamespace("ssddata"))[, "Conc", drop = FALSE]
  })
  names(v1_data) <- v1_names

  y24 <- ssddata::envirotox_acute[ssddata::envirotox_acute$Yanagihara24, ]
  splits <- split(y24, y24$Chemical)
  chem_names <- sort(names(splits))
  envirotox_data <- lapply(chem_names, function(ch) splits[[ch]][, "Conc", drop = FALSE])
  ids <- sprintf("envirotox_%03d", seq_along(chem_names))
  names(envirotox_data) <- ids

  saveRDS(tibble(id = ids, chemical = chem_names), lookup_cache)

  all_data <- c(v1_data, envirotox_data)
  saveRDS(all_data, data_cache)
}

dataset_names <- names(all_data)

# ---- fit BCANZ to every dataset (cached) -----------------------------------

fits_cache <- "cache/fits.rds"

if (file.exists(fits_cache)) {
  fits <- readRDS(fits_cache)
} else {
  fits <- lapply(dataset_names, function(nm) {
    ssd_fit_dists(all_data[[nm]], dists = ssd_dists_bcanz())
  })
  names(fits) <- dataset_names
  saveRDS(fits, fits_cache)
}

# ---- per-dataset source (top-weighted) distribution + true HCx (cached) ---

source_dist_cache <- "cache/source_dist.rds"
true_hc_cache <- "cache/true_hc.rds"

if (file.exists(source_dist_cache) && file.exists(true_hc_cache)) {
  source_dist <- readRDS(source_dist_cache)
  true_hc <- readRDS(true_hc_cache)
} else {
  source_dist <- vapply(dataset_names, function(nm) {
    gl <- ssdtools::glance(fits[[nm]], wt = TRUE)
    gl$dist[which.max(gl$wt)]
  }, character(1))
  source_dist <- tibble(dataset = dataset_names, source_dist = source_dist)
  saveRDS(source_dist, source_dist_cache)

  true_hc <- bind_rows(lapply(dataset_names, function(nm) {
    best_dist <- source_dist$source_dist[source_dist$dataset == nm]
    single_fit <- ssd_fit_dists(all_data[[nm]], dists = best_dist)
    hc <- ssd_hc(single_fit, proportion = proportions, ci = FALSE)
    tibble(
      dataset = nm,
      source_dist = best_dist,
      proportion = hc$proportion,
      true_est = hc$est
    )
  }))
  saveRDS(true_hc, true_hc_cache)
}

# ---- the scenario -----------------------------------------------------------

gen_args <- fits
gen_args$.n <- 1000L
gen_args$.seed <- 42L
gen <- do.call(ssd_gen, gen_args)

data <- ssd_scenario_data(!!!gen)

scenario <- ssd_define_scenario(
  data,
  # nsim: conservative starting default. ~0.3-0.9s per fit task was measured
  # directly (305 datasets x 16 nrow values = 4880 fit tasks at nsim = 1, the
  # ci = FALSE hc step is comparatively cheap), so nsim = 10 is roughly
  # 4880 x 10 x ~0.5s =~ 6.8 hours of serial fit-step compute, ~23 min wall at
  # the 18 workers _targets.R configures - IF those workers have the machine
  # to themselves. That part is unvalidated: development hit heavy, unrelated
  # CPU contention from another job on the same machine, which is why this
  # number comes from the per-task rate above rather than a timed full run.
  # Run check_prereqs.R yourself when the machine is free, or pilot with
  # nsim = 1L first and time it, before trusting this default.
  nsim = 10L,
  seed = 42L,
  nrow = nrow_sweep,
  dists = ssd_distset(BCANZ = ssd_dists_bcanz()),
  est_method = "multi",
  proportion = proportions,
  ci = FALSE
)
