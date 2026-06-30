#!/bin/bash
set -e

############################################
# DEFAULT PATHS (HOST PATHS)
############################################
INPUT="/mnt/raid0/home/p2solo/Matteo_scripts/scripts/Trio_vcf_Data/FAM001.wf_trio_snp.vcf.gz"
OUTPUT_DIR="/mnt/raid0/home/p2solo/Matteo_scripts/scripts/output"

PLUGIN_DATA="/mnt/raid0/home/p2solo/Matteo_scripts/scripts/VARIANT_PRIORITIZATION_ANALYSIS/docker-data/plugins"
VEP_CACHE="/mnt/raid0/home/p2solo/Matteo_scripts/scripts/VARIANT_PRIORITIZATION_ANALYSIS/vep_data"

############################################
# OVERRIDE WITH COMMAND-LINE ARGUMENTS
############################################
if [ $# -ge 1 ]; then
    INPUT="$1"
fi
if [ $# -ge 2 ]; then
    OUTPUT_DIR="$2"
fi

mkdir -p "$OUTPUT_DIR"
sudo chown -R "$USER":"$USER" "$OUTPUT_DIR"
sudo chmod -R a+rwx "$OUTPUT_DIR"

############################################
# OUTPUT NAME
############################################
INPUT_BASENAME=$(basename "$INPUT")
INPUT_FILENAME="${INPUT_BASENAME%.vcf.gz}"
OUTPUT="$OUTPUT_DIR/${INPUT_FILENAME}_VEPannotated.vcf.gz"

############################################
# START DOCKER
############################################
sudo systemctl start docker

############################################
# RUN VEP
############################################
docker run -t -i \
  --user $(id -u):$(id -g) \
  -v /mnt/raid0:/mnt/raid0 \
  -v "$OUTPUT_DIR":"$OUTPUT_DIR" \
  -v "$PLUGIN_DATA":/plugins \
  -v "$PLUGIN_DATA/../vep":/vep \
  ensemblorg/ensembl-vep:release_115.0 \
  vep \
    --cache \
    --offline \
    --everything \
    --format vcf \
    --vcf \
    --force_overwrite \
    --assembly GRCh38 \
    --dir_cache "$VEP_CACHE" \
    --dir_plugins /plugins \
    --input_file "$INPUT" \
    --output_file "$OUTPUT" \
    --compress_output bgzip \
    \
    --plugin LoF,\
loftee_path=/plugins/loftee,\
human_ancestor_fa=/plugins/loftee/human_ancestor.fa.gz,\
conservation_file=/plugins/loftee/gerp_conservation_scores.homo_sapiens.GRCh38.bw,\
max_ent_scan=/plugins/maxEntScan,\
splice_data=/plugins/loftee/splice_data \
    \
    --plugin LoFtool \
    \
    --plugin SpliceAI,\
snv=/plugins/spliceai/spliceai_scores.raw.snv.hg38.vcf.gz,\
indel=/plugins/spliceai/spliceai_scores.raw.indel.hg38.vcf.gz,\
snv_spliceai_masked=/plugins/spliceai/spliceai_scores.masked.snv.hg38.vcf.gz,\
indel_spliceai_masked=/plugins/spliceai/spliceai_scores.masked.indel.hg38.vcf.gz \
    \
    --plugin dbNSFP,/plugins/dbnsfp/dbNSFP5.3.1a_grch38.gz,ALL \
    \
    --plugin gnomADc,/plugins/gnomad/genomes/gnomad.genomes.v4.1.1.all.vcf.gz \
    \
    --custom /plugins/curated_lof/curated_lof.vcf.gz,CuratedLoF,vcf,exact,0,Verdict,Gene \
    \
    --fork 16 \
    --buffer_size 20000

############################################
# INDEX OUTPUT
############################################
tabix -p vcf "$OUTPUT"

############################################
# STOP DOCKER
############################################
sudo systemctl stop docker

echo "=========================================="
echo "VEP annotation complete."
echo "Output: $OUTPUT"
echo "Index:  ${OUTPUT}.tbi"
echo "=========================================="

