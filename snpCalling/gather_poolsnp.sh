#!/usr/bin/env bash
#
#SBATCH -J split_and_run # A single job name for the array
#SBATCH --ntasks-per-node=20 # one core
#SBATCH -N 1 # on one node
#SBATCH -t 12:00:00 ### 6 hours
#SBATCH --mem 10G
#SBATCH -o /scratch/aob2x/dest/slurmOutput/split_and_run.%A_%a.out # Standard output
#SBATCH -e /scratch/aob2x/dest/slurmOutput/split_and_run.%A_%a.err # Standard error
#SBATCH -p standard
#SBATCH --account berglandlab

### run as: sbatch --array=1-8 ${wd}/DEST/snpCalling/gather_poolsnp.sh
### sacct -j 12839251
### cat /scratch/aob2x/dest/slurmOutput/split_and_run.12825614
module load htslib bcftools intel/18.0 intelmpi/18.0 R/3.6.0


wd="/scratch/aob2x/dest"
outdir="/scratch/aob2x/dest/sub_vcfs"
maf=${1} #maf=01

#head -n5 ${wd}/dest/poolSNP_jobs.csv | sed 's/,/_/g' | sed 's/^/\/scratch\/aob2x\/dest\/sub_vcfs\//g' | sed 's/$/.bcf/g' > /scratch/aob2x/dest/sub_vcfs/bcfs_order
ls -d $outdir/*.${maf}.vcf.gz > /scratch/aob2x/dest/sub_vcfs/vcfs_order.${maf}
cat /scratch/aob2x/dest/sub_vcfs/vcfs_order.${maf} | sort -t"_" -k2,2 -k3g,3  > /scratch/aob2x/dest/sub_vcfs/vcfs_order.${maf}.sort

# SLURM_ARRAY_TASK_ID=4
  chr=$( cat /scratch/aob2x/dest/sub_vcfs/vcfs_order.${maf}.sort | rev | cut -f1 -d'/' | rev  | cut -f1 -d'_' | sort | uniq | sed "${SLURM_ARRAY_TASK_ID}q;d" )

  grep /${chr}_ /scratch/aob2x/dest/sub_vcfs/vcfs_order.${maf}.sort > /scratch/aob2x/dest/sub_vcfs/vcfs_order.${chr}.${maf}.sort


 bcftools concat \
 --threads 20 \
 -f /scratch/aob2x/dest/sub_vcfs/vcfs_order.${chr}.${maf}.sort \
 -O v \
 -n \
 -o /scratch/aob2x/dest/sub_bcf/dest.June14_2020.maf001.${chr}.${maf}.bcf