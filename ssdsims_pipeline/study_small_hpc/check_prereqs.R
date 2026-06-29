#!/usr/bin/env Rscript
options(warn = 2)

# check_prereqs.R -- login-node prerequisite checker for the nboot-stability run.
#
# Run before submitting. Verifies, verbosely, everything `Rscript run.R` needs:
#   * R version + library path
#   * SLURM CLI on PATH (sbatch / squeue / srun)
#   * outbound HTTPS to packagemanager.posit.co and github.com (install only)
#   * each runtime package installs & loads
#   * ssdsims is available and its scenario API exists
#   * crew.cluster::crew_options_slurm() constructs
#   * selected_datasets.csv exists and scenario.R builds + fans out into shards
#   * a read-only compute-cost estimate
#
# Exits 0 if all required checks pass, 1 otherwise. Network checks are optional
# (WARN, not FAIL) -- they only matter for install_deps.R.
#
# Usage:
#   Rscript check_prereqs.R

cat_section <- function(label) {
  cat("\n== ", label, " ", strrep("=", max(0L, 72L - nchar(label))), "\n", sep = "")
}

n_ok <- 0L
n_warn <- 0L
n_fail <- 0L

check <- function(label, expr, required = TRUE, hint = NULL) {
  res <- tryCatch(
    list(ok = isTRUE(force(expr)), err = NULL),
    error = function(e) list(ok = FALSE, err = conditionMessage(e))
  )
  status <- if (res$ok) "PASS" else if (required) "FAIL" else "WARN"
  cat(sprintf("  [%s] %s\n", status, label))
  if (!res$ok) {
    if (!is.null(res$err)) cat("        ", res$err, "\n", sep = "")
    if (!is.null(hint)) cat("        hint: ", hint, "\n", sep = "")
  }
  if (res$ok) n_ok <<- n_ok + 1L else if (required) n_fail <<- n_fail + 1L else n_warn <<- n_warn + 1L
  invisible(res$ok)
}

# ---- R ----
cat_section("R")
cat("  version  : ", R.version.string, "\n", sep = "")
cat("  platform : ", R.version$platform, "\n", sep = "")
cat("  libPaths :\n")
for (p in .libPaths()) cat("    - ", p, "\n", sep = "")

check(
  "R is 4.4.x",
  identical(R.version$major, "4") && startsWith(R.version$minor, "4"),
  required = FALSE,
  hint = "Project's working R version is 4.4.1. `module load R/4.4.1` on AIMS HPC."
)

# ---- SLURM ----
cat_section("SLURM CLI")
for (bin in c("sbatch", "squeue", "srun", "scancel")) {
  path <- Sys.which(bin)
  check(
    sprintf("%s on PATH (%s)", bin, if (nzchar(path)) path else "missing"),
    nzchar(path),
    required = bin %in% c("sbatch", "squeue"),
    hint = "Run `module load slurm` first if your site requires it."
  )
}

# ---- Network (install only) ----
cat_section("Outbound HTTPS (needed only for install_deps.R)")
can_reach <- function(url) {
  res <- tryCatch(curlGetHeaders(url, redirect = FALSE, timeout = 5L), error = function(e) NULL)
  if (is.null(res)) return(FALSE)
  status <- attr(res, "status")
  is.numeric(status) && status > 0L
}
# Hit the PINNED dated PPM snapshot (must match install_deps.R's PPM_SNAPSHOT),
# so this also confirms the frozen snapshot date still resolves.
ppm_snapshot <- Sys.getenv("PPM_SNAPSHOT", unset = "2026-06-27")
check(
  sprintf("PPM snapshot %s reachable (ManyLinux PACKAGES)", ppm_snapshot),
  can_reach(sprintf(
    "https://packagemanager.posit.co/cran/%s/bin/linux/manylinux_2_28-x86_64/4.4/src/contrib/PACKAGES",
    ppm_snapshot
  )),
  required = FALSE,
  hint = "Only needed for install_deps.R. Keep PPM_SNAPSHOT in sync with install_deps.R."
)
check(
  "https://github.com reachable",
  can_reach("https://github.com/"),
  required = FALSE,
  hint = "Only needed to install ssddata / ssdtools / ssdsims from GitHub."
)

# ---- Packages ----
cat_section("R packages (load each)")
pkgs <- c(
  "chk", "digest", "dplyr", "dqrng", "duckplyr", "jsonlite", "purrr",
  "rlang", "sessioninfo", "tibble", "tidyr", "withr",
  "targets", "tarchetypes", "tidyselect", "crew", "crew.cluster",
  "mirai", "parallelly", "ggplot2", "readr", "scales",
  "ssddata", "ssdtools", "ssdsims"
)
for (p in pkgs) check(sprintf("library(%s)", p), requireNamespace(p, quietly = TRUE))

