# scenario.R - the 20-dataset bias/coverage/CI-width study (reproduces
# Images/ssdata_sims_collated.png), sourced by _targets.R to build the
# crew-local targets pipeline.
#
# Methodology (matches min_sample_size.Rmd): for each of the 20 ssddata
# example datasets, fit the BCANZ default distributions and take the
# top-AICc-weighted distribution as the "true" data-generating model.
# ssd_gen() does exactly this when given a multi-distribution `fitdists`
# object (see ?ssd_gen: "a fitdists object: the top-weighted distribution is
# selected and drawn as for a tmbfit"), so each dataset's own best-fit model
# is what ssd_scenario_data() resamples from. Re-fit with the model-averaged
# ("multi") set across a sweep of N, with bootstrap confidence intervals via
# the recommended "weighted_samples" method.
#
# ONE scenario (`ssd_define_scenario()` below) run via `ssd_scenario_targets()`,
# not `ssd_design_targets()`/`ssd_design()`. `nsim` is scaled down from the
# original study's 1000 - see the comment on `nsim` below for sizing.

library(ssdsims)
library(ssddata)
library(ssdtools)

dataset_names <- names(ssd_data_sets(c("anzg", "ccme")))

# HC proportions matching Figure 2's three columns (0.01, 0.05, 0.1, 0.2).
proportions <- c(0.01, 0.05, 0.1, 0.2)

# ---- fit the 20 datasets (cached) ------------------------------------------

if (!dir.exists("cache")) {
  dir.create("cache", recursive = TRUE)
}
fits_cache <- "cache/fits.rds"

if (file.exists(fits_cache)) {
  fits <- readRDS(fits_cache)
} else {
  fits <- lapply(dataset_names, function(nm) {
    data <- get(nm, envir = asNamespace("ssddata"))
    ssd_fit_dists(data, dists = ssd_dists_bcanz())
  })
  names(fits) <- dataset_names
  saveRDS(fits, fits_cache)
}

# ---- "true" HCx values for bias/coverage, from each dataset's own
# top-weighted distribution (the same selection ssd_gen() makes internally) --

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
  # nsim: original study used 1000. ssd_estimate_cost() is a poor guide here -
  # it badly underestimates wall time for this scenario shape, because each
  # hc shard bundles ALL 7 nrow values x 3 proportions x nboot=1000 into ONE
  # task (the default hc bundle/partition_by), not one task per cell. Measured
  # directly: ~2.2-2.5 min per (dataset, sim) hc task regardless of nrow, so
  # total serial cost is ~ 20 datasets x nsim x 2.5 min. nsim = 15 below is
  # ~2.78 x 15 =~ 42 min wall time at the 18 workers _targets.R configures (no
  # contention from other jobs on the machine). Raise nsim and budget
  # accordingly; re-time a small pilot (nsim = 2L or 3L) after any change to
  # nboot/proportion/dists, since those change the per-task cost too.
  nsim = 15L,
  seed = 42L,
  nrow = c(5L, 6L, 7L, 8L, 10L, 16L, 26L),
  dists = ssd_distset(BCANZ = ssd_dists_bcanz()),
  est_method = "multi",
  proportion = proportions,
  ci = TRUE,
  nboot = 1000,
  ci_method = "weighted_samples"
)
