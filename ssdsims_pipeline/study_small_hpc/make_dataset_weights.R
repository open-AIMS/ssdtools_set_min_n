#!/usr/bin/env Rscript

# make_dataset_weights.R - (re)build dataset_aicc_weights.csv from the cached
# real-data fits (cache/fits.rds), the 41 x 6 matrix of BCANZ AICc weights per
# dataset plus each dataset's top-weighted ("source") distribution.
#
# This is the committed input for the report's "Source-distribution AICc weights"
# and "Refitted vs true distribution weights" sections. cache/ is git-ignored, so
# the CSV (not the fits) is what travels with the repo; rerun this whenever the
# cached fits change.
#
# WHY THIS SCRIPT EXISTS / the ccme_boron tie
# -------------------------------------------
# The original CSV stored weights ROUNDED to 3 dp and derived source_dist with
# which.max() over the rounded columns. For ccme_boron, gamma (0.356574) and
# weibull (0.357472) both round to 0.357 - a rounding tie, difference ~9e-4 -
# and which.max() over the column order (gamma before weibull) picked GAMMA.
# But ssd_gen()/scenario.R select the source with which.max(glance(wt=TRUE)$wt)
# at FULL precision, which picks WEIBULL. So the CSV's source_dist disagreed with
# cache/true_hc.rds (the distribution actually sampled from) for ccme_boron.
#
# Fix: write weights at full precision, and derive source_dist with an EXPLICIT,
# deterministic rule that reproduces cache/true_hc.rds exactly: the max-weight
# distribution taken in the canonical BCANZ order (ties, should any ever be
# exact, break toward the earlier BCANZ distribution - the same behaviour as
# which.max() on a canonically ordered weight vector, but stated rather than
# left implicit in column order). The script then ASSERTS 41/41 agreement with
# cache/true_hc.rds and stops if any dataset disagrees.

suppressPackageStartupMessages({
  library(ssdtools)
})

fits_cache <- "cache/fits.rds"
true_hc_cache <- "cache/true_hc.rds"
stopifnot(file.exists(fits_cache), file.exists(true_hc_cache))

fits <- readRDS(fits_cache)
true_hc <- readRDS(true_hc_cache)

# Canonical BCANZ distribution order - the column order of the CSV and the order
# in which ties are broken. Taken from ssdtools so it cannot drift from glance().
dists_bcanz <- ssd_dists_bcanz()

pick_source <- function(w) {
  # w: named full-precision weight vector in canonical BCANZ order.
  # Deterministic argmax: first distribution (in canonical order) attaining the
  # maximum weight. Matches which.max(glance(wt=TRUE)$wt) as used by scenario.R /
  # ssd_gen(), but the tie-break is explicit rather than a side effect of order.
  names(w)[which.max(w)]
}

rows <- lapply(names(fits), function(nm) {
  gl <- ssdtools::glance(fits[[nm]], wt = TRUE)
  w <- setNames(rep(0, length(dists_bcanz)), dists_bcanz)
  w[gl$dist] <- gl$wt # full precision; distributions not present stay 0
  src <- pick_source(w)
  data.frame(
    dataset = nm,
    as.list(w),
    source_dist = src,
    source_wt = unname(w[src]),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
})
out <- do.call(rbind, rows)

# ---- verify 41/41 agreement with the sampled-from source in true_hc.rds -------

true_src <- unique(true_hc[, c("dataset", "source_dist")])
chk <- merge(
  out[, c("dataset", "source_dist")], true_src,
  by = "dataset", suffixes = c("_csv", "_true")
)
disagree <- chk[chk$source_dist_csv != chk$source_dist_true, ]
if (nrow(disagree)) {
  print(disagree)
  stop("source_dist disagrees with cache/true_hc.rds for ",
    nrow(disagree), " dataset(s)")
}
cat(sprintf("source_dist agreement with cache/true_hc.rds: %d/%d\n",
  nrow(chk) - nrow(disagree), nrow(chk)))

# Full precision on disk; the report rounds for display.
write.csv(out, "dataset_aicc_weights.csv", row.names = FALSE)
cat("Wrote dataset_aicc_weights.csv\n\n")

cat("Corrected source-distribution counts (of 41 datasets):\n")
print(table(factor(out$source_dist, levels = dists_bcanz)))