# ---- ssdsims surface ----
cat_section("ssdsims API surface used by the pipeline")
if (requireNamespace("ssdsims", quietly = TRUE)) {
  syms <- c(
    "ssd_define_scenario", "ssd_scenario_data", "ssd_scenario_targets",
    "ssd_scenario_hc_shards", "scenario_results_dir"
  )
  for (s in syms) {
    check(
      sprintf("ssdsims::%s exists", s),
      exists(s, envir = asNamespace("ssdsims"), inherits = FALSE)
    )
  }
  cat("  ssdsims version : ", as.character(packageVersion("ssdsims")), "\n", sep = "")
}
if (requireNamespace("ssdtools", quietly = TRUE)) {
  cat("  ssdtools version: ", as.character(packageVersion("ssdtools")), "\n", sep = "")
}
if (requireNamespace("ssddata", quietly = TRUE)) {
  cat("  ssddata version : ", as.character(packageVersion("ssddata")), "\n", sep = "")
}

# ---- crew.cluster sanity ----
cat_section("crew.cluster sanity")
if (requireNamespace("crew.cluster", quietly = TRUE)) {
  check("crew_options_slurm() constructs", {
    opts <- crew.cluster::crew_options_slurm(
      script_lines = c("module load R/4.4.1", "module load slurm"),
      partition = "cpuq", cpus_per_task = 1L,
      memory_gigabytes_per_cpu = 1, time_minutes = 30L
    )
    inherits(opts, "crew_options_slurm")
  })
}

# ---- selection + scenario builds & fans out ----
cat_section("selected_datasets.csv + scenario.R")
check(
  "selected_datasets.csv exists (run select_datasets.R if not)",
  file.exists("selected_datasets.csv"),
  hint = "Rscript select_datasets.R  (the prep step that picks the six datasets)."
)
check(
  "populations.rds exists (run make_populations.R if not)",
  file.exists("populations.rds"),
  hint = "Rscript make_populations.R  (the prep step that generates the parametric populations). It is committed, so normally arrives via git pull."
)
scenario <- NULL
if (
  file.exists("populations.rds") &&
    requireNamespace("ssdsims", quietly = TRUE) &&
    requireNamespace("ssddata", quietly = TRUE)
) {
  check(
    "scenario.R sources and builds an ssdsims_scenario",
    {
      e <- new.env()
      sys.source("scenario.R", envir = e)
      scenario <<- e$scenario
      inherits(scenario, "ssdsims_scenario")
    },
    hint = "Check the dataset names in selected_datasets.csv resolve in ssddata."
  )
  if (!is.null(scenario)) {
    check(
      "scenario fans out into >1 hc shard",
      nrow(ssdsims::ssd_scenario_hc_shards(scenario)) > 1L,
      required = FALSE
    )
    cat("  results dir     : ", ssdsims::scenario_results_dir(scenario), "\n", sep = "")
    cat("  hc shards       : ", nrow(ssdsims::ssd_scenario_hc_shards(scenario)), "\n", sep = "")
  }
}

# ---- cost estimate ----
cat_section("Computation cost estimate (ballpark, read-only)")
if (!is.null(scenario) && exists("ssd_estimate_cost", envir = asNamespace("ssdsims"))) {
  est <- tryCatch(
    ssdsims::ssd_estimate_cost(scenario),
    error = function(e) {
      cat("  (could not estimate: ", conditionMessage(e), ")\n", sep = "")
      NULL
    }
  )
  if (!is.null(est)) {
    print(est)
    total_secs <- as.numeric(est$total, units = "secs")
    longest_secs <- as.numeric(est$longest, units = "secs")
    workers <- 32L # keep in sync with crew_controller_slurm(workers=) in _targets.R
    wall <- max(longest_secs, total_secs / workers)
    cat(sprintf(
      "  rough wall time at %d workers: ~%.1f min (max of longest task and total/workers)\n",
      workers, wall / 60
    ))
  }
}

# ---- summary ----
cat_section("Summary")
cat(sprintf("  passed : %d\n  warned : %d\n  failed : %d\n", n_ok, n_warn, n_fail))
if (n_fail > 0L) {
  cat("\nFAIL. Fix the items above before submitting.\n")
  quit(status = 1L)
} else {
  cat("\nPASS. You can run `Rscript run.R`.\n")
}
