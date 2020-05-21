#!/bin/bash

check_exit_status () {
  if [ ! "$2" -eq "0" ]; then
    echo "Step $1 failed with exit status $2"
    exit $2
  fi
}

read1="test_file_1"
read2="test_file_2"
sample="default_sample_name"
output="."
threads="1"
max_cov=0.95
min_cov=10
theta=0.005
D=0.01
priortype="informative"
fold="unfolded"

# Credit: https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -c|--cores)
    threads="$2"
    shift # past argument
    shift # past value
    ;;
    -x|--max_cov)
    max_cov="$2"
    shift # past argument
    shift # past value
    ;;
    -n|--min_cov)
    min_cov="$2"
    shift # past argument
    shift # past value
    ;;
    -h|--help)
    echo "Usage:"
    echo "  singularity run [options] <image> -h          Display this help message."
    echo "  singularity run [options] <image> <fastq_file_1_path> <fastq_file_2_path> <sample_name> <output_dir> <num_cores>"
    exit 0
    shift # past argument
    ;;
    -t|--theta)
    theta=$2
    shift # past argument
    shift # past value
    ;;
    -D)
    D=$2
    shift # past argument
    shift # past value
    ;;
    -p|--priortype)
    theta=$2
    shift # past argument
    shift # past value
    ;;
    -f|--fold)
    fold=$2
    shift # past argument
    shift # past value
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") #save it to an array
    shift
    ;;
esac
done

set -- "${POSITIONAL[@]}"

