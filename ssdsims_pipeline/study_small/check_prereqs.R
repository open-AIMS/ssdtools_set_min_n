#!/usr/bin/env Rscript
options(warn = 2)

# check_prereqs.R - prerequisite checker for the local (no SLURM, no Azure)
# study_small pipeline. Run before `Rscript run.R`.
#
# Usage:
#   Rscript check_prereqs.R

n_ok <- 0L
n_warn <- 0L
n_fail <- 0L

check <- function(label, expr, required = TRUE) {
  res <- tryCatch(
    list(ok = isTRUE(force(expr)), err = NULL),
    error = function(e) list(ok = FALSE, err = conditionMessage(e))
  )
  status <- if (res$ok) "PASS" else if (required) "FAIL" else "WARN"
  cat(sprintf("  [%s] %s\n", status, label))
  if (!res$ok && !is.null(res$err)) cat("        ", res$err, "\n", sep = "")
  if (res$ok) n_ok <<- n_ok + 1L else if (required) n_fail <<- n_fail + 1L else n_warn <<- n_warn + 1L
  invisible(res$ok)
}

cat("== packages ==\n")
pkgs <- c(
  "ssdsims", "ssddata", "ssdtools", "dplyr", "arrow", "duckplyr",
  "ggplot2", "patchwork", "targets", "tarchetypes", "crew", "mirai"
)
for (p in pkgs) check(sprintf("library(%s)", p), requireNamespace(p, quietly = TRUE))

cat("\n== crew local controller ==\n")
check("crew::crew_controller_local() constructs", {
  ctl <- crew::crew_controller_local(workers = 2L)
  inherits(ctl, "crew_class_controller")
})

cat("\n== scenario builds ==\n")
scenario <- NULL
check("scenario.R sources and builds an ssdsims_scenario", {
  e <- new.env()
  sys.source("scenario.R", envir = e)
  scenario <<- e$scenario
  inherits(scenario, "ssdsims_scenario")
})

cat("\n== compute cost estimate (ballpark, read-only) ==\n")
if (!is.null(scenario)) {
  est <- tryCatch(ssdsims::ssd_estimate_cost(scenario), error = function(e) NULL)
  if (!is.null(est)) {
    print(est)
    workers <- 18L # keep in sync with crew_controller_local(workers = ) in _targets.R
    total_secs <- as.numeric(est$total, units = "secs")
    longest_secs <- as.numeric(est$longest, units = "secs")
    wall <- max(longest_secs, total_secs / workers)
    cat(sprintf(
      "  rough wall time at %d local workers: ~%.1f min\n",
      workers, wall / 60
    ))
    cat(
      "  NOTE: measured directly during development, this estimate was off\n",
      "  by >10x - it does not account for nrow/proportion being bundled\n",
      "  into one hc task per (dataset, sim) (the default hc bundle), so the\n",
      "  real per-task cost is much higher than the per-cell number above.\n",
      "  Trust a timed pilot over this estimate: temporarily set nsim = 2L\n",
      "  in scenario.R, `Rscript run.R`, read the reported wall time, then\n",
      "  scale nsim linearly from that.\n",
      sep = ""
    )
  }
}

cat(sprintf("\npassed: %d  warned: %d  failed: %d\n", n_ok, n_warn, n_fail))
if (n_fail > 0L) cat("\nFAIL. Fix the items above.\n") else cat("\nPASS. You can run `Rscript run.R`.\n")
