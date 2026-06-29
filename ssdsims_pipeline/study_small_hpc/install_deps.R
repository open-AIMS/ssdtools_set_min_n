#!/usr/bin/env Rscript
options(warn = 2)

# install_deps.R -- install ssdsims + every dependency this study needs, as
# ManyLinux binaries from Posit Public Package Manager (PPM), plus the GitHub
# source packages.
#
# Binary URL (PINNED to a DATED PPM snapshot -- see the note below):
#   https://packagemanager.posit.co/cran/<DATE>/bin/linux/manylinux_2_28-x86_64/4.4
# Despite the `.tar.gz` extension PPM serves there, the contents are pre-compiled
# manylinux_2_28 binaries (glibc >= 2.28); install.packages() treats Linux as
# "source", so we keep pkgType = "source" and override only the repo URL.
#
# ============================================================================
# WHY THE PPM SNAPSHOT IS PINNED TO A DATE (do NOT change casually) -- IMPORTANT
# ============================================================================
# We deliberately pin to a DATED snapshot instead of `.../cran/latest/...`. With
# `latest`, the binary package versions move whenever PPM updates, so two installs
# on different days can get a DIFFERENT package set. That is a problem here: a
# change in a low-level dependency (notably `rlang`) shifts hashes/serialisation
# in a way that INVALIDATES the targets cache, so the WHOLE study re-computes (and,
# if uploading, re-writes every result). To keep one stable, reproducible package
# set over time -- so re-running adds only genuinely new work and results stay
# byte-comparable -- we freeze the snapshot to a fixed date.
#
# Changing PPM_SNAPSHOT is a deliberate act: expect it to bump rlang/others and
# trigger a full recompute. Pick a new date, re-install everywhere (WSL + HPC),
# and plan to rebuild results from scratch. Keep WSL and the HPC on the SAME date.
# ============================================================================
#
# This study has NO Azure upload (results are pulled with rsync/scp), so the
# Azure client is intentionally NOT installed.
#
# Package sources (per the study's decision):
#   * ssddata  -> open-AIMS/ssddata@dev       (the current dev version)
#   * ssdtools -> poissonconsulting/ssdtools@dev (upstream dev; has C++, compiles)
#   * ssdsims  -> poissonconsulting/ssdsims    (its Remotes also pin ssdtools@dev)
#
# Usage:
#   Rscript install_deps.R
#
# Env overrides:
#   SSDSIMS_REF    ssdsims branch/tag/commit (default: "main")
#   SSDDATA_REF    ssddata branch/tag/commit (default: "dev" — the dev version,
#                  the branch this study was built and selected against)
#   SSDTOOLS_REF   ssdtools branch/tag/commit (default: "dev")
#   PPM_SNAPSHOT   PPM snapshot date (default below) — see the pinning note above
#   R_LIBS_USER    target library (R's standard mechanism)

ssdsims_ref <- Sys.getenv("SSDSIMS_REF", unset = "main")
ssddata_ref <- Sys.getenv("SSDDATA_REF", unset = "dev")
ssdtools_ref <- Sys.getenv("SSDTOOLS_REF", unset = "dev")

# Pinned PPM snapshot date. Frozen for reproducibility (see the note above). Keep
# this identical on WSL and the HPC; bumping it is a deliberate, recompute-from-
# scratch decision.
ppm_snapshot <- Sys.getenv("PPM_SNAPSHOT", unset = "2026-06-27")

manylinux <- sprintf(
  "https://packagemanager.posit.co/cran/%s/bin/linux/manylinux_2_28-x86_64/4.4",
  ppm_snapshot
)

options(
  repos = c(PPM = manylinux, CRAN = "https://cloud.r-project.org"),
  install.packages.compile.from.source = "never",
  Ncpus = max(1L, parallel::detectCores() - 1L)
)

cat("install_deps.R\n")
cat("  R           : ", R.version.string, "\n", sep = "")
cat("  platform    : ", R.version$platform, "\n", sep = "")
cat("  lib (1st)   : ", .libPaths()[[1L]], "\n", sep = "")
cat("  binary repo : ", manylinux, "\n", sep = "")
cat("  PPM snapshot: ", ppm_snapshot, " (pinned for reproducibility)\n", sep = "")
cat("  ssdsims ref : ", ssdsims_ref, "\n", sep = "")
cat("  ssddata ref : ", ssddata_ref, "\n", sep = "")
cat("  ssdtools ref: ", ssdtools_ref, "\n\n", sep = "")

# CRAN/PPM binary deps: ssdsims runtime + the targets/crew/SLURM pipeline + the
# tidyverse bits select_datasets.R / analyse_results.R use. No Azure client.
runtime_deps <- c(
  # ssdsims runtime (DESCRIPTION Imports)
  "chk", "digest", "dplyr", "dqrng", "duckplyr", "jsonlite", "purrr",
  "rlang", "sessioninfo", "tibble", "tidyr", "withr",
  # targets + crew + SLURM bridge
  "targets", "tarchetypes", "tidyselect", "crew", "crew.cluster",
  "mirai", "parallelly",
  # prep + analysis (selection, coverage/width plots)
  "ggplot2", "readr", "scales",
  # the bootstrap installer for GitHub refs
  "remotes"
)

already <- rownames(installed.packages())
to_install <- setdiff(runtime_deps, already)

if (length(to_install)) {
  cat(
    "Installing ", length(to_install), " binary packages:\n  ",
    paste(to_install, collapse = ", "), "\n\n",
    sep = ""
  )
  install.packages(to_install)
} else {
  cat("All listed runtime deps already installed.\n\n")
}

# ssddata from the AIMS dev fork.
cat("Installing ssddata from open-AIMS/ssddata@", ssddata_ref, "\n", sep = "")
remotes::install_github(
  "open-AIMS/ssddata",
  ref = ssddata_ref,
  upgrade = "never",
  dependencies = TRUE
)

# ssdtools dev from upstream. Contains C++, so this is the one source compile.
cat("Installing ssdtools from poissonconsulting/ssdtools@", ssdtools_ref, "\n", sep = "")
remotes::install_github(
  "poissonconsulting/ssdtools",
  ref = ssdtools_ref,
  upgrade = "never",
  dependencies = TRUE
)

# ssdsims itself. Its DESCRIPTION Remotes pins ssdtools@dev too; installing
# ssdtools first (above) means remotes sees it satisfied.
cat("Installing ssdsims from poissonconsulting/ssdsims@", ssdsims_ref, "\n", sep = "")
remotes::install_github(
  "poissonconsulting/ssdsims",
  ref = ssdsims_ref,
  upgrade = "never",
  dependencies = TRUE
)

cat("\nDone. Verify with:\n")
cat("  Rscript check_prereqs.R\n")