if [ $# != 4 ]
  then
    echo "ERROR: Need to supply <fastq_file_1_path> <fastq_file_2_path> <sample_name> <output_dir> as positional arguments, and no others"
    exit 1
fi

read1=$1; shift
read2=$1; shift
sample=$1; shift
output=$1; shift

if [ ! -f "$read1" ]; then
  echo "ERROR: $read1 does not exist"
  exit 1
fi

if [ ! -f "$read2" ]; then
  echo "ERROR: $read2 does not exist"
  exit 1
fi

if [ ! -d $output/$sample/ ]; then
  mkdir -p $output/$sample/
fi

if [ ! -d $output/$sample/${sample}_fastqc ]; then
  mkdir $output/$sample/${sample}_fastqc
fi

if [ ! -d $output/$sample/${sample}_fastqc/trimmed ]; then
  mkdir $output/$sample/${sample}_fastqc/trimmed
fi

fastqc $read1 $read2 -o $output/$sample/${sample}_fastqc

cutadapt \
-q 18 \
--minimum-length 75 \
-o $output/$sample/${sample}.trimmed1.fq.gz \
-p $output/$sample/${sample}.trimmed2.fq.gz \
-b ACACTCTTTCCCTACACGACGCTCTTCCGATC \
-B CAAGCAGAAGACGGCATACGAGAT \
-O 15 \
-n 3 \
--cores=$threads \
$read1 $read2

check_exit_status "cutadapt" $?

fastqc $output/$sample/${sample}.trimmed1.fq.gz $output/$sample/${sample}.trimmed2.fq.gz -o $output/$sample/${sample}_fastqc/trimmed

check_exit_status "fastqc" $?

#Automatically uses all available cores
bbmerge.sh in1=$output/$sample/${sample}.trimmed1.fq.gz in2=$output/$sample/${sample}.trimmed2.fq.gz out=$output/$sample/${sample}.merged.fq.gz outu1=$output/$sample/${sample}.1_un.fq.gz outu2=$output/$sample/${sample}.2_un.fq.gz

check_exit_status "bbmerge" $?

rm $output/$sample/${sample}.trimmed*

bwa mem -t $threads -M -R "@RG\tID:$sample\tSM:sample_name\tPL:illumina\tLB:lib1" /opt/hologenome/holo_dmel_6.12.fa $output/$sample/${sample}.1_un.fq.gz $output/$sample/${sample}.2_un.fq.gz | samtools view -@ $threads -Sbh -q 20 -F 0x100 - > $output/$sample/${sample}.merged_un.bam

rm $output/$sample/${sample}.1_un.fq.gz
rm $output/$sample/${sample}.2_un.fq.gz

bwa mem -t $threads -M -R "@RG\tID:$sample\tSM:sample_name\tPL:illumina\tLB:lib1" /opt/hologenome/holo_dmel_6.12.fa $output/$sample/${sample}.merged.fq.gz | samtools view -@ $threads -Sbh -q 20 -F 0x100 - > $output/$sample/${sample}.merged.bam

check_exit_status "bwa_mem" $?

rm $output/$sample/${sample}.merged.fq.gz

java -jar $PICARD MergeSamFiles I=$output/$sample/${sample}.merged.bam I=$output/$sample/${sample}.merged_un.bam SO=coordinate USE_THREADING=true O=$output/$sample/${sample}.sorted_merged.bam

check_exit_status "Picard_MergeSamFiles" $?

rm $output/$sample/${sample}.merged.bam
rm $output/$sample/${sample}.merged_un.bam

java -jar $PICARD MarkDuplicates \
REMOVE_DUPLICATES=true \
I=$output/$sample/${sample}.sorted_merged.bam \
O=$output/$sample/${sample}.dedup.bam \
M=$output/$sample/${sample}.mark_duplicates_report.txt \
VALIDATION_STRINGENCY=SILENT

check_exit_status "Picard_MarkDuplicates" $?

rm $output/$sample/${sample}.sorted_merged.bam

samtools index $output/$sample/${sample}.dedup.bam

java -jar $GATK -T RealignerTargetCreator \
-nt $threads \
-R /opt/hologenome/holo_dmel_6.12.fa \
-I $output/$sample/${sample}.dedup.bam \
-o $output/$sample/${sample}.hologenome.intervals

check_exit_status "GATK_RealignerTargetCreator" $?

java -jar $GATK \
-T IndelRealigner \
-R /opt/hologenome/holo_dmel_6.12.fa \
-I $output/$sample/${sample}.dedup.bam \
-targetIntervals $output/$sample/${sample}.hologenome.intervals \
-o $output/$sample/${sample}.contaminated_realigned.bam

check_exit_status "GATK_IndelRealigner" $?

rm $output/$sample/${sample}.dedup.bam*

# samtools index $output/$sample/${sample}.contaminated_realigned.bam

#Number of reads mapping to simulans and mel
# grep -v "sim_" $output/$sample/${sample}.${sample}.original_idxstats.txt | awk -F '\t' '{sum+=$3;} END {print sum;}' > $output/$sample/${sample}.num_mel.txt
# grep "sim_" $output/$sample/${sample}.${sample}.original_idxstats.txt | awk -F '\t' '{sum+=$3;} END {print sum;}' > $output/$sample/${sample}.num_sim.txt

#Filter out the simulans contaminants
mel_chromosomes="2L 2R 3L 3R 4 X Y mitochondrion_genome"
sim_chromosomes="sim_2L sim_2R sim_3L sim_3R sim_4 sim_X sim_mtDNA"

samtools view -@ $threads $output/$sample/${sample}.contaminated_realigned.bam $mel_chromosomes -b > $output/$sample/${sample}.mel.bam
samtools view -@ $threads $output/$sample/${sample}.contaminated_realigned.bam $sim_chromosomes -b > $output/$sample/${sample}.sim.bam

mv $output/$sample/${sample}.contaminated_realigned.bam  $output/$sample/${sample}.original.bam
rm $output/$sample/${sample}.contaminated_realigned.bai

samtools mpileup $output/$sample/${sample}.mel.bam -f /opt/hologenome/raw/D_melanogaster_r6.12.fasta > $output/$sample/${sample}.mel_mpileup.txt

/opt/DEST/mappingPipeline/scripts/Mpileup2Snape.sh \
  $output/$sample/${sample}.mel_mpileup.txt \
  $sample \
  $theta \
  $D \
  $priortype \
  $fold

check_exit_status "SNAPE" $?

python /opt/DEST/SNAPE/SNAPE_to_VCF.py ${sample}_SNAPE.txt

check_exit_status "SNAPE_2_VCF" $?

mv ${sample}_SNAPE.txt $output/$sample/${sample}.SNAPE.txt
mv ${sample}_SNAPE.vcf $output/$sample/${sample}.SNAPE.vcf

check_exit_status "mpileup" $?

python3 /opt/DEST/mappingPipeline/scripts/Mpileup2Sync.py \
--mpileup $output/$sample/${sample}.mel_mpileup.txt \
--ref /opt/hologenome/raw/D_melanogaster_r6.12.fasta.pickled.ref \
--output $output/$sample/${sample}

check_exit_status "Mpileup2Sync" $?

python3 /opt/DEST/mappingPipeline/scripts/MaskSYNC.py \
--sync $output/$sample/${sample}.sync.gz \
--output $output/$sample/${sample} \
--indel $output/$sample/${sample}.indel \
--coverage $output/$sample/${sample}.cov \
--mincov $min_cov \
--maxcov $max_cov \
--te /opt/DEST/RepeatMasker/ref/dmel-all-chromosome-r6.12.fasta.out.gff

check_exit_status "MaskSYNC" $?

# gzip $output/$sample/${sample}.cov
# gzip $output/$sample/${sample}.indel

mv $output/$sample/${sample}_masked.sync.gz $output/$sample/${sample}.masked.sync.gz
gunzip $output/$sample/${sample}.masked.sync.gz
bgzip $output/$sample/${sample}.masked.sync
tabix -s 1 -b 2 -e 2 $output/$sample/${sample}.masked.sync.gz

check_exit_status "tabix" $?

gzip $output/$sample/${sample}.mel_mpileup.txt

echo "Read 1: $read1" >> $output/$sample/${sample}.parameters.txt
echo "Read 2: $read2" >> $output/$sample/${sample}.parameters.txt
echo "Sample name: $sample" >> >> $output/$sample/${sample}.parameters.txt
echo "Output directory: $output" >> $output/$sample/${sample}.parameters.txt
echo "Number of cores used: $threads" >> $output/$sample/${sample}.parameters.txt
echo "Max cov: $max_cov" >> $output/$sample/${sample}.parameters.txt
echo "Min cov $min_cov" >> $output/$sample/${sample}.parameters.txt
