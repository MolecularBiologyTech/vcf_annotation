#!/bin/bash
set -e

############################################
# BASE DIRECTORIES
############################################
BASE="/mnt/raid0/home/p2solo/Matteo_scripts/scripts/VARIANT_PRIORITIZATION_ANALYSIS"
DOCKER_DATA="$BASE/docker-data"
VEP_DATA="$BASE/vep_data"
PLUGIN_DATA="$BASE/plugin_data"
BASESPACE_DIR="$BASE/BaseSpaceCLI"
BASESPACE_BIN="$BASESPACE_DIR/bs"

TEST_INPUT_VCF="$VEP_DATA/input.vcf"
TEST_OUTPUT_VCF="$VEP_DATA/output.vep.vcf"

mkdir -p "$BASE" "$VEP_DATA" "$PLUGIN_DATA" "$BASESPACE_DIR"
mkdir -p "$PLUGIN_DATA"/{dbnsfp,spliceai,loftee,opentargets}

############################################
# BASESPACE CLI INSTALL
############################################
echo "[BaseSpace] Installing BaseSpace CLI v1..."
wget -q "https://launch.basespace.illumina.com/CLI/latest/amd64-linux/bs" -O "$BASESPACE_BIN"
chmod u+x "$BASESPACE_BIN"
export PATH="$BASESPACE_DIR:$PATH"

############################################
# BASESPACE AUTH CHECK
############################################
if [ ! -f "$HOME/.basespace/default.cfg" ]; then
    echo "[BaseSpace] Authentication required..."
    mkdir -p "$HOME/.basespace"
    $BASESPACE_BIN auth
fi

############################################
# DOCKER SETUP
############################################
sudo apt-get update -y
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

mkdir -p "$DOCKER_DATA"
sudo chown -R "$USER":"$USER" "$DOCKER_DATA"

