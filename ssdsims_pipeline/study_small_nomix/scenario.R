# scenario.R - a small, local, tractable variant of study_small that DROPS the
# 5-parameter lnorm_lnorm mixture from the candidate set.
#
# Motivation: in study_small(_hpc) the model-averaged N=5 estimates are dominated
# by the lnorm_lnorm mixture purely because of an AICc small-sample-correction
# degeneracy (the correction 2k(k+1)/(n-k-1) rewards a k=5 model at n=5; see
# ../study_small_hpc/ssdtools-aicc-issue.md). This scenario removes that
# distribution so we can ask: is "N=5 is materially worse than N=6" still true
# once the degeneracy is gone, or was the jump largely an artefact of the mixture?
#
# Everything else mirrors study_small: fit each of the 41 ssddata datasets with
# the reduced BCANZ set, take the top-AICc distribution as the "true" generating
# model, resample, and re-fit with model averaging over the same reduced set.
# Sized down to run locally in ~30 min.

library(ssdsims)
library(ssddata)
library(ssdtools)

dataset_names <- names(ssd_data_sets(c("anzg", "ccme")))

# BCANZ default set MINUS the lognormal-lognormal mixture -> five 2-parameter
# unimodal distributions, for which AICc is well defined at N >= 4 (npars + 2).
dists_nomix <- setdiff(ssd_dists_bcanz(), "lnorm_lnorm")

proportions <- c(0.01, 0.05, 0.1, 0.2)

# ---- fit the 41 datasets with the reduced set (cached) ---------------------

if (!dir.exists("cache")) {
  dir.create("cache", recursive = TRUE)
}
fits_cache <- "cache/fits.rds"

if (file.exists(fits_cache)) {
  fits <- readRDS(fits_cache)
} else {
  fits <- lapply(dataset_names, function(nm) {
    data <- get(nm, envir = asNamespace("ssddata"))
    ssd_fit_dists(data, dists = dists_nomix)
  })
  names(fits) <- dataset_names
  saveRDS(fits, fits_cache)
}

# ---- "true" HCx from each dataset's own top-weighted (unimodal) distribution -

true_hc_cache <- "cache/true_hc.rds"

if (file.exists(true_hc_cache)) {
  true_hc <- readRDS(true_hc_cache)
} else {
  true_hc <- do.call(
    rbind,
    lapply(dataset_names, function(nm) {
      gl <- ssdtools::glance(fits[[nm]], wt = TRUE)
      best_dist <- gl$dist[which.max(gl$wt)]
      data <- get(nm, envir = asNamespace("ssddata"))
      single_fit <- ssd_fit_dists(data, dists = best_dist)
      hc <- ssd_hc(single_fit, proportion = proportions, ci = FALSE)
      data.frame(
        dataset = nm,
        source_dist = best_dist,
        proportion = hc$proportion,
        true_est = hc$est
      )
    })
  )
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
  # Tractable defaults: nsim=30, N focused on the 5-vs-6 question, nboot=200.
  # ~0.2 min per (dataset, sim) hc task x 41 datasets x 30 sims ~= 246 core-min
  # -> ~30 min wall at the 8 local workers _targets.R uses (8, not more, to stay
  # within RAM). 30 sims x 41 datasets = 1230 obs/N is ample for pooled coverage.
  # Set STUDY_SMALL_NOMIX_NSIM=2 for a fast pilot after any nboot/proportion/dists change.
  nsim = as.integer(Sys.getenv("STUDY_SMALL_NOMIX_NSIM", unset = "30")),
  seed = 42L,
  nrow = c(5L, 6L, 7L, 8L),
  dists = ssd_distset(BCANZ_no_mix = dists_nomix),
  est_method = "multi",
  proportion = proportions,
  ci = TRUE,
  nboot = 200,
  ci_method = "weighted_samples"
)
