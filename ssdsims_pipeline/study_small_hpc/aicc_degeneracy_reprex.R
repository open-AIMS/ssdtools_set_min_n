#!/usr/bin/env Rscript

# aicc_degeneracy_reprex.R - a committed, self-contained reproduction of the two
# Stage 0 forensic experiments behind the report's "What the pipeline surfaced:
# the AICc degeneracy" section (and the filed ssdtools issue). It writes two
# committed CSVs:
#
#   aicc_version_comparison.csv   (experiment a: version x arguments x weight)
#   aicc_fit_rate_comparison.csv  (experiment b: Monte Carlo n = 5 fit rate)
#
# WHAT IS BEING SHOWN
# -------------------
# a. The AICc small-sample degeneracy of the 5-parameter lnorm_lnorm mixture is
#    INVARIANT to ssdtools version and to fit arguments. Fitting the 5-point
#    reprex data (and its natural 6- and 7-point extensions) the mixture is handed
#    AICc weight 1.000 at n = 5 (correction 2*5*6/(5-5-1) = -60, a reward), exactly
#    0 at n = 6 (denominator 0 -> AICc = +Inf), and ~9.4e-15 at n = 7 (finite and
#    heavily penalised) - the same in 1.0.6, 2.0.0 and 2.6.0, and under both the
#    native defaults and the lenient (computable = FALSE, at_boundary_ok = TRUE,
#    min_pmix = 0) settings. The criterion, not the engine, produces this.
#
# b. What changed between the 1.0.x and 2.x series is the FIT ENGINE: the
#    over-parameterised mixture is fitted to n = 5 data far more often under 2.x.
#    1000 samples of n = 5 drawn from a unimodal lognormal source are fitted with
#    ssd_dists_bcanz(); we record how often the mixture is present, how often it
#    wins (wt > 0.5), and its mean weight, with a Clopper-Pearson binomial 95% CI
#    on each rate. The fit rate is far lower under 1.0.x than under 2.x while the
#    criterion is unchanged; see aicc_fit_rate_comparison.csv for the figures.
#
# WEIGHTS ARE COMPUTED FROM aicc, NOT READ FROM ssd_gof()
# -------------------------------------------------------
# ssd_gof()'s weight/wt column is ROUNDED to 3 dp, so a genuine ~9.4e-15 weight
# displays as 0.000. Model averaging (ssd_hc(est_method = "multi")) uses
# full-precision weights, so we reconstruct them from the (full-precision) aicc
# column: wt_i = exp(-delta_i/2) / sum_j exp(-delta_j/2), delta = aicc - min(aicc).
# An infinite aicc (n = 6) contributes exp(-Inf) = 0, i.e. weight exactly 0.
#
# MULTI-VERSION INSTALLS (reproducible from a clean clone)
# --------------------------------------------------------
# Each ssdtools version is installed into its own library under
# cache/ssdtools_versions/<version>/ (cache/ is git-ignored, so the libraries do
# not travel with the repo - only the two CSVs do). Installs use
# remotes::install_version() against CRAN / the CRAN archive and are cached: a
# re-run reinstalls nothing. Because two ssdtools versions cannot be loaded in one
# session, every fit runs in a fresh callr subprocess with that version's library
# first on .libPaths(). Requires: remotes, callr (both ship with the tidyverse /
# devtools toolchain used elsewhere in this pipeline). A working C++/TMB toolchain
# is needed to build ssdtools 1.0.6 (TMB-based); 2.x builds the same way.

set.seed(42)

suppressPackageStartupMessages({
  library(remotes)
  library(callr)
})

options(repos = c(CRAN = "https://cloud.r-project.org"))

versions <- c("1.0.6", "2.0.0", "2.6.0")
lib_root <- file.path("cache", "ssdtools_versions")
dir.create(lib_root, showWarnings = FALSE, recursive = TRUE)

# ---- ensure each pinned ssdtools version is installed in its own library ------

