#!/usr/bin/env bash
#
# pull_results.sh - retrieve the study_small_hpc Parquet results from the HPC
# back into this WSL workspace via rsync, then (optionally) build the figure
# locally. The pipeline writes no cloud upload, so results live on the cluster
# under study_small_hpc/results/ - this script mirrors that tree down to the
# matching local results/ dir.
#
# Connection details are taken from environment variables so no personal host
# config is committed. Set them in your shell (or a local, gitignored env file
# you `source` first):
#
#   export HPC_HOST=hpc.example.org          # or a Host alias from ~/.ssh/config
#   export HPC_USER=rfisher                  # omit if HPC_HOST is an ssh alias
#   export HPC_REMOTE_DIR=/scratch/rfisher/ssdtools_set_min_n/ssdsims_pipeline/study_small_hpc
#
# Usage (from inside ssdsims_pipeline/study_small_hpc/):
#   ./pull_results.sh            # rsync results/ down
#   ./pull_results.sh -n         # dry run: show what would transfer, copy nothing
#   ./pull_results.sh --figure   # rsync, then Rscript make_figure.R locally
#
set -euo pipefail

# --- resolve paths relative to this script, not the caller's CWD -------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_RESULTS="${SCRIPT_DIR}/results"

# --- options -----------------------------------------------------------------
DRY_RUN=""
RUN_FIGURE=0
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY_RUN="--dry-run" ;;
    --figure) RUN_FIGURE=1 ;;
    -h|--help)
      # print the contiguous header comment block only (stop at first non-# line)
      awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
      exit 0 ;;
    *)
      echo "Unknown option: $arg (try --help)" >&2
      exit 2 ;;
  esac
done

# --- dependencies ------------------------------------------------------------
if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync not found. Install it in WSL:  sudo apt install rsync" >&2
  exit 1
fi

# --- required config ---------------------------------------------------------
: "${HPC_HOST:?Set HPC_HOST (hostname or ~/.ssh/config Host alias)}"
: "${HPC_REMOTE_DIR:?Set HPC_REMOTE_DIR (absolute path to study_small_hpc on the HPC)}"

# Build the remote endpoint. If HPC_USER is set, use user@host; otherwise assume
# HPC_HOST is an ssh-config alias that already carries the user.
if [[ -n "${HPC_USER:-}" ]]; then
  REMOTE="${HPC_USER}@${HPC_HOST}"
else
  REMOTE="${HPC_HOST}"
fi

# Trailing slash on the source: copy the *contents* of remote results/ into the
# local results/ dir (not results/results/).
REMOTE_SRC="${REMOTE}:${HPC_REMOTE_DIR%/}/results/"

mkdir -p "$LOCAL_RESULTS"

echo "Pulling:  ${REMOTE_SRC}"
echo "Into:     ${LOCAL_RESULTS}/"
[[ -n "$DRY_RUN" ]] && echo "(dry run - nothing will be written)"

# -a archive (perms/times/recursion), -z compress, --partial resume interrupted
# transfers, --info=progress2 a single overall progress line. Parquet is already
# compressed so -z mostly helps the many tiny shard files' metadata.
rsync -az --partial --info=progress2 $DRY_RUN \
  "$REMOTE_SRC" "${LOCAL_RESULTS}/"

echo "Done."

if [[ "$RUN_FIGURE" -eq 1 && -z "$DRY_RUN" ]]; then
  echo "Building figure locally..."
  cd "$SCRIPT_DIR"
  Rscript make_figure.R
fi