sudo bash -c "cat > /etc/docker/daemon.json" <<EOF
{
  "data-root": "$DOCKER_DATA"
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

############################################
# PERMISSIONS
############################################
sudo chown -R "$USER":"$USER" "$DOCKER_DATA" "$VEP_DATA" "$PLUGIN_DATA"
sudo chmod -R a+rwx "$DOCKER_DATA" "$VEP_DATA" "$PLUGIN_DATA"

############################################
# VEP 115 INSTALL
############################################
docker pull ensemblorg/ensembl-vep:release_115.0

docker run -t -i \
  -v "$VEP_DATA":/data \
  ensemblorg/ensembl-vep:release_115.0 \
  INSTALL.pl -a cf -s homo_sapiens -y GRCh38

############################################
# SPLICEAI DOWNLOAD
############################################
OUTDIR="$PLUGIN_DATA/spliceai"
mkdir -p "$OUTDIR"

FILES=(16534036123 16534036125 16534036127 16534036128)

for ID in "${FILES[@]}"; do
    $BASESPACE_BIN download file --id $ID --output "$OUTDIR"
done

############################################
# LOFTEE (GRCh38)
############################################
mkdir -p "$PLUGIN_DATA/loftee"
cd "$PLUGIN_DATA/loftee"

wget -c "https://s3.amazonaws.com/bcbio_nextgen/human_ancestor.fa.gz"
wget -c "https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/gerp_conservation_scores.homo_sapiens.GRCh38.bw"
wget -c "https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/loftee.sql.gz"

echo "[LoFTEE] Downloading helper scripts..."

curl -L "https://raw.githubusercontent.com/konradjk/loftee/master/LoF.pm" \
  -o "$PLUGIN_DATA/LoF.pm"

curl -L "https://raw.githubusercontent.com/konradjk/loftee/master/utr_splice.pl" \
  -o "$PLUGIN_DATA/utr_splice.pl"

curl -L "https://raw.githubusercontent.com/konradjk/loftee/master/filter_vep.pl" \
  -o "$PLUGIN_DATA/filter_vep.pl"

chmod +x "$PLUGIN_DATA/utr_splice.pl" "$PLUGIN_DATA/filter_vep.pl"

############################################
# OPENTARGETS (TSV → VCF + index)
############################################
cd "$PLUGIN_DATA/opentargets"

wget -c "https://ftp.ebi.ac.uk/pub/databases/opentargets/genetics/latest/OTGenetics_VEP/OTGenetics.tsv.gz"

TSV="$PLUGIN_DATA/opentargets/OTGenetics.tsv.gz"
VCF="$PLUGIN_DATA/opentargets/OTGenetics.vcf.gz"

if [ -s "$TSV" ]; then
    TMP_VCF="${VCF%.gz}"

    cat <<EOF > "$TMP_VCF"
##fileformat=VCFv4.2
##INFO=<ID=OT_GENEID,Number=1,Type=String,Description="OpenTargets Ensembl Gene ID">
##INFO=<ID=OT_SYMBOL,Number=1,Type=String,Description="OpenTargets Gene Symbol">
##INFO=<ID=OT_GENENAME,Number=1,Type=String,Description="OpenTargets Gene Name">
##INFO=<ID=OT_L2G,Number=1,Type=Float,Description="OpenTargets Locus-to-Gene Score">
#CHROM  POS     ID      REF     ALT     QUAL    FILTER  INFO
EOF

    zcat "$TSV" | \
        awk 'BEGIN{FS="\t"; OFS="\t"}
             NR>1 {
                chr=$1; pos=$2; ref=$3; alt=$4;
                geneid=$5; symbol=$6; genename=$7; l2g=$8;
                gsub(/ /, "_", genename);
                info="OT_GENEID="geneid";OT_SYMBOL="symbol";OT_GENENAME="genename";OT_L2G="l2g;
                print chr, pos, ".", ref, alt, ".", "PASS", info
             }' >> "$TMP_VCF"

    bgzip -f "$TMP_VCF"
    tabix -f -p vcf "$VCF"
fi

############################################
# dbNSFP 5.3.1a + index
############################################
cd "$PLUGIN_DATA/dbnsfp"

wget -c "https://dist.genos.us/academic/e55b09/dbNSFP5.3.1a_grch38.gz"

DBNSFP_FILE="$PLUGIN_DATA/dbnsfp/dbNSFP5.3.1a_grch38.gz"

if [ -s "$DBNSFP_FILE" ]; then
    tabix -s 1 -b 2 -e 2 "$DBNSFP_FILE"
fi

############################################
# VEP PLUGIN .pm FILES
############################################
cd "$PLUGIN_DATA"

declare -A URLS=(
  ["SpliceAI.pm"]="https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/SpliceAI.pm"
  ["dbNSFP.pm"]="https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/dbNSFP.pm"
  ["OpenTargets.pm"]="https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/OpenTargets.pm"
)

for FILE in "${!URLS[@]}"; do
    wget -q -O "$PLUGIN_DATA/$FILE" "${URLS[$FILE]}"
done

chmod -R a+rwx "$PLUGIN_DATA"

############################################
# CREATE MINIMAL TEST VCF
############################################
cat > "$TEST_INPUT_VCF" <<EOF
##fileformat=VCFv4.2
#CHROM  POS     ID      REF     ALT     QUAL     FILTER  INFO
1       832873  .       A       C       .        PASS    .
EOF

############################################
# PLUGIN INTEGRITY CHECK
############################################
echo "=== Checking plugin integrity ==="

check() {
    if [ ! -s "$1" ]; then
        echo "❌ Missing or empty: $1"
    else
        echo "✅ OK: $1"
    fi
}

check "$PLUGIN_DATA/LoF.pm"
check "$PLUGIN_DATA/utr_splice.pl"
check "$PLUGIN_DATA/filter_vep.pl"
check "$PLUGIN_DATA/loftee/human_ancestor.fa.gz"
check "$PLUGIN_DATA/loftee/gerp_conservation_scores.homo_sapiens.GRCh38.bw"
check "$PLUGIN_DATA/spliceai/spliceai_scores.raw.snv.hg38.vcf.gz"
check "$PLUGIN_DATA/spliceai/spliceai_scores.raw.indel.hg38.vcf.gz"
check "$PLUGIN_DATA/dbnsfp/dbNSFP5.3.1a_grch38.gz"
check "$PLUGIN_DATA/dbnsfp/dbNSFP5.3.1a_grch38.gz.tbi"
check "$PLUGIN_DATA/opentargets/OTGenetics.vcf.gz"
check "$PLUGIN_DATA/opentargets/OTGenetics.vcf.gz.tbi"

############################################
# FULL VEP TEST RUN (YOUR EXACT OPTIONS)
############################################
echo "=== Running full VEP test ==="

docker run -t -i \
  -v "$VEP_DATA":/data \
  -v "$PLUGIN_DATA":/plugins \
  ensemblorg/ensembl-vep:release_115.0 \
  vep \
    --cache \
    --offline \
    --everything \
    --no_stats \
    --chr 1 \
    --check_ref \
    --format vcf \
    --vcf \
    --force_overwrite \
    --assembly GRCh38 \
    --dir_cache /data/.vep \
    --input_file /data/$(basename "$TEST_INPUT_VCF") \
    --output_file /data/$(basename "$TEST_OUTPUT_VCF") \
    \
    --plugin LoF,\
loftee_path=/plugins/loftee,\
human_ancestor_fa=/plugins/loftee/human_ancestor.fa.gz,\
conservation_file=/plugins/loftee/gerp_conservation_scores.homo_sapiens.GRCh38.bw \
    \
    --plugin SpliceAI,\
snv=/plugins/spliceai/spliceai_scores.raw.snv.hg38.vcf.gz,\
indel=/plugins/spliceai/spliceai_scores.raw.indel.hg38.vcf.gz \
    \
    --plugin dbNSFP,/plugins/dbnsfp/dbNSFP5.3.1a_grch38.gz,ALL \
    \
    --plugin OpenTargets,file=/plugins/opentargets/OTGenetics.tsv.gz \
    \
    --fork 16 \
    --buffer_size 20000

echo "=========================================="
echo "PIPELINE COMPLETE"
echo "Output: $TEST_OUTPUT_VCF"
echo "=========================================="