ensure_version <- function(v) {
  lib <- file.path(lib_root, v)
  dir.create(lib, showWarnings = FALSE, recursive = TRUE)
  have <- tryCatch(
    as.character(packageVersion("ssdtools", lib.loc = lib)),
    error = function(e) NA_character_
  )
  if (!identical(have, v)) {
    message(sprintf("Installing ssdtools %s into %s ...", v, lib))
    remotes::install_version(
      "ssdtools",
      version = v,
      lib = lib,
      upgrade = "never",
      dependencies = TRUE,
      quiet = TRUE
    )
  }
  normalizePath(lib)
}

libs <- vapply(versions, ensure_version, character(1))
names(libs) <- versions

# ---- the worker: everything below runs inside a per-version callr subprocess --
# It is a pure function of its arguments (the version's library goes first on
# .libPaths via callr's `libpath`), so no ssdtools symbol leaks across versions.

worker <- function(exp_a_data, mc_samples, profiles_a, profiles_b) {
  suppressPackageStartupMessages(library(ssdtools))
  ver <- as.character(packageVersion("ssdtools"))

  gof <- function(fit) {
    # ssd_gof() gained a `wt` arg in 2.3.1 and deprecates the wt = FALSE call;
    # pre-2.3.1 rejects the arg entirely. Try the new form, fall back to old.
    g <- tryCatch(ssd_gof(fit, wt = TRUE), error = function(e) ssd_gof(fit))
    as.data.frame(g)
  }

  # Full-precision AICc model-averaging weight of `dist` from a gof table.
  # Returns 0 (with present = FALSE) if the distribution is absent (failed fit).
  mix_weight <- function(g, dist = "lnorm_lnorm") {
    if (!dist %in% g$dist) {
      return(list(present = FALSE, wt = 0, aicc = NA_real_))
    }
    delta <- g$aicc - min(g$aicc)
    w <- exp(-delta / 2) / sum(exp(-delta / 2))
    list(
      present = TRUE,
      wt = w[g$dist == dist],
      aicc = g$aicc[g$dist == dist]
    )
  }

  fit_one <- function(x, profile) {
    args <- list(
      data = data.frame(Conc = x),
      dists = ssd_dists_bcanz(),
      nrow = 5L
    )
    if (profile == "lenient") {
      # Most-permissive acceptance: keep every fit, allow boundary solutions,
      # no minimum mixing proportion. `native` omits these so each version's own
      # defaults apply (1.0.6: computable TRUE / at_boundary_ok FALSE / min_pmix 0;
      # 2.x: computable FALSE / at_boundary_ok TRUE / min_pmix ssd_min_pmix(n)).
      args$computable <- FALSE
      args$at_boundary_ok <- TRUE
      args$min_pmix <- 0
    }
    tryCatch(do.call(ssd_fit_dists, args), error = function(e) NULL)
  }

  # ---- experiment a: version x arguments x weight at n = 5, 6, 7 --------------
  rows_a <- list()
  for (profile in profiles_a) {
    for (nm in names(exp_a_data)) {
      x <- exp_a_data[[nm]]
      fit <- fit_one(x, profile)
      mw <- if (is.null(fit)) list(present = FALSE, wt = 0, aicc = NA_real_) else mix_weight(gof(fit))
      rows_a[[length(rows_a) + 1L]] <- data.frame(
        version = ver,
        profile = profile,
        n = length(x),
        lnorm_lnorm_present = mw$present,
        lnorm_lnorm_aicc = mw$aicc,
        lnorm_lnorm_wt = mw$wt,
        stringsAsFactors = FALSE
      )
    }
  }
  exp_a <- do.call(rbind, rows_a)

  # ---- experiment b: Monte Carlo n = 5 fit rate ------------------------------
  rows_b <- list()
  for (profile in profiles_b) {
    per_sample <- lapply(mc_samples, function(x) {
      fit <- fit_one(x, profile)
      if (is.null(fit)) return(list(present = FALSE, wt = 0))
      mix_weight(gof(fit))
    })
    present <- vapply(per_sample, `[[`, logical(1), "present")
    wts <- vapply(per_sample, `[[`, numeric(1), "wt")
    wins <- wts > 0.5
    n <- length(mc_samples)
    # Each rate is a binomial proportion over the n Monte Carlo samples, so the
    # natural interval is a binomial CI, not a bootstrap. Clopper-Pearson (exact)
    # via base R binom.test keeps the reprex dependency-free.
    ci_present <- 100 * binom.test(sum(present), n)$conf.int
    ci_wins <- 100 * binom.test(sum(wins), n)$conf.int
    rows_b[[length(rows_b) + 1L]] <- data.frame(
      version = ver,
      profile = profile,
      n_samples = n,
      pct_mixture_present = 100 * mean(present),
      present_ci_lwr = ci_present[1],
      present_ci_upr = ci_present[2],
      pct_mixture_wins = 100 * mean(wins),
      wins_ci_lwr = ci_wins[1],
      wins_ci_upr = ci_wins[2],
      mean_mixture_weight = mean(wts),
      stringsAsFactors = FALSE
    )
  }
  exp_b <- do.call(rbind, rows_b)

  list(exp_a = exp_a, exp_b = exp_b)
}

