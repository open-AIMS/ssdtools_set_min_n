#!/bin/bash
# Submit from study_small_hpc/ on the HPC:  sbatch extract_fit_weights.sbatch
# Decodes the fit shards' serialised fitdists and writes fit_weights_observed.csv
# (see extract_fit_weights.R). ~20-25 min on 8 cores for the 500 sim shards.
#SBATCH --job-name=extract-fit-weights
#SBATCH --partition=cpuq
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=2G
#SBATCH --time=60
#SBATCH --nice=6000
#SBATCH --output=extract_fit_weights.slurm.out

module load R/4.4.1
export EXTRACT_CORES=${SLURM_CPUS_PER_TASK:-8}
cd "${SLURM_SUBMIT_DIR:-.}"
Rscript extract_fit_weights.R
