#!/usr/bin/env bash
#
#SBATCH -J geoEndemic # A single job name for the array
#SBATCH --ntasks-per-node=1 # one core
#SBATCH -N 1 # on one node
#SBATCH --cpus-per-task=1 ### standard has 28 or 40 $SLURM_CPUS_PER_TASK
#SBATCH -t 01:00:00 # Running time of 1 hours
#SBATCH --mem 40G # Memory request of 8 GB
#SBATCH -o /scratch/aob2x/daphnia_hwe_sims/slurmOut/lme4qtl.%A_%a.out # Standard output
#SBATCH -e /scratch/aob2x/daphnia_hwe_sims/slurmOut/lme4qtl.%A_%a.err # Standard error
#SBATCH -p largemem
#SBATCH --account berglandlab

# sbatch /scratch/aob2x/dest/DEST/Analyses/GeographicEndemism/geographic_clustering_endemic.collect.sh
# sacct -j 18436693
# cat /scratch/aob2x/daphnia_hwe_sims/slurmOut/lme4qtl.18336694_1.err
module load gcc/7.1.0  openmpi/3.1.4 R/3.6.3

Rscript /scratch/aob2x/dest/DEST/Analyses/GeographicEndemism/geographic_clustering_endemic.collect.R