# ---- inputs shared verbatim across every version (comparability) --------------

# The 5-point reprex and its natural geometric extensions (ratio ~3). The 7-point
# extension c(...,100) is the one that yields the ~116 mixture AICc noted in the
# ssdtools issue.
exp_a_data <- list(
  n5 = c(0.1, 0.3, 1, 3, 10),
  n6 = c(0.1, 0.3, 1, 3, 10, 30),
  n7 = c(0.1, 0.3, 1, 3, 10, 30, 100)
)

# 1000 samples of n = 5 from a unimodal lognormal source, generated ONCE so every
# version fits the identical data. meanlog = 0, sdlog = 1 is a plain unimodal
# source that generates no mixture structure. 1000 (vs an earlier 150) tightens
# the Clopper-Pearson CI on the 1.0.x fit rate to a few points either side.
n_mc <- 1000L
mc_samples <- lapply(seq_len(n_mc), function(i) rlnorm(5, meanlog = 0, sdlog = 1))

# Which (version, profile) cells to run for each experiment.
# a: both profiles in every version (to show argument-invariance).
# b: 1.0.6 native + lenient (the lenient control shows acceptance settings do not
#    lift the 1.0.x fit rate), plus 2.0.0 and 2.6.0 native (2.6.0 native = the
#    pipeline's own settings).
profiles_a_by_ver <- list("1.0.6" = c("native", "lenient"),
                          "2.0.0" = c("native", "lenient"),
                          "2.6.0" = c("native", "lenient"))
profiles_b_by_ver <- list("1.0.6" = c("native", "lenient"),
                          "2.0.0" = c("native"),
                          "2.6.0" = c("native"))

# ---- run each version in its own subprocess and collect -----------------------

results <- lapply(versions, function(v) {
  message(sprintf("Running experiments under ssdtools %s ...", v))
  callr::r(
    worker,
    args = list(
      exp_a_data = exp_a_data,
      mc_samples = mc_samples,
      profiles_a = profiles_a_by_ver[[v]],
      profiles_b = profiles_b_by_ver[[v]]
    ),
    libpath = c(libs[[v]], .libPaths())
  )
})

exp_a <- do.call(rbind, lapply(results, `[[`, "exp_a"))
exp_b <- do.call(rbind, lapply(results, `[[`, "exp_b"))

# Order for stable, human-readable CSVs.
exp_a <- exp_a[order(exp_a$version, exp_a$profile, exp_a$n), ]
exp_b <- exp_b[order(exp_b$version, exp_b$profile), ]

write.csv(exp_a, "aicc_version_comparison.csv", row.names = FALSE)
write.csv(exp_b, "aicc_fit_rate_comparison.csv", row.names = FALSE)

cat("\n== aicc_version_comparison.csv (experiment a) ==\n")
print(exp_a, row.names = FALSE, digits = 4)
cat("\n== aicc_fit_rate_comparison.csv (experiment b) ==\n")
print(exp_b, row.names = FALSE, digits = 4)
cat("\nWrote aicc_version_comparison.csv and aicc_fit_rate_comparison.csv\n")
