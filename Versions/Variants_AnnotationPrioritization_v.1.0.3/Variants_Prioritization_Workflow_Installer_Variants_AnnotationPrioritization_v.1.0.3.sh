#!/usr/bin/env bash
set -euo pipefail

###############################################
# USER‑CONFIGURABLE VARIABLES
###############################################

BASE="/mnt/raid0/home/p2solo/Matteo_scripts/scripts/VARIANT_PRIORITIZATION_ANALYSIS"   # <----- Choose your base directory
TOOLS_DIR="$BASE/tools"   # All tools will be installed in this subdirectory

ANNOTSV_VERSION="v3.5.10"
CUSTOM_HUMAN_VERSION="3.5"
CUSTOM_EXOMISER_VERSION="2512"

EXOMISER_VERSION="15.0.0"
DATA_VERSION="2512"
REMM_VERSION="0.4"

CONDA_ROOT="$TOOLS_DIR/miniconda3"
ENV_NAME="trio-annot-env"
ENV_NAME_2="multiqc-env"

ANNOTSV_DIR="$TOOLS_DIR/AnnotSV"
# VEP Docker paths (will be set during installation)
DOCKER_DATA="$BASE/docker-data"
VEP_DATA="$BASE/vep_data"
PLUGIN_DATA="$BASE/plugin_data"
VEP_CACHE_DIR="$VEP_DATA"
CLINVAR_DIR="$TOOLS_DIR/clinvar_data"
CADD_DIR="$PLUGIN_DATA/cadd"
# GNOMAD_DIR="$TOOLS_DIR/gnomad_data"  # SKIPPED: Using CADD's built-in gnomAD frequency data
VEP_DIR="$VEP_DATA"
VEP_PLUGIN_DIR="$PLUGIN_DATA"
# FASTA path will be auto-detected from Docker cache structure
FASTA_DIR="$VEP_CACHE_DIR/homo_sapiens"
FASTA_BGZ=""
IGV_INSTALL_DIR="$TOOLS_DIR/IGV_Snapshot"
IGV_REPO_URL="https://github.com/stevekm/IGV-snapshot-automator.git"

HTSLIB_VERSION="1.21"
BCFTOOLS_VERSION="1.21"

###############################################
# Logger
###############################################
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

###############################################
# Ultra‑reliable GitHub downloader
###############################################
download_github_zip() {
    local url="$1"
    local outfile="$2"

    echo "[INFO] Downloading $outfile"

    # Convert GitHub URL → codeload (more reliable)
    local codeload_url="${url/github.com/codeload.github.com}"
    codeload_url="${codeload_url/\/refs\/tags\//\/}"

    echo "[INFO] Trying codeload: $codeload_url"
    if wget -q --tries=5 --timeout=20 "$codeload_url" -O "$outfile"; then
        echo "[OK] Downloaded via codeload"
        return 0
    fi

    echo "[WARN] codeload failed, trying wget original URL"
    if wget -q --tries=5 --timeout=20 "$url" -O "$outfile"; then
        echo "[OK] Downloaded via wget"
        return 0
    fi

    echo "[WARN] wget failed, trying curl"
    if curl -L --retry 5 --retry-delay 5 -o "$outfile" "$url"; then
        echo "[OK] Downloaded via curl"
        return 0
    fi

    if command -v aria2c >/dev/null 2>&1; then
        echo "[WARN] curl failed, trying aria2c"
        if aria2c -x 16 -s 16 -o "$outfile" "$url"; then
            echo "[OK] Downloaded via aria2c"
            return 0
        fi
    fi

    echo "[ERROR] Failed to download $outfile"
    exit 1
}

###############################################
# 1. System dependencies (system Perl + gcc)
###############################################
sudo apt update
sudo apt install -y \
    build-essential wget git make bc curl unzip \
    libssl-dev zlib1g-dev libncurses5-dev libncursesw5-dev \
    libreadline-dev libsqlite3-dev libgdbm-dev libbz2-dev \
    libexpat1-dev liblzma-dev tk-dev uuid-dev \
    tabix aria2

###############################################
# 2. Install Miniconda
###############################################
mkdir -p "$BASE"
mkdir -p "$TOOLS_DIR"
cd "$BASE"

if [ ! -d "$CONDA_ROOT" ]; then
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
    bash miniconda.sh -b -p "$CONDA_ROOT"
    rm miniconda.sh
fi

###############################################
# 3. Conda reliability + mamba
###############################################
source "$CONDA_ROOT/etc/profile.d/conda.sh"
conda init bash

conda config --set remote_read_timeout_secs 120
conda config --set remote_connect_timeout_secs 60
conda config --set remote_max_retries 10

if ! conda list -n base | grep -q mamba; then
    conda install -y -n base -c conda-forge mamba
fi

if command -v mamba >/dev/null 2>&1; then
    MAMBA="mamba"
else
    MAMBA="conda"
fi

###############################################
# 5. ClinVar data
###############################################
log "Downloading ClinVar..."

mkdir -p "$CLINVAR_DIR"
cd "$CLINVAR_DIR"

if [ ! -f "clinvar.vcf.gz" ]; then
    wget ftp://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh38/clinvar.vcf.gz
fi

if [ ! -f "clinvar.vcf.gz.tbi" ]; then
    tabix -p vcf clinvar.vcf.gz
fi

###############################################
# 6. Create conda env (NO PERL!)
###############################################
REQUIRED_TOOLS=(curl unzip samtools bedtools python)

if ! conda env list | grep -q "^${ENV_NAME} "; then
    $MAMBA create -y -n "$ENV_NAME" -c bioconda -c conda-forge "${REQUIRED_TOOLS[@]}" pandas fpdf matplotlib numpy
fi

conda activate "$ENV_NAME"

###############################################
# 8. Build htslib + bcftools (for QC only)
###############################################
log "Building htslib + bcftools..."

conda remove -y bcftools || true

TMPDIR=$(mktemp -d)
cd "$TMPDIR"

wget -q https://github.com/samtools/htslib/releases/download/${HTSLIB_VERSION}/htslib-${HTSLIB_VERSION}.tar.bz2
tar xjf htslib-${HTSLIB_VERSION}.tar.bz2
cd htslib-${HTSLIB_VERSION}
./configure --prefix="$CONDA_ROOT/envs/$ENV_NAME"
make -j"$(nproc)"
make install

cd "$TMPDIR"
wget -q https://github.com/samtools/bcftools/releases/download/${BCFTOOLS_VERSION}/bcftools-${BCFTOOLS_VERSION}.tar.bz2
tar xjf bcftools-${BCFTOOLS_VERSION}.tar.bz2
cd bcftools-${BCFTOOLS_VERSION}
./configure --prefix="$CONDA_ROOT/envs/$ENV_NAME" --with-htslib="$CONDA_ROOT/envs/$ENV_NAME"
make -j"$(nproc)"
make install

export BCFTOOLS_PLUGINS="$CONDA_ROOT/envs/$ENV_NAME/libexec/bcftools"
echo "export BCFTOOLS_PLUGINS=\"$BCFTOOLS_PLUGINS\"" >> "$HOME/.bashrc"

cd /
rm -rf "$TMPDIR"

###############################################
# 9. Install Docker + VEP 115 (Docker-based)
###############################################

DOCKER_DATA="$BASE/docker-data"
VEP_DATA="$BASE/vep_data"
PLUGIN_DATA="$BASE/plugin_data"

echo "=========================================="
echo "Installing Docker + Preparing VEP 115 + Plugins"
echo "=========================================="

###############################################
# Install Docker + required tools
###############################################
sudo apt-get install -y docker.io tabix
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

sudo chown -R "$USER":"$USER" "$DOCKER_DATA"

sudo bash -c "cat > /etc/docker/daemon.json" <<EOF
{
  "data-root": "$DOCKER_DATA"
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

###############################################
# Permissions
###############################################
sudo chown -R "$USER":"$USER" "$DOCKER_DATA" "$VEP_DATA" "$PLUGIN_DATA"
sudo chmod -R a+rwx "$DOCKER_DATA" "$VEP_DATA" "$PLUGIN_DATA"

###############################################
# VEP 115 INSTALL (CACHE INTO VEP_DATA)
###############################################
docker pull ensemblorg/ensembl-vep:release_115.0

docker run -t -i \
  -v "$VEP_DATA":/data \
  ensemblorg/ensembl-vep:release_115.0 \
  INSTALL.pl \
    --AUTO cf \
    --SPECIES homo_sapiens \
    --ASSEMBLY GRCh38 \
    --CACHE_VERSION 115 \
    --DESTDIR /data

###############################################
# Create plugin data directories
###############################################
mkdir -p "$PLUGIN_DATA"/{dbnsfp,spliceai,loftee,gnomad,curated_lof}
sudo chown -R "$USER":"$USER" "$PLUGIN_DATA"
chmod -R 775 "$PLUGIN_DATA"

echo "=========================================="
echo "Downloading plugin datasets"
echo "=========================================="

###############################################
# LOFTEE (GRCh38 DATA → PLUGIN_DATA/loftee)
###############################################
mkdir -p "$PLUGIN_DATA/loftee"
cd "$PLUGIN_DATA/loftee"

wget -c "https://s3.amazonaws.com/bcbio_nextgen/human_ancestor.fa.gz"
wget -c "https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/gerp_conservation_scores.homo_sapiens.GRCh38.bw"
wget -c "https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/loftee.sql.gz"

###############################################
# REQUIRED LoFTEE PLUGIN FILES (GRCh38 → /plugins)
###############################################
cd "$PLUGIN_DATA"

curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/LoF.pm" -o LoF.pm
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/gerp_dist.pl" -o gerp_dist.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/loftee_splice_utils.pl" -o loftee_splice_utils.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/utr_splice.pl" -o utr_splice.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/filter_vep.pl" -o filter_vep.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/de_novo_donor.pl" -o de_novo_donor.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/de_novo_acceptor.pl" -o de_novo_acceptor.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_site_scan.pl" -o splice_site_scan.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/extended_splice.pl" -o extended_splice.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/svm.pl" -o svm.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/context.pm" -o context.pm
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/ancestral.pm" -o ancestral.pm

chmod +x "$PLUGIN_DATA"/*.pl

###############################################
# MOVE LoFTEE FILES INTO CORRECT DIRECTORY
###############################################
echo "[LoFTEE] Moving plugin files into /plugins/loftee ..."

cp $PLUGIN_DATA/LoF.pm $PLUGIN_DATA/loftee/
mv $PLUGIN_DATA/gerp_dist.pl $PLUGIN_DATA/loftee/
mv $PLUGIN_DATA/loftee_splice_utils.pl $PLUGIN_DATA/loftee/
cp $PLUGIN_DATA/utr_splice.pl $PLUGIN_DATA/loftee/
mv $PLUGIN_DATA/filter_vep.pl $PLUGIN_DATA/loftee/
mv $PLUGIN_DATA/de_novo_donor.pl $PLUGIN_DATA/loftee/
mv $PLUGIN_DATA/de_novo_acceptor.pl $PLUGIN_DATA/loftee/
mv $PLUGIN_DATA/splice_site_scan.pl $PLUGIN_DATA/loftee/
mv $PLUGIN_DATA/extended_splice.pl $PLUGIN_DATA/loftee/
mv $PLUGIN_DATA/svm.pl $PLUGIN_DATA/loftee/
cp $PLUGIN_DATA/context.pm $PLUGIN_DATA/loftee/
cp $PLUGIN_DATA/ancestral.pm $PLUGIN_DATA/loftee/

###############################################
# INSTALL MaxEntScan (→ /plugins/maxEntScan)
###############################################
echo "[LoFTEE] Installing MaxEntScan splice-site scoring scripts..."

MAXENT_DIR="$PLUGIN_DATA/maxEntScan"
mkdir -p "$MAXENT_DIR"
cd "$MAXENT_DIR"

curl -L "https://raw.githubusercontent.com/konradjk/loftee/master/maxEntScan/score3.pl" -o score3.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/master/maxEntScan/score5.pl" -o score5.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/master/maxEntScan/maxentscan_score3.pl" -o maxentscan_score3.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/master/maxEntScan/maxentscan_score5.pl" -o maxentscan_score5.pl

chmod +x *.pl

###############################################
# INSTALL LoFTEE splice_data
###############################################
echo "[LoFTEE] Installing splice_data..."

SPLICE_DATA_DIR="$PLUGIN_DATA/loftee/splice_data"
mkdir -p "$SPLICE_DATA_DIR/donor_motifs" "$SPLICE_DATA_DIR/acceptor_motifs" "$SPLICE_DATA_DIR/pwm"

curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_data/donor_motifs/ese.txt" -o "$SPLICE_DATA_DIR/donor_motifs/ese.txt"
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_data/donor_motifs/ess.txt" -o "$SPLICE_DATA_DIR/donor_motifs/ess.txt"

curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_data/acceptor_motifs/ese.txt" -o "$SPLICE_DATA_DIR/acceptor_motifs/ese.txt"
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_data/acceptor_motifs/ess.txt" -o "$SPLICE_DATA_DIR/acceptor_motifs/ess.txt"

curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_data/pwm/donor_pwm.txt" -o "$SPLICE_DATA_DIR/pwm/donor_pwm.txt"
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_data/pwm/acceptor_pwm.txt" -o "$SPLICE_DATA_DIR/pwm/acceptor_pwm.txt"

###############################################
# dbNSFP 5.3.1a + index
###############################################
cd "$PLUGIN_DATA/dbnsfp"

wget -c "https://dist.genos.us/academic/e55b09/dbNSFP5.3.1a_grch38.gz"

DBNSFP_FILE="$PLUGIN_DATA/dbnsfp/dbNSFP5.3.1a_grch38.gz"

if [ -s "$DBNSFP_FILE" ]; then
    tabix -f -s 1 -b 2 -e 2 "$DBNSFP_FILE"
fi

###############################################
# VEP PLUGIN .pm FILES
###############################################
cd "$PLUGIN_DATA"

wget -q -O LoFtool.pm https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/LoFtool.pm
wget -q -O LoFtool_scores.txt https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/LoFtool_scores.txt
wget -q -O SpliceAI.pm https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/SpliceAI.pm
wget -q -O dbNSFP.pm https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/dbNSFP.pm
wget -q -O dbNSFP_replacement_logic https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/dbNSFP_replacement_logic
wget -q -O gnomADc.pm https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/gnomADc.pm

chmod a+r LoFtool.pm LoFtool_scores.txt SpliceAI.pm dbNSFP.pm dbNSFP_replacement_logic gnomADc.pm

###############################################
# gnomAD GENOMES v4.1.1
###############################################
GNOMAD_VERSION="4.1.1"
GNOMAD_BASE_URL="https://storage.googleapis.com/gcp-public-data--gnomad/release/${GNOMAD_VERSION}/vcf/genomes"

GNOMAD_DIR="$PLUGIN_DATA/gnomad/genomes"
mkdir -p "$GNOMAD_DIR"
cd "$GNOMAD_DIR"

for CHR in {1..22} X Y; do
  FILE="gnomad.genomes.v${GNOMAD_VERSION}.sites.chr${CHR}.vcf.bgz"
  wget -c "${GNOMAD_BASE_URL}/${FILE}"
  wget -c "${GNOMAD_BASE_URL}/${FILE}.tbi"
done

###############################################
# gnomAD curated LoF — FIXED SORTING + INDEXING
###############################################
CURATED_DIR="$PLUGIN_DATA/curated_lof"
cd "$CURATED_DIR"

wget -c "https://storage.googleapis.com/gcp-public-data--gnomad/release/4.1/lof_curation/incomplete_penetrance_curation_results.csv"

cat > convert_curated_lof_csv_to_vcf.sh <<'EOF'
#!/bin/bash
set -e

CSV="$1"
OUTVCF="$2"

echo "##fileformat=VCFv4.2" > "$OUTVCF"
echo "##INFO=<ID=Verdict,Number=1,Type=String,Description=\"gnomAD curated LoF verdict\">" >> "$OUTVCF"
echo "##INFO=<ID=Gene,Number=1,Type=String,Description=\"Gene symbol\">" >> "$OUTVCF"
echo "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO" >> "$OUTVCF"

tail -n +2 "$CSV" | while IFS=',' read -r variant_id gene verdict rest; do
    chrom=$(echo "$variant_id" | cut -d'-' -f1)
    pos=$(echo "$variant_id" | cut -d'-' -f2)
    ref=$(echo "$variant_id" | cut -d'-' -f3)
    alt=$(echo "$variant_id" | cut -d'-' -f4)

    gene_symbol=$(echo "$gene" | cut -d':' -f2)

    INFO="Verdict=$verdict;Gene=$gene_symbol"

    echo -e "$chrom\t$pos\t.\t$ref\t$alt\t.\tPASS\t$INFO" >> "$OUTVCF"
done
EOF

chmod +x convert_curated_lof_csv_to_vcf.sh

./convert_curated_lof_csv_to_vcf.sh incomplete_penetrance_curation_results.csv curated_lof.vcf

echo "Sorting curated_lof..."
sort -k1,1 -k2,2n curated_lof.vcf > curated_lof.sorted.vcf

echo "Compressing curated_lof..."
bgzip -f curated_lof.sorted.vcf

echo "Indexing curated_lof..."
tabix -f -p vcf curated_lof.sorted.vcf.gz

mv curated_lof.sorted.vcf.gz curated_lof.vcf.gz
mv curated_lof.sorted.vcf.gz.tbi curated_lof.vcf.gz.tbi

###############################################
# FIX 1 — LoFTEE helper scripts must exist in /plugins
###############################################
echo "[LoFTEE] Copying helper scripts to /plugins..."
LOF_HELPERS=(
  gerp_dist.pl
  de_novo_donor.pl
  de_novo_acceptor.pl
  splice_site_scan.pl
  extended_splice.pl
  svm.pl
  filter_vep.pl
  loftee_splice_utils.pl
  utr_splice.pl
)

for f in "${LOF_HELPERS[@]}"; do
  if [ -f "$PLUGIN_DATA/loftee/$f" ]; then
    cp "$PLUGIN_DATA/loftee/$f" "$PLUGIN_DATA/"
  fi
done

###############################################
# FIX 2 — LoFTEE splice_data must exist at /vep/loftee/splice_data
###############################################
echo "[LoFTEE] Copying splice_data to /vep/loftee..."
mkdir -p "$PLUGIN_DATA/../vep/loftee"
cp -r "$PLUGIN_DATA/loftee/splice_data" "$PLUGIN_DATA/../vep/loftee/"

###############################################
# FIX 3 — Merge gnomAD genomes into a single file
###############################################
echo "[gnomADc] Merging per-chromosome VCFs..."
GNOMAD_DIR="$PLUGIN_DATA/gnomad/genomes"
MERGED="$GNOMAD_DIR/gnomad.genomes.v4.1.1.all.vcf.gz"

if [ ! -f "$MERGED" ]; then
    bcftools concat -Oz -o "$MERGED" $GNOMAD_DIR/*.vcf.bgz
    tabix -p vcf "$MERGED"
    echo "[gnomADc] Deleting individual chromosome VCFs..."
    rm $GNOMAD_DIR/gnomad.genomes.v*.sites.chr*.vcf.bgz
    rm $GNOMAD_DIR/gnomad.genomes.v*.sites.chr*.vcf.bgz.tbi
fi

###############################################
# FIX 4 — dbNSFP README required
###############################################
echo "[dbNSFP] Creating README..."
if [ ! -f "$PLUGIN_DATA/dbnsfp/README.txt" ]; then
    echo "dbNSFP 5.3.1a dataset" > "$PLUGIN_DATA/dbnsfp/README.txt"
fi

echo "=========================================="
echo "INSTALLATION COMPLETE"
echo "=========================================="
echo "Docker storage: $DOCKER_DATA"
echo "VEP cache:      $VEP_DATA"
echo "Plugins root:   $PLUGIN_DATA  (mounted as /plugins)"

###############################################
# 15. Install AnnotSV
###############################################
log "Installing AnnotSV..."

rm -rf "$ANNOTSV_DIR"
git clone -b "$ANNOTSV_VERSION" https://github.com/lgmgeo/AnnotSV.git "$ANNOTSV_DIR"

cd "$ANNOTSV_DIR"
make PREFIX=. install

make PREFIX=. \
    HUMAN_VERSION="${CUSTOM_HUMAN_VERSION}" \
    EXOMISER_VERSION="${CUSTOM_EXOMISER_VERSION}" \
    install-human-annotation

echo "export ANNOTSV=$ANNOTSV_DIR" >> "$HOME/.bashrc"

###############################################
# 16. MultiQC environment
###############################################
conda activate "$ENV_NAME"

if ! conda env list | grep -q "^${ENV_NAME_2} "; then
    $MAMBA create -y -n "$ENV_NAME_2" -c conda-forge -c bioconda python=3.10 multiqc
fi

###############################################
# 17. Install Exomiser
###############################################
log "Installing Exomiser..."

# Check if Exomiser is already installed
cd "$TOOLS_DIR"
EXOMISER_DIR=$(find . -maxdepth 1 -type d -name "exomiser-cli-*" | head -n 1)

if [ -n "$EXOMISER_DIR" ]; then
    log "Exomiser installation detected in $TOOLS_DIR/${EXOMISER_DIR}"
    log "Checking for REMM data..."

    # Check if REMM data already exists
    REMM_EXISTS=false

    if [ -f "${EXOMISER_DIR}/data/remm/${REMM_VERSION}/ReMM.v${REMM_VERSION}.hg38.tsv.gz" ]; then
        REMM_EXISTS=true
        log "REMM data already present."
    fi

    # Download missing data
    if [ "$REMM_EXISTS" = false ]; then
        log "Downloading missing REMM data..."

        mkdir -p "${EXOMISER_DIR}/data/remm/${REMM_VERSION}"

        # Download REMM data if missing (FIXED URL)
        log "Downloading REMM v${REMM_VERSION} data for hg38..."
        wget -O "${EXOMISER_DIR}/data/remm/${REMM_VERSION}/ReMM.v${REMM_VERSION}.hg38.tsv.gz" \
            https://kircherlab.bihealth.org/download/ReMM/ReMM.v${REMM_VERSION}.hg38.tsv.gz

        wget -O "${EXOMISER_DIR}/data/remm/${REMM_VERSION}/ReMM.v${REMM_VERSION}.hg38.tsv.gz.tbi" \
            https://kircherlab.bihealth.org/download/ReMM/ReMM.v${REMM_VERSION}.hg38.tsv.gz.tbi

        log "REMM update complete."
    else
        log "REMM data already present. No update needed."
    fi

else
    # Check for required tools
    if ! command -v java &> /dev/null; then
        log "Error: Java is not installed. Exomiser requires Java to run."
        log "Skipping Exomiser installation."
    else
        log "Downloading Exomiser program..."

        # FIXED GITHUB URL FORMAT
        wget -O exomiser-cli-${EXOMISER_VERSION}-distribution.zip \
            https://github.com/exomiser/Exomiser/releases/download/${EXOMISER_VERSION}/exomiser-cli-${EXOMISER_VERSION}-distribution.zip

        log "Extracting Exomiser program..."
        unzip -q exomiser-cli-${EXOMISER_VERSION}-distribution.zip

        log "Creating data directory..."
        mkdir -p exomiser-cli-${EXOMISER_VERSION}/data

        log "Downloading Exomiser data files (approximately 80 GB)..."
        wget https://g-879a9f.f5dc97.75bc.dn.glob.us/data/${DATA_VERSION}_phenotype.zip
        wget https://g-879a9f.f5dc97.75bc.dn.glob.us/data/${DATA_VERSION}_hg38.zip

        log "Extracting data files..."
        unzip -q ${DATA_VERSION}_phenotype.zip -d exomiser-cli-${EXOMISER_VERSION}/data
        unzip -q ${DATA_VERSION}_hg38.zip -d exomiser-cli-${EXOMISER_VERSION}/data

        log "Creating directories for optional data sources (REMM)..."
        mkdir -p exomiser-cli-${EXOMISER_VERSION}/data/remm/${REMM_VERSION}

        # FIXED REMM URLs
        log "Downloading REMM v${REMM_VERSION} data for hg38..."
        wget -O exomiser-cli-${EXOMISER_VERSION}/data/remm/${REMM_VERSION}/ReMM.v${REMM_VERSION}.hg38.tsv.gz \
            https://kircherlab.bihealth.org/download/ReMM/ReMM.v${REMM_VERSION}.hg38.tsv.gz

        wget -O exomiser-cli-${EXOMISER_VERSION}/data/remm/${REMM_VERSION}/ReMM.v${REMM_VERSION}.hg38.tsv.gz.tbi \
            https://kircherlab.bihealth.org/download/ReMM/ReMM.v${REMM_VERSION}.hg38.tsv.gz.tbi

        # Create final application.properties
        log "Creating final application.properties..."

        cat > exomiser-cli-${EXOMISER_VERSION}/application.properties <<EOF
#
# Exomiser configuration file
# Updated for hg38 + REMM v0.4
#

############################################
# ROOT DATA DIRECTORY
############################################
exomiser.data-directory=${TOOLS_DIR}/exomiser-cli-${EXOMISER_VERSION}/data

############################################
# OPTIONAL DATA SOURCES
############################################
remm.version=0.4
exomiser.hg38.remm-path=\${exomiser.data-directory}/remm/\${remm.version}/ReMM.v0.4.hg38.tsv.gz

############################################
# GENOME ASSEMBLY DATA VERSIONS
############################################
exomiser.hg38.data-version=2512
exomiser.genome-analysis.hg38=true
exomiser.genome-analysis.hg19=false

############################################
# PHENOTYPE DATA
############################################
exomiser.phenotype.data-version=2512

############################################
# CACHING
############################################
spring.cache.type=caffeine
spring.cache.caffeine.spec=maximumSize=60000

############################################
# LOGGING
############################################
logging.file.name=logs/exomiser.log
logging.level.com.zaxxer.hikari=ERROR
EOF

        log "Creating logs directory..."
        mkdir -p exomiser-cli-${EXOMISER_VERSION}/logs

        ###############################################
        # CLEAN UP ZIP FILES (ONLY IN THIS BRANCH)
        ###############################################
        rm -f "${TOOLS_DIR}/exomiser-cli-${EXOMISER_VERSION}-distribution.zip"
        rm -f "${TOOLS_DIR}/${DATA_VERSION}_phenotype.zip"
        rm -f "${TOOLS_DIR}/${DATA_VERSION}_hg38.zip"

        log "Exomiser installation complete."
    fi
fi

###############################################
# 18. Install IGV Snapshot Automator
###############################################
log "Installing IGV Snapshot Automator..."

log "[1/6] Installing IGV dependencies..."
sudo apt install -y python3 python3-pip wget unzip xvfb x11-utils default-jre openjdk-8-jre

JAVA8_PATH=$(update-alternatives --list java | grep "java-8" | head -n 1)
if [ -z "$JAVA8_PATH" ]; then
    log "ERROR: Java 8 not found"
    exit 1
fi
log "Java 8 detected at: $JAVA8_PATH"

log "[2/6] Cloning IGV repository..."
rm -rf "$TOOLS_DIR/IGV_Snapshot"
cd "$TOOLS_DIR"
git clone "$IGV_REPO_URL" "IGV_Snapshot"

log "[3/6] Installing IGV..."
cd "$TOOLS_DIR/IGV_Snapshot"
make install

PATCH_FILE="$TOOLS_DIR/IGV_Snapshot/make_IGV_snapshots.py"
cp "$PATCH_FILE" "$PATCH_FILE.bak"

log "[4/6] Applying patches..."

# Disable X-server detection
sed -i 's/x_serv_port = get_open_X_server()/# x_serv_port = get_open_X_server()/g' "$PATCH_FILE"
sed -i 's/print(.*x_serv_port.*)//g' "$PATCH_FILE"

# Replace IGV command with Java 8 + xvfb-run
sed -i "s|java -Xmx|xvfb-run -a $JAVA8_PATH -Xmx|g" "$PATCH_FILE"

# Insert width/height AFTER the -s argument block
sed -i '/help="Group reads by forward\/reverse strand."/a \
    parser.add_argument("-w", "--width", type=int, default=2000, help="Snapshot width in pixels")\n    parser.add_argument("-H", "--height", type=int, default=800, help="Snapshot height in pixels")' "$PATCH_FILE"

# Fix batchscript writer
sed -i 's/batchscript.write("snapshotHeight/batchscript.write("snapshotWidth {}\\n".format(args.width))\nbatchscript.write("snapshotHeight/' "$PATCH_FILE"

log "[5/6] Setting permissions..."
chmod +x "$PATCH_FILE"

log "[6/6] IGV Snapshot Automator installation complete."
log "Patched Python script:"
log "  - Adds -w (width)"
log "  - Adds -H (height)"
log "  - Uses Java 8"
log "  - Uses xvfb-run"
log "  - Disables X-server detection"
log ""
log "Run IGV snapshots with:"
log "  python3 make_IGV_snapshots.py -w 4000 -H 1200 ..."

###############################################
# 19. Final confirmation
###############################################
echo "=============================================="
echo "AnnotSV installed at: $ANNOTSV_DIR"
echo "VEP installed at: $VEP_DIR"
echo "VEP cache at: $VEP_CACHE_DIR"
echo "FASTA installed at: $FASTA_BGZ"
echo "CADD v1.6 installed at: $CADD_DIR"
# echo "gnomAD genomes installed at: $GNOMAD_DIR"  # SKIPPED: Using CADD's built-in gnomAD frequency data
echo "ClinVar VCF installed at: $CLINVAR_DIR"
echo "Conda environment: $ENV_NAME"
echo "MultiQC environment: $ENV_NAME_2"
echo "Exomiser installed at: $TOOLS_DIR/exomiser-cli-${EXOMISER_VERSION}"
echo "IGV Snapshot Automator installed at: $TOOLS_DIR/IGV_Snapshot"
echo "bcftools plugins directory: $BCFTOOLS_PLUGINS"
echo "Unified installation complete."
echo "=============================================="


###############################################
# 20. Generate analysis scripts
###############################################

echo "=============================================="
echo "Generating analysis scripts in BASE"
echo "=============================================="

# Generate script 0 (README)
cat > "$BASE/0_README_Trio_Analysis_Workflow.md" << 'EOF'
# Trio Analysis Workflow - Complete Documentation

## Overview

This workflow is designed for **trio-based de novo variant detection and prioritization** in rare Mendelian diseases. It combines comprehensive annotation, stringent quality control, and phenotype-driven analysis to identify pathogenic variants in affected children.

---

## Prioritization Workflow

### Step 0 - Quality Filtering
- **MIN_DP ≥10**: Minimum depth for reliable genotype calls
- **MIN_GQ ≥20**: Genotype quality ≥99% confidence
- **Purpose**: Ensures only high-confidence variants proceed to analysis
- **Implementation**: Applied during bcftools filtering in 2_Run_analysis.sh 

### Step 1 - Inheritance Filtering
- **Trio-based de novo pattern detection**
  - Child has variant (0/1, 1/1, or 1 on chrX for males)
  - Both parents are reference (0/0)
- **Purpose**: Prevents inherited variants from being misclassified as de novo
- **Implementation**: Lines 2340-2368 in 2_Run_analysis.sh 
- **Additional safeguards**:
  - X-linked de novo guard (chrX in males)
  - Parental alt-read suppression (AD_ALT == 0 for parents)
  - Allelic balance filtering (0.3-0.7 for child)

### Step 2 - Population Frequency Filtering
- **AF_THRESHOLD="0.001"** (0.1%, stricter than standard 1%)
- **Checks all gnomAD AF fields**:
  - INFO/AF
  - INFO/gnomAD_AF
  - INFO/gnomADg_AF
  - INFO/gnomADg_AF_popmax
  - INFO/gnomAD_exomes_AF
  - INFO/gnomAD_genomes_AF
- **Purpose**: Removes common polymorphisms, retains ultra-rare variants
- **Implementation**: Lines 2317-2324 in 2_Run_analysis.sh 

### Step 3 - Variant Effect Filtering
The workflow generates **two separate VCFs**:

#### LoF VCF (filtered_LoF.vcf.gz)
- **High-impact coding variants only**:
  - stop_gained
  - frameshift_variant
  - splice_acceptor_variant
  - splice_donor_variant
  - start_lost
  - stop_lost
- **Additional filters**:
  - CADD_PHRED > 20 OR missing
  - REVEL > 0.5 OR missing
  - SpliceAI > 0.2 OR missing
  - AnnotSV pathogenic/likely_pathogenic OR missing

#### Non-coding VCF (filtered_non_coding.vcf.gz)
- **Regulatory/intronic/intergenic variants**
- **No consequence filter** (retains all non-coding variants)
- **Purpose**: Allows REMM-based regulatory variant prioritization

### Step 4 - Clinical Database Annotation (ClinVar)
- **ClinVar is NOT used for filtering**
- **ClinVar annotations are included for manual review**
- **Rationale**: See "Why ClinVar is NOT used for direct filtering" below

### Step 5 - Phenotype-Driven Prioritization
- **Exomiser with HPO terms**
  - hiPhive prioritizer: Phenotype similarity scoring
  - OMIM prioritizer: Matches variants to known diseases
- **Implementation**: Lines 2524-2528 in 2_Run_analysis.sh 
- **Output**: Ranked candidate variants with gene-level and variant-level scores

---

## Why ClinVar is NOT Used for Direct Filtering

### 1. Novel Pathogenic Variants
- Rare diseases often involve newly discovered pathogenic variants not yet in ClinVar
- Filtering by ClinVar would exclude these novel but clinically relevant variants
- ~30-50% of pathogenic de novo variants in rare diseases are not in ClinVar

### 2. ClinVar Coverage Limitations
- ClinVar is biased toward well-studied genes and common diseases
- Many rare disease genes have limited ClinVar annotations
- Structural variants (SVs) have poor ClinVar coverage compared to SNVs

### 3. False Negatives in ClinVar
- Variants may be classified as "VUS" (Uncertain Significance) but still be pathogenic
- Lag between discovery and ClinVar submission/curated classification
- Different submitters may have conflicting interpretations

### 4. Complementary Approach (This Workflow's Method)
- ClinVar annotations are **included in output for manual review**
- Exomiser's OMIM prioritizer indirectly captures clinical database associations
- Pathogenicity scores (CADD, REVEL, SpliceAI) provide computational evidence
- Phenotype matching (HPO terms) is more powerful for rare diseases than database lookup

### 5. Clinical Best Practice
- ACMG guidelines recommend using ClinVar as **supporting evidence**, not a filter
- Combining multiple evidence types (frequency, pathogenicity, phenotype) is more robust
- Manual review of ClinVar status is preferred over automated filtering

### Summary
This workflow uses ClinVar as an **annotation layer for manual review** rather than a filtering criterion. This approach maximizes sensitivity for novel pathogenic variants while still providing ClinVar context for interpretation.

---

## Tools Used and Their Purposes

### Core Bioinformatics Tools

| Tool | Version | Purpose |
|------|---------|---------|
| **VEP** (Variant Effect Predictor) | 116.0 (Docker) | Annotates SNVs/indels with functional consequences, gene names, and pathogenicity scores |
| **AnnotSV** | v3.5.10 | Annotates structural variants (SVs) with clinical significance, gene overlap, and population frequency |
| **Exomiser** | 15.0.0 | Phenotype-driven variant prioritization using HPO terms and disease databases |
| **bcftools** | 1.21 | VCF manipulation, filtering, and trio-based de novo detection |
| **samtools** | Latest | BAM/SAM file processing and genome indexing |
| **bedtools** | Latest | Genomic interval operations and region analysis |
| **Docker** | Latest | Containerization platform for VEP execution |

### Supporting Tools

| Tool | Purpose |
|------|---------|
| **Miniconda + mamba** | Package management and conda environment setup |
| **MultiQC** | Quality control report aggregation |
| **IGV Snapshot Automator** | Automated IGV visualization for variant validation |

---

## Annotation Sources and Origins

### VEP Annotation Databases (for SNVs/Indels)

| Database | Version | Source | Purpose |
|----------|---------|--------|---------|
| **ClinVar** | Latest | NCBI FTP (ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh38/) | Clinical significance annotations (pathogenic/benign classifications) |
| **CADD** | v1.6 | Kircher Lab (kircherlab.bihealth.org) | Combined Annotation Dependent Depletion scores for pathogenicity prediction |
| **dbNSFP** | v5.3.1 | SoftGenetics (dbnsfp.softgenetics.com) | Comprehensive functional annotation database with multiple prediction scores |
| **SpliceAI** | Latest | Broad Institute (storage.googleapis.com/broad-ml4cv-public) | Deep learning-based splice site effect prediction |
| **REVEL** | Latest | MSSM (rothsj06.u.hpc.mssm.edu) | Rare Exome Variant Ensemble Learner for missense variant pathogenicity |
| **AlphaMissense** | Latest | DeepMind (storage.googleapis.com/alphamissense) | Deep learning missense pathogenicity prediction |
| **LOFTEE** | Latest | GitHub (konradjk/loftee) | Loss-of-function transcript effect estimator for filtering spurious LoF variants |
| **OpenTargets** | Latest | OpenTargets (storage.googleapis.com/open-targets-data-releases) | Drug target associations and therapeutic insights |
| **gnomAD v4** | Latest | gnomAD (gnomad.broadinstitute.org) | Latest population frequency data from large-scale sequencing projects |
| **VEP Cache** | v116.0 | Ensembl (Docker container) | Pre-computed variant annotations for fast lookup |

### AnnotSV Annotation Databases (for Structural Variants)

| Database | Version | Source | Purpose |
|----------|---------|--------|---------|
| **ClinVar** | Latest | NCBI FTP | Clinical significance annotations for SVs |
| **CADD** | v1.6 | Kircher Lab | CADD scores for SV pathogenicity prediction (via AnnotSV) |
| **gnomAD** | Latest | gnomAD | Population frequency data for SVs |
| **AnnotSV Annotations** | v3.5.10 | AnnotSV built-in | SV-specific annotations including ACMG classifications, gene overlap, and clinical significance |
| **Exomiser** | 2512 | Exomiser | Gene-disease associations and phenotype data |
| **REMM** | v0.4 | Kircher Lab | Regulatory element missense mutation scores for non-coding variants |

---

## Annotations Added to Raw VCF

### SNV/Indel VCF Annotations (via VEP)

VEP adds comprehensive annotations to the **CSQ INFO field**. Each variant's CSQ field contains multiple pipe-separated values:

| Annotation | Field in CSQ | Description | Use in Prioritization |
|------------|--------------|-------------|----------------------|
| **Consequence** | Consequence | Variant consequence (e.g., stop_gained, frameshift) | Identifies high-impact variants |
| **SYMBOL** | SYMBOL | Gene symbol | Gene-based prioritization |
| **CADD_PHRED** | CADD_PHRED | CADD Phred-scaled score (v1.6) | Pathogenicity prediction (score >20 = top 1%) |
| **REVEL** | REVEL | Rare Exome Variant Ensemble Learner score | Missense variant pathogenicity (score >0.5 = likely pathogenic) |
| **SpliceAI** | SpliceAI | Deep learning splice site prediction | Splice variant assessment (score >0.2 = significant) |
| **AlphaMissense** | AlphaMissense | Deep learning missense pathogenicity | State-of-the-art missense variant prediction |
| **dbNSFP** | Multiple fields | Comprehensive functional prediction scores | Cross-reference multiple predictors |
| **LOFTEE** | LoF_flag | Loss-of-function transcript effect | Filters spurious LoF variants |
| **OpenTargets** | OpenTargets | Drug target associations | Therapeutic insights |
| **gnomAD v4 AF** | gnomADg_AF | Latest population frequencies (v4) | Updated rarity filtering |
| **CLNSIG** | CLNSIG | ClinVar clinical significance | Known disease associations |
| **CLNREVSTAT** | CLNREVSTAT | ClinVar review status | Confidence in clinical interpretation |
| **CLNDN** | CLNDN | ClinVar disease name | Associated disease information |
| **gnomAD_AF** | gnomAD_AF | Legacy population frequencies | Cross-reference rarity metrics |

**Example CSQ field structure:**
``
CSQ=Consequence|SYMBOL|CADD_PHRED|REVEL|SpliceAI|AlphaMissense|CLNSIG|CLNREVSTAT|...
`

### SV VCF Annotations (via AnnotSV)

AnnotSV adds annotations as **separate INFO fields** to the SV VCF:

| Annotation | INFO Field | Description | Use in Prioritization |
|------------|-----------|-------------|----------------------|
| **Gene** | Gene | Overlapping gene symbols | Gene-based prioritization |
| **SVTYPE** | SVTYPE | Structural variant type (DEL, DUP, INV, INS) | Variant classification |
| **ANNOTSV** | ANNOTSV | AnnotSV pathogenicity classification | Clinical significance |
| **gnomAD_AF** | gnomAD_AF | Population frequency | Rarity filtering |
| **gnomADg_AF** | gnomADg_AF | gnomAD genome frequency | Population-specific rarity |
| **gnomADg_AF_popmax** | gnomADg_AF_popmax | Maximum population frequency | Conservative rarity filtering |
| **ACMG_Classification** | ACMG_Classification | ACMG pathogenicity classification | Clinical interpretation |
| **Disease_Mechanism** | Disease_Mechanism | Known disease mechanism | Gene-disease association |
| **HI_ClinVar** | HI_ClinVar | ClinVar haploinsufficiency score | Dosage sensitivity |

---

## Workflow Architecture

### Input Files
- **INPUT_SV_VCF**: Structural variants VCF (gzipped)
- **INPUT_SNP_VCF**: SNV/indel VCF (gzipped)
- **PED_FILE**: Trio pedigree file (FAMID INDID FATHER MOTHER SEX PHENOTYPE)
- **PROBAND_BAM, FATHER_BAM, MOTHER_BAM**: BAM files for IGV visualization
- **GENOME_FASTA**: Reference genome (GRCh38)

### Output Structure
`
ANALYSIS_OUTPUT_DIR/
├── 01_annotated_sv/
│   ├── trio_SV_annotated.tsv
│   └── trio_SV_annotated.vcf.gz
├── 02_annotated_snv/
│   ├── trio_SNP_annotated.vcf.gz
│   └── SNP_stats.txt
├── 03_exomiser_phenotype_filt/
│   ├── filtered_LoF.vcf.gz
│   ├── filtered_non_coding.vcf.gz
│   ├── exomiser_results_LoF/
│   └── exomiser_results_non_coding/
└── 04_IGV_snapshots/
    └── [IGV snapshot images]
``

---

## Usage Instructions

1. **Run installation script** to install tools and download databases
2. **Edit 1_Define_data_specs.txt** with your data paths and HPO terms
3. **Run 2_Run_analysis.sh** to execute the complete pipeline
4. **Review results** in the output directory
5. **Examine Exomiser HTML reports** for phenotype-driven prioritization
6. **Check IGV snapshots** for visual validation of top candidates

---

## Key Features

- **Comprehensive annotation**: VEP + AnnotSV for both SVs and SNVs
- **Stringent trio-based filtering**: bcftools for true de novo detection
- **Phenotype-driven prioritization**: Exomiser with HPO terms
- **Quality control**: MultiQC reports and automated QC
- **Visual validation**: Automated IGV snapshots for top candidates
- **ClinVar-aware**: Annotations included for manual review without filtering
- **Regulatory variant support**: REMM-based non-coding variant prioritization
- **Reproducible**: Docker-based VEP, conda environments, version-controlled databases

---

## References

- VEP: https://www.ensembl.org/info/docs/tools/vep/index.html
- AnnotSV: https://github.com/lgmgeo/AnnotSV
- Exomiser: https://github.com/exomiser/Exomiser
- ClinVar: https://www.ncbi.nlm.nih.gov/clinvar/
- gnomAD: https://gnomad.broadinstitute.org/
- CADD: https://cadd.gs.washington.edu/
- REVEL: https://sites.google.com/site/jpopgen/revel
- SpliceAI: https://github.com/Illumina/SpliceAI

---

**Version**: 1.0  
**Last Updated**: 2026-06-21  
**Genome Assembly**: GRCh38  
**Analysis Type**: Trio-based de novo variant detection and prioritization
EOF

echo "Created: $BASE/0_README_Trio_Analysis_Workflow.md"

# Generate script 1 (configuration template)
cat > "$BASE/1_Define_data_specs.txt" << 'EOF'
#!/bin/bash
# USER CONFIGURATION FILE
# Edit all variables below before running script 2

# ============================================================
# 1. Data parameters
# ============================================================

# Analysis output directory (where all results will be saved)
ANALYSIS_OUTPUT_DIR="/path/to/analysis/output"

# Analysis name (e.g., TRIO_HUG, FAM001, etc.)
ANALYSIS_NAME=""

# Sample IDs (AUTO-DETECTED from PED file - do not edit manually)
# The following will be automatically extracted from PED_FILE:
#   - FAM_ID (Family ID)
#   - PROBAND (Affected individual, phenotype=2)
#   - FATHER (Father ID from proband row)
#   - MOTHER (Mother ID from proband row)
#   - CHILD_SEX (Proband sex: 1=male, 2=female)

# Input files (absolute paths)
INPUT_SV_VCF="/path/to/your/sv.vcf.gz"
INPUT_SNP_VCF="/path/to/your/snp.vcf.gz"
PED_FILE="/path/to/your/family.ped"

# BAM files for IGV visualization
PROBAND_BAM="/path/to/proband.bam"
FATHER_BAM="/path/to/father.bam"
MOTHER_BAM="/path/to/mother.bam"

# Reference genome
GENOME_FASTA="/path/to/reference/genome.fa.gz"



# ============================================================
# 2. FILTERING PARAMETERS (trio-based de novo + QC + rarity). * See bottom of the page for explanation !
# ============================================================

# Allele frequency threshold (gnomAD)
AF_THRESHOLD="0.001"

# Allelic balance range for child (heterozygous variants)
AB_MIN="0.3"
AB_MAX="0.7"

# Genotype quality thresholds
MIN_DP="10"
MIN_GQ="20"

# Pathogenicity thresholds (LoF VCF only)
CADD_PHRED_THRESHOLD="20"
REVEL_THRESHOLD="0.5"
SPLICEAI_THRESHOLD="0.2"



# ============================================================
# 3. EXOMISER PARAMETERS
# ============================================================

# HPO terms (phenotype identifiers)
HPO_TERMS=(
    "HP:0000430"   # Arhinia
    "HP:0000568"   # Microphthalmia
    "HP:0008188"   # Hypogonadotropic hypogonadism
    "HP:0001999"   # Facial dysmorphism
    "HP:0000453"   # Choanal atresia
    "HP:0000589"   # Coloboma
    "HP:0000518"   # Cataract
)

# OMIM disease ID
OMIM_DISEASE_ID="OMIM:603457"

# Exomiser priority score settings
PRIORITY_TYPE="HIPHIVE_PRIORITY"
MIN_PRIORITY_SCORE="0.501"

# Exomiser analysis mode options:
#   PASS_ONLY - Only analyzes variants that pass initial quality filters (faster, focused on high-quality variants)
#   FULL - Analyzes all variants regardless of quality filters (slower, more comprehensive)
EXOMISER_ANALYSIS_MODE="PASS_ONLY"

# Exomiser output options:
#   true - Only outputs variants that contribute to phenotype/prioritization score (smaller output, focused on candidates)
#   false - Outputs all variants that pass the analysis (larger output, includes all filtered variants)
EXOMISER_OUTPUT_CONTRIBUTING_ONLY="false"



# ============================================================
# 4. IGV SNAPSHOT PARAMETERS
# ============================================================


# IGV snapshot settings
IGV_MEMORY="102400"
VIEWPORT_FRACTION="15"     #<-----Increse to make variant size smaller in IGV snapshots. 
SNAPSHOT_WIDTH=4000
SNAPSHOT_HEIGHT=1200










# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# * DETAILED EXPLANATION TO CHOOSE VALUES in point 2.
#
# De novo + compound-heterozygous WGS filter (SNVs + SVs)
# Produces TWO VCFs for Exomiser:
#   1) filtered_LoF.vcf.gz        → coding, LoF-only
#   2) filtered_non_coding.vcf.gz → non-coding only
# Trio-based filtering using bcftools
#
#
# INPUTS:
#   - Joint VCF (SNVs + SVs), annotated with:
#       * VEP (CSQ: Consequence, SYMBOL, CADD_PHRED, REVEL, SpliceAI)
#       * AnnotSV (SVTYPE, ANNOTSV, gnomAD* AF fields)
#   - PED file with trio (FAMID INDID FATHER MOTHER SEX PHENOTYPE)
#
#
# 1) Trio & de novo pattern
# -------------------------
# A de novo variant is present in the affected child and absent in both parents.
# This is the strongest genetic signal for severe early-onset disease.
#
# CHILD GT allowed:
#   - 0/1, 1/1, 0|1, 1|0 → heterozygous or homozygous alt
#   - 1 → hemizygous alt on chrX in males
#
# PARENTS:
#   - MOTHER GT = 0/0
#   - FATHER GT = 0/0
#
# Prevents:
#   - inherited variants misclassified as de novo
#   - parental mosaicism being misinterpreted
#   - mis-genotyping of parents or child
#
#
# 2) Robust rarity filter (all gnomAD fields)
# -------------------------------------------
# De novo pathogenic variants are almost always absent or extremely rare in
# population databases. Different tools annotate AF differently, so we check:
#
#   INFO/AF                < 0.001 OR missing
#   INFO/gnomAD_AF         < 0.001 OR missing
#   INFO/gnomADg_AF        < 0.001 OR missing
#   INFO/gnomADg_AF_popmax < 0.001 OR missing
#   INFO/gnomAD_exomes_AF  < 0.001 OR missing
#   INFO/gnomAD_genomes_AF < 0.001 OR missing
#
# This:
#   - keeps ultra-rare variants across SNVs, INDELs, SVs
#   - allows missing AF (common for rare SVs)
#   - removes common polymorphisms and population-specific benign variants
#
#
# 3) Allelic balance (child) & parent alt-read suppression
# --------------------------------------------------------
# For a true heterozygous variant in the child:
#
#   ALT fraction = AD_ALT / (AD_REF + AD_ALT) ≈ 0.5
#
# We accept 0.3–0.7 to allow for noise and mapping bias.
#
# CHILD:
#   - 0.3 ≤ ALT fraction ≤ 0.7
#
# PARENTS:
#   - AD_ALT == 0 (no alt reads)
#
# Prevents:
#   - false de novo calls from sequencing noise
#   - parental mosaicism being miscalled as de novo
#   - contamination and misalignment artifacts
#
#
# 4) Genotype quality filters
# ---------------------------
# DP ≥ 10 and GQ ≥ 20 for all trio members.
#
# DP (depth):
#   - below 10 reads, allelic balance and genotype calls are unreliable.
#
# GQ (genotype quality, Phred-scaled):
#   - GQ 20 ≈ 99% confidence in the genotype.
#
# Prevents:
#   - false positives from low coverage
#   - unstable genotypes in noisy regions
#
#
# 5) SVTYPE sanity rules
# ----------------------
# Structural variant callers and AnnotSV sometimes emit records where the child
# is 0/0 but the SV is still listed.
#
# We exclude SVs where:
#   - CHILD GT == 0/0 for that SVTYPE (DEL, DUP, INV, INS)
#
# Prevents:
#   - spurious SV records
#   - placeholder or multi-sample artifacts
#
#
# 6) X-linked de novo guard
# -------------------------
# For chrX in males:
#   - GT=1 means the variant is present on the only X chromosome.
#   - Mother must be 0/0 for a true de novo event.
#
# Prevents:
#   - inherited maternal variants misclassified as de novo
#   - misinterpretation of hemizygous calls
#
#
# 7) VEP consequence filter (LoF-only, for coding VCF)
# ----------------------------------------------------
# Keeps only HIGH-impact protein-truncating variants:
#   - stop_gained
#   - frameshift_variant
#   - splice_acceptor_variant
#   - splice_donor_variant
#   - start_lost
#   - stop_lost
#
# These are the most likely to cause severe Mendelian disease and are enriched
# among pathogenic de novo variants.
#
# NOTE:
#   This step removes non-coding variants. It is applied only to the LoF VCF.
#
#
# 8) CADD, REVEL, SpliceAI thresholds (LoF VCF only)
# --------------------------------------------------
#   - CADD_PHRED > 20  → top ~1% most deleterious variants genome-wide
#   - REVEL > 0.5      → strong predictor of pathogenic missense
#   - SpliceAI > 0.2   → meaningful predicted effect on splicing
#
# Missing values are allowed so that unannotated variants are not discarded.
#
# Prevents:
#   - weakly damaging or likely benign variants dominating the candidate list
#
#
# 9) AnnotSV pathogenicity filter (LoF VCF only)
# ----------------------------------------------
# For SVs, AnnotSV provides curated pathogenicity tags.
#
# We keep variants where:
#   - ANNOTSV contains "pathogenic" or "likely_pathogenic"
#   - OR ANNOTSV is missing (for SNVs without AnnotSV)
#
# Enriches:
#   - clinically relevant SVs
#   - avoids dropping SNVs due to missing AnnotSV annotation
#
#
# 10) Compound-heterozygous candidates (post-step)
# ------------------------------------------------
# After filtering, we count genes (INFO/SYMBOL) with ≥2 hits in the LoF VCF.
# These genes are candidates for compound-heterozygous configurations:
#   - two different damaging alleles in the same gene
#   - typically one inherited from each parent
EOF

echo "Created: $BASE/1_Define_data_specs.txt"

# Generate script 2 (analysis pipeline)
cat > "$BASE/2_Run_analysis.sh" << 'ENDOFSCRIPT'
#!/bin/bash
set -euo pipefail

################################################################################
# COMPLETE TRIO ANALYSIS PIPELINE
#
# Combines:
#   • Part 1: SV & SNV/Indel Annotation
#   • Part 2: Variant Prioritization with Exomiser
#   • Part 3: IGV Visualization
################################################################################

############################################
# AUTO-DETECT BASE FROM INSTALLATION
############################################

# Find the installation directory by locating exomiser-cli-15.0.0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Check if exomiser-cli exists in tools directory
TOOLS_DIR="$PARENT_DIR/tools"
if [ -d "$TOOLS_DIR/exomiser-cli-15.0.0" ]; then
    BASE="$PARENT_DIR"
elif [ -d "$SCRIPT_DIR/tools/exomiser-cli-15.0.0" ]; then
    BASE="$SCRIPT_DIR"
else
    # Try to find it by searching upward
    SEARCH_DIR="$SCRIPT_DIR"
    while [ "$SEARCH_DIR" != "/" ]; do
        if [ -d "$SEARCH_DIR/tools/exomiser-cli-15.0.0" ]; then
            BASE="$SEARCH_DIR"
            break
        fi
        SEARCH_DIR="$(dirname "$SEARCH_DIR")"
    done
fi

if [ -z "$BASE" ]; then
    echo "ERROR: Could not auto-detect installation directory (BASE)"
    echo "Please ensure Variants_Prioritization_Installing.sh was run successfully"
    exit 1
fi

TOOLS_DIR="$BASE/tools"
echo "Auto-detected BASE: $BASE"
echo "Auto-detected TOOLS_DIR: $TOOLS_DIR"

############################################
# SOURCE USER CONFIGURATION
############################################

CONFIG_FILE="$SCRIPT_DIR/1_Define_data_specs.txt"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    echo "Please edit 1_Define_data_specs.txt before running this script"
    exit 1
fi

source "$CONFIG_FILE"

############################################
# DERIVED VARIABLES (auto-calculated)
############################################

# Create analysis output directory structure
ANALYSIS_DIR="${ANALYSIS_OUTPUT_DIR}/${ANALYSIS_NAME}_variants_prioritization_analysis"

# Folder for raw input files
RAW_INPUT_DIR="$ANALYSIS_DIR/raw_vcf_Epi2ME_Triowf"

# Folder 1: Annotated SV VCF
SV_ANNOTATED_DIR="$ANALYSIS_DIR/01_annotated_sv"

# Folder 2: Annotated SNV VCF
SNV_ANNOTATED_DIR="$ANALYSIS_DIR/02_annotated_snv"

# Folder 3: Intermediate files + Exomiser outputs
WORKFLOW_DIR="$ANALYSIS_DIR/03_exomiser_phenotype_filt"
WORKFLOW_INTERMEDIATE="$WORKFLOW_DIR/intermediate"
WORKFLOW_EXOMISER_OUTPUT="$WORKFLOW_DIR"
WORKFLOW_EXOMISER_OUTPUT_LOF="$WORKFLOW_DIR/exomiser_results_LoF"
WORKFLOW_EXOMISER_OUTPUT_NONCODING="$WORKFLOW_DIR/exomiser_results_non_coding"

# Folder 4: Regions + IGV snapshots
IGV_DIR="$ANALYSIS_DIR/04_igv_visualization"
IGV_SNAPSHOTS_DIR_LOF="$IGV_DIR/snapshots_LoF"
IGV_SNAPSHOTS_DIR_NONCODING="$IGV_DIR/snapshots_non_coding"

# Folder 5: QC raw output Epi2ME vcfs
QC_RAW_OUTPUT_DIR="$ANALYSIS_DIR/QC raw output Epi2ME vcfs"

# Exomiser installation directories
TOOLS_DIR="$BASE/tools"
EXOMISER_DIR="$TOOLS_DIR/exomiser-cli-15.0.0"
EXOMISER_JAR="${EXOMISER_DIR}/exomiser-cli-15.0.0.jar"
EXOMISER_DATA="${EXOMISER_DIR}/data"
EXOMISER_PROPS="${EXOMISER_DIR}/application.properties"

# Exomiser files
EXOMISER_YAML="$WORKFLOW_DIR/exomiser_config.yml"
EXOMISER_INPUT_VCF="$WORKFLOW_DIR/sv.exomiser.vcf.gz"
EXOMISER_PED="$WORKFLOW_DIR/family.ped"
EXOMISER_OUTPUT_FILENAME="${ANALYSIS_NAME}_exomiser_results"
EXOMISER_OUTDIR="$WORKFLOW_EXOMISER_OUTPUT"

# IGV directories (redefine from installation dir to analysis dir)
IGV_INSTALLATION_DIR="$TOOLS_DIR/IGV_Snapshot"
IGV_OUTPUT_DIR_LOF="$IGV_SNAPSHOTS_DIR_LOF"
IGV_OUTPUT_DIR_NONCODING="$IGV_SNAPSHOTS_DIR_NONCODING"
IGV_REGIONS_FILE_LOF="$IGV_DIR/exomiser_regions_LoF.bed"
IGV_REGIONS_FILE_NONCODING="$IGV_DIR/exomiser_regions_non_coding.bed"

# BAM files array
BAM_FILES=("$PROBAND_BAM" "$FATHER_BAM" "$MOTHER_BAM")

# Tool paths
ANNOTSV="$TOOLS_DIR/AnnotSV"
# VEP Docker paths
DOCKER_DATA="$BASE/docker-data"
VEP_DATA="$BASE/vep_data"
PLUGIN_DATA="$BASE/plugin_data"
VEP_BIN_DIR="$VEP_DATA"
VEP_CACHE_DIR="$VEP_DATA"
VEP_PLUGIN_DIR="$PLUGIN_DATA"
CLINVAR_DIR="$TOOLS_DIR/clinvar_data"
CADD_DIR="$PLUGIN_DATA/cadd"
ASSEMBLY="GRCh38"

# Conda configuration
if [[ -d "/opt/miniconda3" ]]; then
    CONDA_ROOT="/opt/miniconda3"
else
    CONDA_ROOT="$TOOLS_DIR/miniconda3"
fi

ENV_MAIN="trio-annot-env"
ENV_MULTIQC="multiqc-env"

# AnnotSV TSV (will be created if not exists)
ANNOTSV_TSV="$SV_ANNOTATED_DIR/trio_SV_annotated.tsv"

# IGV variables from config
IGV_GENOME="$GENOME_FASTA"

# Input VCFs for prioritization (will be from annotation output)
SNV_VCF="$SNV_ANNOTATED_DIR/trio_SNP_annotated.vcf.gz"
SV_VCF="$SV_ANNOTATED_DIR/trio_annotated_SV.vcf.gz"

############################################
# SETUP ANALYSIS DIRECTORY
############################################

echo "=========================================="
echo "Setting up analysis directory"
echo "=========================================="
echo "Analysis directory: $ANALYSIS_DIR"

mkdir -p "$ANALYSIS_DIR"
mkdir -p "$RAW_INPUT_DIR"
mkdir -p "$SV_ANNOTATED_DIR"
mkdir -p "$SNV_ANNOTATED_DIR"
mkdir -p "$WORKFLOW_INTERMEDIATE"
mkdir -p "$WORKFLOW_EXOMISER_OUTPUT_LOF"
mkdir -p "$WORKFLOW_EXOMISER_OUTPUT_NONCODING"
mkdir -p "$IGV_DIR"
mkdir -p "$IGV_SNAPSHOTS_DIR_LOF"
mkdir -p "$IGV_SNAPSHOTS_DIR_NONCODING"
mkdir -p "$QC_RAW_OUTPUT_DIR"
chmod -R u+rwX "$ANALYSIS_DIR"

# Copy input files to analysis directory
echo "Copying input files to analysis directory..."
cp "$INPUT_SV_VCF" "$RAW_INPUT_DIR/"
cp "$INPUT_SNP_VCF" "$RAW_INPUT_DIR/"
cp "$PED_FILE" "$RAW_INPUT_DIR/"

# Update input paths to use copies in analysis directory
INPUT_SV_VCF="$RAW_INPUT_DIR/$(basename $INPUT_SV_VCF)"
INPUT_SNP_VCF="$RAW_INPUT_DIR/$(basename $INPUT_SNP_VCF)"
EXOMISER_PED="$RAW_INPUT_DIR/$(basename $PED_FILE)"

echo "Input files copied successfully"

############################################
# LOGGING
############################################
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

############################################
# ACTIVATE CONDA ENVIRONMENT (needed for Python QC)
############################################
log "[INFO] Activating conda environment for Python QC..."
source "$CONDA_ROOT/etc/profile.d/conda.sh"
conda activate "$ENV_MAIN"

############################################
# STEP 0: RAW VCF QC (FIRST STEP)
############################################

log "=========================================="
log "STEP 0: RAW VCF QC ANALYSIS"
log "=========================================="

log "[INFO] Running Python QC analysis on raw VCF files..."

# Run Python QC pipeline (embedded)
python3 - "$INPUT_SNP_VCF" "$INPUT_SV_VCF" "$EXOMISER_PED" "$QC_RAW_OUTPUT_DIR/raw_vcf_qc_report.pdf" << 'PYTHON_CODE'
#!/usr/bin/env python3
"""
Consolidated VCF Analysis Pipeline
Takes SNP VCF, SV VCF, and PED file paths as input.
Generates PDF report with embedded histograms (no PNG files saved).
"""

import argparse
import gzip
import re
import io
import sys
import os
import tempfile
from fpdf import FPDF
import matplotlib.pyplot as plt
import numpy as np


def parse_ped_file(ped_path):
    """Parse PED file and infer family relationships and health status."""
    family_info = {}
    
    with open(ped_path, 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 6:
                family_id = parts[0]
                individual_id = parts[1]
                father_id = parts[2]
                mother_id = parts[3]
                sex = parts[4]  # 1=male, 2=female
                phenotype = parts[5]  # 1=unaffected/healthy, 2=affected/sick
                
                role = ""
                health = "Healthy" if phenotype == "1" else "Sick"
                
                if father_id == "0" and mother_id == "0":
                    role = "Father" if sex == "1" else "Mother"
                else:
                    role = "Son" if sex == "1" else "Daughter"
                
                family_info[individual_id] = {
                    'role': role,
                    'health': health,
                    'father_id': father_id,
                    'mother_id': mother_id
                }
    
    return family_info


def parse_vcf_header(vcf_path):
    """Parse VCF header and extract INFO field definitions."""
    info_fields = {}
    format_fields = {}
    filter_fields = {}
    alt_fields = {}
    columns = []
    
    # Determine if file is gzipped
    if vcf_path.endswith('.gz'):
        opener = gzip.open
        mode = 'rt'
    else:
        opener = open
        mode = 'r'
    
    with opener(vcf_path, mode) as f:
        for line in f:
            line = line.strip()
            if line.startswith('##INFO='):
                info_match = re.search(r'##INFO=<ID=([^,]+),Number=([^,]+),Type=([^,]+),Description="([^"]+)">', line)
                if info_match:
                    field_id = info_match.group(1)
                    number = info_match.group(2)
                    field_type = info_match.group(3)
                    description = info_match.group(4)
                    info_fields[field_id] = {
                        'Number': number,
                        'Type': field_type,
                        'Description': description
                    }
            elif line.startswith('##FORMAT='):
                format_match = re.search(r'##FORMAT=<ID=([^,]+),Number=([^,]+),Type=([^,]+),Description="([^"]+)">', line)
                if format_match:
                    field_id = format_match.group(1)
                    number = format_match.group(2)
                    field_type = format_match.group(3)
                    description = format_match.group(4)
                    format_fields[field_id] = {
                        'Number': number,
                        'Type': field_type,
                        'Description': description
                    }
            elif line.startswith('##FILTER='):
                filter_match = re.search(r'##FILTER=<ID=([^,]+),Description="([^"]+)">', line)
                if filter_match:
                    field_id = filter_match.group(1)
                    description = filter_match.group(2)
                    filter_fields[field_id] = description
            elif line.startswith('##ALT='):
                alt_match = re.search(r'##ALT=<ID=([^,]+),Description="([^"]+)">', line)
                if alt_match:
                    field_id = alt_match.group(1)
                    description = alt_match.group(2)
                    alt_fields[field_id] = description
            elif line.startswith('#CHROM'):
                columns = line.split('\t')
                break
    
    return info_fields, format_fields, filter_fields, alt_fields, columns


def generate_summary_text(snp_vcf_path, sv_vcf_path, ped_path, output_path):
    """Generate summary text file from VCF and PED files."""
    family_info = parse_ped_file(ped_path)
    
    snp_info, snp_format, snp_filters, snp_alts, snp_columns = parse_vcf_header(snp_vcf_path)
    sv_info, sv_format, sv_filters, sv_alts, sv_columns = parse_vcf_header(sv_vcf_path)
    
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write("\n")
        f.write("=" * 80 + "\n")
        f.write("VCF COLUMN REFERENCE:\n")
        f.write("=" * 80 + "\n")
        f.write("\n")
        f.write("Standard VCF columns:\n")
        f.write("  1. #CHROM      - Chromosome name\n")
        f.write("  2. POS         - 1-based position of variant\n")
        f.write("  3. ID          - Variant identifier (usually '.' if none)\n")
        f.write("  4. REF         - Reference allele\n")
        f.write("  5. ALT         - Alternate allele(s)\n")
        f.write("  6. QUAL        - Quality score\n")
        f.write("  7. FILTER      - Filter status (PASS if passed)\n")
        f.write("  8. INFO        - Semicolon-separated list of info fields\n")
        f.write("  9+. FORMAT     - Format of genotype fields (if samples present)\n")
        f.write("  10+. Sample columns - Genotype data for each sample\n")
        f.write("\n")
        f.write("INFO fields contain additional variant-specific information.\n")
        f.write("The INFO column is semicolon-separated: KEY=VALUE;KEY2=VALUE2;...\n")
        f.write("\n")
        
        f.write("=" * 80 + "\n")
        f.write("SNP VCF FILE\n")
        f.write("=" * 80 + "\n")
        f.write(f"File: {snp_vcf_path}\n")
        f.write("\n")
        
        f.write("COLUMN STRUCTURE:\n")
        f.write("-" * 80 + "\n")
        for i, col in enumerate(snp_columns, 1):
            if i >= 10 and col in family_info:
                f.write(f"  {i}. {col} ({family_info[col]['role']}, {family_info[col]['health']})\n")
            else:
                f.write(f"  {i}. {col}\n")
        f.write("\n")
        
        f.write(f"INFO FIELDS ({len(snp_info)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, field_info in sorted(snp_info.items()):
            f.write(f"  {field_id:20s} | Type: {field_info['Type']:8s} | Number: {field_info['Number']:5s} | {field_info['Description']}\n")
        
        f.write(f"\nFORMAT FIELDS ({len(snp_format)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, field_info in sorted(snp_format.items()):
            desc = field_info['Description']
            if field_id == 'RNC':
                f.write(f"  {field_id:20s} | Type: {field_info['Type']:8s} | Number: {field_info['Number']:5s} | {desc}\n")
                f.write("                                     I = gVCF input site is non-called, D = insufficient Depth of coverage, - = unrepresentable overlapping deletion,\n")
                f.write("                                     L = Lost/unrepresentable allele (other than deletion), U = multiple Unphased variants present,\n")
                f.write("                                     O = multiple Overlapping variants present, 1 = site is Monoallelic, no assertion about presence of REF or ALT allele\n")
            else:
                f.write(f"  {field_id:20s} | Type: {field_info['Type']:8s} | Number: {field_info['Number']:5s} | {desc}\n")
        
        f.write(f"\nFILTER DEFINITIONS ({len(snp_filters)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, description in sorted(snp_filters.items()):
            f.write(f"  {field_id:20s} | {description}\n")
        
        f.write("\n")
        f.write("=" * 80 + "\n")
        f.write("SV VCF FILE\n")
        f.write("=" * 80 + "\n")
        f.write(f"File: {sv_vcf_path}\n")
        f.write("\n")
        
        f.write("COLUMN STRUCTURE:\n")
        f.write("-" * 80 + "\n")
        for i, col in enumerate(sv_columns, 1):
            if i >= 10 and col in family_info:
                f.write(f"  {i}. {col} ({family_info[col]['role']}, {family_info[col]['health']})\n")
            else:
                f.write(f"  {i}. {col}\n")
        f.write("\n")
        
        f.write(f"INFO FIELDS ({len(sv_info)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, field_info in sorted(sv_info.items()):
            desc = field_info['Description']
            if field_id == 'PHASE':
                f.write(f"  {field_id:20s} | Type: {field_info['Type']:8s} | Number: {field_info['Number']:5s} | {desc}\n")
                f.write("                                    HAPLOTYPE,PHASESET,HAPLOTYPE_SUPPORT,PHASESET_SUPPORT,HAPLOTYPE_FILTER,PHASESET_FILTER\n")
            else:
                f.write(f"  {field_id:20s} | Type: {field_info['Type']:8s} | Number: {field_info['Number']:5s} | {desc}\n")
        
        f.write(f"\nFORMAT FIELDS ({len(sv_format)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, field_info in sorted(sv_format.items()):
            f.write(f"  {field_id:20s} | Type: {field_info['Type']:8s} | Number: {field_info['Number']:5s} | {field_info['Description']}\n")
        
        f.write(f"\nALT FIELD DEFINITIONS ({len(sv_alts)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, description in sorted(sv_alts.items()):
            f.write(f"  {field_id:20s} | {description}\n")
        
        f.write(f"\nFILTER DEFINITIONS ({len(sv_filters)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, description in sorted(sv_filters.items()):
            f.write(f"  {field_id:20s} | {description}\n")


def extract_qual_dp_gq_snp(vcf_path):
    """Extract QUAL, DP and GQ values from SNP VCF."""
    qual_values = []
    dp_values = []
    gq_values = []
    
    with open(vcf_path, 'r') as f:
        for line in f:
            if line.startswith('#'):
                continue
            parts = line.strip().split('\t')
            if len(parts) < 10:
                continue
            
            qual = parts[5]
            if qual != '.':
                try:
                    qual_values.append(float(qual))
                except ValueError:
                    pass
            
            format_field = parts[8]
            format_keys = format_field.split(':')
            
            dp_index = None
            gq_index = None
            for i, key in enumerate(format_keys):
                if key == 'DP':
                    dp_index = i
                elif key == 'GQ':
                    gq_index = i
            
            sample_data = parts[9]
            sample_values = sample_data.split(':')
            
            if dp_index is not None and len(sample_values) > dp_index:
                dp = sample_values[dp_index]
                if dp != '.':
                    try:
                        dp_values.append(int(dp))
                    except ValueError:
                        pass
            
            if gq_index is not None and len(sample_values) > gq_index:
                gq = sample_values[gq_index]
                if gq != '.':
                    try:
                        gq_values.append(int(gq))
                    except ValueError:
                        pass
    
    return np.array(qual_values), np.array(dp_values), np.array(gq_values)


def extract_qual_dp_gq_sv(vcf_path):
    """Extract QUAL, DP (DR+DV) and GQ values from SV VCF."""
    qual_values = []
    dp_values = []
    gq_values = []
    
    with gzip.open(vcf_path, 'rt') as f:
        for line in f:
            if line.startswith('#'):
                continue
            parts = line.strip().split('\t')
            if len(parts) < 10:
                continue
            
            qual = parts[5]
            if qual != '.':
                try:
                    qual_values.append(float(qual))
                except ValueError:
                    pass
            
            format_field = parts[8]
            format_keys = format_field.split(':')
            
            dr_index = None
            dv_index = None
            gq_index = None
            for i, key in enumerate(format_keys):
                if key == 'DR':
                    dr_index = i
                elif key == 'DV':
                    dv_index = i
                elif key == 'GQ':
                    gq_index = i
            
            sample_data = parts[9]
            sample_values = sample_data.split(':')
            
            # Calculate total depth as DR + DV
            dr = 0
            dv = 0
            if dr_index is not None and len(sample_values) > dr_index:
                dr_val = sample_values[dr_index]
                if dr_val != '.':
                    try:
                        dr = int(dr_val)
                    except ValueError:
                        pass
            
            if dv_index is not None and len(sample_values) > dv_index:
                dv_val = sample_values[dv_index]
                if dv_val != '.':
                    try:
                        dv = int(dv_val)
                    except ValueError:
                        pass
            
            if dr > 0 or dv > 0:
                dp_values.append(dr + dv)
            
            if gq_index is not None and len(sample_values) > gq_index:
                gq = sample_values[gq_index]
                if gq != '.':
                    try:
                        gq_values.append(int(gq))
                    except ValueError:
                        pass
    
    return np.array(qual_values), np.array(dp_values), np.array(gq_values)


def create_histogram_figure(data, title, xlabel, ylabel, bins=50, log_scale=False):
    """Create histogram figure and return as bytes."""
    fig = plt.figure(figsize=(10, 6))
    
    if len(data) == 0:
        plt.text(0.5, 0.5, 'No data available', ha='center', va='center', transform=plt.gca().transAxes)
    else:
        plt.hist(data, bins=bins, edgecolor='black', alpha=0.7, color='steelblue')
        if log_scale:
            plt.yscale('log')
    
    plt.title(title, fontsize=14, fontweight='bold')
    plt.xlabel(xlabel, fontsize=12)
    plt.ylabel(ylabel, fontsize=12)
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    
    # Save to temporary file
    temp_file = tempfile.NamedTemporaryFile(suffix='.png', delete=False)
    plt.savefig(temp_file.name, format='png', dpi=150, bbox_inches='tight')
    plt.close(fig)
    temp_file.close()
    return temp_file.name


class PDFReport(FPDF):
    def __init__(self):
        super().__init__(format='A4', unit='mm', orientation='L')
        self.base_path = ""
    
    def header(self):
        pass
    
    def footer(self):
        pass


def convert_to_pdf(txt_file, pdf_file, snp_histograms, sv_histograms):
    """Convert text summary to PDF with embedded histograms."""
    pdf = PDFReport()
    pdf.add_page()
    
    # Font settings
    pdf.set_font("Courier", size=8)
    line_height = 5
    
    # Read and process text file
    with open(txt_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    i = 0
    while i < len(lines):
        line = lines[i].rstrip('\n')
        
        if not line.strip():
            pdf.ln(line_height)
            i += 1
            continue
        
        # Print line character by character with character width
        char_width = 1.67
        page_width = pdf.w - 2 * pdf.l_margin
        max_chars = int(page_width / char_width)
        
        if len(line) > max_chars:
            # Split long lines
            for j in range(0, len(line), max_chars):
                chunk = line[j:j + max_chars]
                pdf.cell(0, line_height, txt=chunk, ln=True)
        else:
            pdf.cell(0, line_height, txt=line, ln=True)
        
        i += 1
    
    # Add SNP histograms page
    pdf.add_page()
    pdf.set_font("Courier", size=12)
    pdf.cell(0, 10, txt="SNP VCF HISTOGRAMS", ln=True)
    
    # 2x2 grid layout with explicit Y positioning - maximized
    col_width = 120
    row1_y = 20
    row2_y = 100
    col1_x = 25
    col2_x = 155
    
    # Row 1
    if snp_histograms[0]:
        pdf.image(snp_histograms[0], x=col1_x, y=row1_y, w=col_width)
    if snp_histograms[1]:
        pdf.image(snp_histograms[1], x=col2_x, y=row1_y, w=col_width)
    
    # Row 2
    if snp_histograms[2]:
        pdf.image(snp_histograms[2], x=col1_x, y=row2_y, w=col_width)
    if snp_histograms[3]:
        pdf.image(snp_histograms[3], x=col2_x, y=row2_y, w=col_width)
    
    # Add SV histograms page
    pdf.add_page()
    pdf.set_font("Courier", size=12)
    pdf.cell(0, 10, txt="SV VCF HISTOGRAMS", ln=True)
    
    # 2x2 grid layout with explicit Y positioning - maximized
    # Row 1
    if sv_histograms[0]:
        pdf.image(sv_histograms[0], x=col1_x, y=row1_y, w=col_width)
    if sv_histograms[1]:
        pdf.image(sv_histograms[1], x=col2_x, y=row1_y, w=col_width)
    
    # Row 2
    if sv_histograms[2]:
        pdf.image(sv_histograms[2], x=col1_x, y=row2_y, w=col_width)
    if sv_histograms[3]:
        pdf.image(sv_histograms[3], x=col2_x, y=row2_y, w=col_width)
    
    pdf.output(pdf_file)
    print(f"PDF saved to: {pdf_file}")
    
    # Clean up temporary histogram files
    for hist_file in snp_histograms + sv_histograms:
        if hist_file and os.path.exists(hist_file):
            os.unlink(hist_file)


if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: python3 - <snp_vcf> <sv_vcf> <ped> <output_pdf>", file=sys.stderr)
        sys.exit(1)
    
    snp_vcf_path = sys.argv[1]
    sv_vcf_path = sys.argv[2]
    ped_path = sys.argv[3]
    output_pdf = sys.argv[4]
    
    print("=" * 80)
    print("VCF ANALYSIS PIPELINE")
    print("=" * 80)
    print(f"SNP VCF: {snp_vcf_path}")
    print(f"SV VCF: {sv_vcf_path}")
    print(f"PED file: {ped_path}")
    print(f"Output: {output_pdf}")
    print()
    
    # Generate summary text
    print("Generating summary text...")
    summary_txt = "vcf_info_summary.txt"
    generate_summary_text(snp_vcf_path, sv_vcf_path, ped_path, summary_txt)
    print(f"Summary saved to: {summary_txt}")
    
    # Extract data for histograms
    print("\nExtracting data from SNP VCF...")
    snp_qual, snp_dp, snp_gq = extract_qual_dp_gq_snp(snp_vcf_path)
    print(f"  QUAL: {len(snp_qual)}, DP: {len(snp_dp)}, GQ: {len(snp_gq)}")
    
    print("\nExtracting data from SV VCF...")
    sv_qual, sv_dp, sv_gq = extract_qual_dp_gq_sv(sv_vcf_path)
    print(f"  QUAL: {len(sv_qual)}, DP: {len(sv_dp)}, GQ: {len(sv_gq)}")
    
    # Generate histograms in memory
    print("\nGenerating histograms in memory...")
    
    # SNP histograms
    snp_hist_qual = create_histogram_figure(snp_qual, "SNP VCF - Quality (QUAL)", "Quality Score", "Count", bins=50)
    snp_hist_dp = create_histogram_figure(snp_dp, "SNP VCF - Read Depth (DP)", "Read Depth", "Count", bins=50)
    snp_hist_dp_log = create_histogram_figure(snp_dp, "SNP VCF - Read Depth (DP) - Log Scale", "Read Depth", "Count (log)", bins=50, log_scale=True)
    snp_hist_gq = create_histogram_figure(snp_gq, "SNP VCF - Genotype Quality (GQ)", "Genotype Quality", "Count", bins=50)
    
    snp_histograms = [snp_hist_qual, snp_hist_dp, snp_hist_dp_log, snp_hist_gq]
    
    # SV histograms
    sv_hist_qual = create_histogram_figure(sv_qual, "SV VCF - Quality (QUAL)", "Quality Score", "Count", bins=50)
    sv_hist_dp = create_histogram_figure(sv_dp, "SV VCF - Total Read Depth (DR+DV)", "Total Read Depth (DR+DV)", "Count", bins=50)
    sv_hist_dp_log = create_histogram_figure(sv_dp, "SV VCF - Total Read Depth (DR+DV) - Log Scale", "Total Read Depth (DR+DV)", "Count (log)", bins=50, log_scale=True)
    sv_hist_gq = create_histogram_figure(sv_gq, "SV VCF - Genotype Quality (GQ)", "Genotype Quality", "Count", bins=50)
    
    sv_histograms = [sv_hist_qual, sv_hist_dp, sv_hist_dp_log, sv_hist_gq]
    
    print("Histograms generated in memory (no PNG files saved)")
    
    # Convert to PDF
    print("\nConverting to PDF...")
    convert_to_pdf(summary_txt, output_pdf, snp_histograms, sv_histograms)
    
    # Clean up summary text file
    if os.path.exists(summary_txt):
        os.unlink(summary_txt)
    
    print("\nPipeline complete!")
    print(f"Output PDF: {output_pdf}")
PYTHON_CODE

log "[INFO] QC analysis complete. Report saved to: $QC_RAW_OUTPUT_DIR/raw_vcf_qc_report.pdf"

############################################
# PART 1: SV & SNV/INDEL ANNOTATION
############################################

log "=========================================="
log "PART 1: ANNOTATION & QC"
log "=========================================="

# Activate environment
source "$CONDA_ROOT/etc/profile.d/conda.sh"
conda activate "$ENV_MAIN"

# Required for Python merge steps
if ! python3 -c "import pandas" 2>/dev/null; then
    log "[INFO] Installing pandas..."
    conda install -y pandas
fi

# VEP is now Docker-based, no PERL5LIB needed
log "[INFO] VEP will run via Docker container"
export BCFTOOLS_PLUGINS="$CONDA_PREFIX/libexec/bcftools"

# Check bcftools plugins
log "[INFO] Checking bcftools plugin availability..."
BCFTOOLS_BIN=$(which bcftools)
if [[ "$BCFTOOLS_BIN" != "$CONDA_PREFIX/bin/bcftools" ]]; then
    log "[ERROR] bcftools is not coming from the conda environment."
    exit 1
fi

if [[ ! -d "$BCFTOOLS_PLUGINS" ]]; then
    log "[ERROR] Plugin directory not found: $BCFTOOLS_PLUGINS"
    exit 1
fi

REQUIRED_PLUGINS=("mendelian" "trio-dnm")
for PLG in "${REQUIRED_PLUGINS[@]}"; do
    if [[ ! -f "$BCFTOOLS_PLUGINS/${PLG}.so" ]]; then
        if [[ -f "$BCFTOOLS_PLUGINS/${PLG}2.so" ]]; then
            ln -s "$BCFTOOLS_PLUGINS/${PLG}2.so" "$BCFTOOLS_PLUGINS/${PLG}.so"
        else
            log "[ERROR] Required bcftools plugin missing: $PLG.so"
            exit 1
        fi
    fi
done

log "[INFO] bcftools plugins OK."

############################################
# STEP 1: SV ANNOTATION
############################################

log "=========================================="
log "STEP 1: SV ANNOTATION"
log "=========================================="

# Ensure pandas is available
if ! python3 -c "import pandas" >/dev/null 2>&1; then
    log "[INFO] Installing pandas into environment..."
    conda install -y pandas
fi

############################################
# RUN AnnotSV (TSV-ONLY MODE)
############################################

SV_UNANNOTATED_TSV="$SV_ANNOTATED_DIR/trio_SV_unannotated.tsv"
SV_MERGED_TSV="$SV_ANNOTATED_DIR/trio_SV_merged.tsv"
SV_ANNOTATED_VCF="$SV_ANNOTATED_DIR/trio_annotated_SV.vcf"
SV_TRIO_FILTERED_VCF="$SV_ANNOTATED_DIR/trio_SV_trio_filtered.vcf"
SV_ANNOT_STATS="$SV_ANNOTATED_DIR/sv_annot.stats.txt"
SV_INTERPRETATION_REPORT="$SV_ANNOTATED_DIR/sv_interpretation_report.txt"

log "[INFO] Running AnnotSV for SV annotation..."

if [[ ! -f "$ANNOTSV_TSV" ]]; then
    log "[INFO] AnnotSV TSV not found, running AnnotSV..."
    "$ANNOTSV/bin/AnnotSV" \
        -SVinputFile "$INPUT_SV_VCF" \
        -genomeBuild GRCh38 \
        -annotationsDir "$ANNOTSV/share/AnnotSV" \
        -outputDir "$SV_ANNOTATED_DIR" \
        -outputFile "$ANNOTSV_TSV" \
        -vcf 0
else
    log "[INFO] AnnotSV TSV already exists, skipping AnnotSV run: $ANNOTSV_TSV"
fi

############################################
# BUILD UNANNOTATED TSV FROM RAW VCF
############################################

log "[INFO] Generating unannotated TSV from raw SV VCF..."
bcftools query -f '%CHROM\t%POS\t%END\t%ID\t%SVTYPE\t%SVLEN\t%QUAL\t%FILTER\n' \
    "$INPUT_SV_VCF" > "$SV_UNANNOTATED_TSV"

############################################
# MERGE ANNOTATED AND UNANNOTATED TSVs
############################################

log "[INFO] Merging annotated and unannotated TSVs..."
python3 << EOF
import pandas as pd

unannot = pd.read_csv(
    "$SV_UNANNOTATED_TSV",
    sep="\t",
    header=None,
    names=["CHROM","POS","END","ID","SVTYPE","SVLEN","QUAL","FILTER"]
)

annot = pd.read_csv(
    "$ANNOTSV_TSV",
    sep="\t",
    comment="#",
    low_memory=False
)

annot = annot[annot['SV_chrom'].notna() & (annot['SV_chrom'] != '')]

if "SV_typeSamples_ID" in annot.columns:
    idx = annot.columns.get_loc("SV_typeSamples_ID")
    annot.insert(idx + 1, "Samples_ID", None)
    annot.rename(columns={"SV_typeSamples_ID": "SV_type"}, inplace=True)

annot = annot.rename(columns={
    "SV_chrom": "SV_CHROM",
    "SV_start": "SV_POS",
    "SV_end": "SV_END"
})

merged = pd.merge(unannot, annot, on=["ID"], how="left", suffixes=("", "_annot"))

cols_to_drop = [
    col for col in merged.columns
    if col.endswith("_annot") and col not in ["SV_CHROM", "SV_POS", "SV_END", "END_annot"]
]
merged = merged.drop(columns=cols_to_drop, errors='ignore')

if "END_annot" in merged.columns:
    merged = merged.drop(columns=["END_annot"])
if "END" not in merged.columns:
    merged["END"] = unannot["END"]

basic_cols = ["CHROM","POS","END","ID","REF","ALT","QUAL","FILTER","INFO","FORMAT"]
other_cols = [c for c in merged.columns if c not in basic_cols]
merged = merged[basic_cols + other_cols]

merged = merged[merged['CHROM'].notna() & (merged['CHROM'] != '')]

merged.to_csv("$SV_MERGED_TSV", sep="\t", index=False)
print(f"[SUCCESS] Merged TSV created with {len(merged)} rows")
EOF

############################################
# PREPARE INFO HEADER LINES FOR VCF
############################################

log "[INFO] Preparing INFO header lines for annotated VCF..."
python3 << EOF
import pandas as pd

df = pd.read_csv("$SV_MERGED_TSV", sep="\t", low_memory=False)

exclude = {
    "CHROM","POS","END","ID","REF","ALT","QUAL","FILTER",
    "FORMAT","AnnotSVtype","$CHILD","$FATHER","$MOTHER"
}

annot_cols = [c for c in df.columns if c not in exclude]

header_file = "$SV_ANNOTATED_DIR/info_headers.txt"
with open(header_file, "w") as h:
    for col in annot_cols:
        h.write(f'##INFO=<ID={col},Number=.,Type=String,Description="AnnotSV field {col}">\\n')
EOF

############################################
# ANNOTATE VCF USING ID-BASED MATCHING
############################################

log "[INFO] Annotating SV VCF with merged TSV annotations..."
python3 << EOF
import pandas as pd
import gzip

df = pd.read_csv("$SV_MERGED_TSV", sep="\t", low_memory=False)

if "Annotation_mode" in df.columns:
    df = df.sort_values("Annotation_mode", ascending=False)
    df = df.drop_duplicates(subset=["ID"], keep="first")

exclude = {
    "CHROM","POS","END","ID","REF","ALT","QUAL","FILTER",
    "FORMAT","AnnotSVtype","$CHILD","$FATHER","$MOTHER"
}
annot_cols = [c for c in df.columns if c not in exclude]

annot_dict = {}
for _, row in df.iterrows():
    info_parts = []
    for col in annot_cols:
        val = row[col]
        if pd.notna(val):
            val = str(val).replace(" ", "_").replace(";", "_").replace("=", "_")
            info_parts.append(f"{col}={val}")
    annot_dict[row["ID"]] = ";".join(info_parts)

# Detect if VCF is gzipped
opener = gzip.open
try:
    with gzip.open("$INPUT_SV_VCF", "rt") as test:
        test.read(1)
except OSError:
    opener = open

with opener("$INPUT_SV_VCF", "rt") as infile:
    lines = infile.readlines()

headers = []
variants = []
for line in lines:
    if line.startswith("#"):
        headers.append(line.rstrip("\\n"))
    else:
        variants.append(line.rstrip("\\n"))

with open("$SV_ANNOTATED_DIR/info_headers.txt", "r") as header_file:
    new_headers = [l.strip() for l in header_file if l.strip()]

# Clean malformed INFO headers
headers_clean = []
for line in headers:
    if line.startswith("##INFO=<") and "##INFO=<" in line[9:]:
        parts = line.split("##INFO=<")
        for i, part in enumerate(parts):
            if i == 0:
                if part.strip():
                    headers_clean.append(part.strip())
            else:
                headers_clean.append("##INFO=<" + part.strip())
    else:
        headers_clean.append(line)

# Insert new INFO headers before #CHROM
chrom_idx = None
for i, line in enumerate(headers_clean):
    if line.startswith("#CHROM"):
        chrom_idx = i
        break

if chrom_idx is not None:
    headers_final = headers_clean[:chrom_idx] + new_headers + headers_clean[chrom_idx:]
else:
    headers_final = headers_clean + new_headers

with open("$SV_ANNOTATED_VCF", "w") as outfile:
    for line in headers_final:
        outfile.write(line + "\\n")
    for line in variants:
        fields = line.split("\\t")
        if len(fields) < 8:
            continue
        chrom = fields[0]
        if not chrom or chrom == ".":
            continue
        var_id = fields[2]
        existing_info = fields[7]
        if var_id in annot_dict and annot_dict[var_id]:
            fields[7] = f"{existing_info};{annot_dict[var_id]}"
        outfile.write("\\t".join(fields) + "\\n")

print(f"[SUCCESS] VCF annotated with {len(annot_dict)} variants")
EOF

############################################
# BASIC STATS AND INTERPRETATION REPORT
############################################

log "[INFO] Running bcftools stats on annotated SV VCF..."
bcftools stats "$SV_ANNOTATED_VCF" > "$SV_ANNOT_STATS"

TOTAL_SV_ANN=$(grep -vc '^#' "$SV_ANNOTATED_VCF" || true)
ACMG_1=$(grep -F "ACMG_class=1" "$SV_ANNOTATED_VCF" | wc -l || echo 0)
ACMG_3=$(grep -F "ACMG_class=3" "$SV_ANNOTATED_VCF" | wc -l || echo 0)
ACMG_FULL_3=$(grep -F "ACMG_class=full_3" "$SV_ANNOTATED_VCF" | wc -l || echo 0)
HM_SV_COUNT=$((ACMG_3 + ACMG_FULL_3))

cat > "$SV_INTERPRETATION_REPORT" <<EOF
TRIO INTERPRETATION REPORT (SV ONLY)

SV:
  Total annotated:               ${TOTAL_SV_ANN}
  Pathogenic/Likely_pathogenic:  ${HM_SV_COUNT}
EOF

log "[SUCCESS] Step 1 (SV Annotation) completed."
log "Output files:"
log "  Annotated SV VCF: $SV_ANNOTATED_VCF"
log "  SV stats:          $SV_ANNOT_STATS"
log "  SV report:         $SV_INTERPRETATION_REPORT"
log ""

############################################
# STEP 2: SNV/INDEL ANNOTATION
############################################

log "=========================================="
log "STEP 2: SNV/INDEL ANNOTATION"
log "=========================================="

# Required for Python merge steps
if ! python3 -c "import pandas" 2>/dev/null; then
    log "[INFO] Installing pandas..."
    conda install -y pandas
fi

# VEP is now Docker-based, no PERL5LIB needed
log "[INFO] VEP will run via Docker container"
export BCFTOOLS_PLUGINS="$CONDA_PREFIX/libexec/bcftools"

log "[INFO] PART 2.1: SNP/INDEL ANNOTATION"
SNP_VCF_ANN="$SNV_ANNOTATED_DIR/trio_SNP_annotated.vcf.gz"
SNP_VCF_FILTERED="$SNV_ANNOTATED_DIR/trio_SNP_trio_filtered.vcf"
SNP_ANNOT_STATS="$SNV_ANNOTATED_DIR/snp_annot.stats.txt"
SNP_INTERPRETATION_REPORT="$SNV_ANNOTATED_DIR/snp_interpretation_report.txt"

# 0. Convert chr* → Ensembl names
CHR_FIXED_VCF="$SNV_ANNOTATED_DIR/input_chr_fixed.vcf.gz"

log "[INFO] Converting UCSC chr* names to Ensembl names..."

bcftools annotate \
  --rename-chrs <(printf "chr1\t1\nchr2\t2\nchr3\t3\nchr4\t4\nchr5\t5\nchr6\t6\nchr7\t7\nchr8\t8\nchr9\t9\nchr10\t10\nchr11\t11\nchr12\t12\nchr13\t13\nchr14\t14\nchr15\t15\nchr16\t16\nchr17\t17\nchr18\t18\nchr19\t19\nchr20\t20\nchr21\t21\nchr22\t22\nchrX\tX\nchrY\tY\nchrM\tMT\n") \
  -O z \
  -o "${CHR_FIXED_VCF}" \
  "${INPUT_SNP_VCF}"

tabix -p vcf "${CHR_FIXED_VCF}"

# 1. Normalize VCF so REF matches GRCh38
NORM_VCF="$SNV_ANNOTATED_DIR/input_normalized.vcf.gz"

log "[INFO] Normalizing VCF against GRCh38 reference..."

# Auto-detect FASTA from Docker cache structure (latest version)
FASTA_BGZ=$(find "$VEP_CACHE_DIR/homo_sapiens" -name "Homo_sapiens.GRCh38.dna.primary_assembly.fa.bgz" | head -n1)

if [ -z "$FASTA_BGZ" ]; then
  log "[ERROR] Could not find VEP FASTA file in $VEP_CACHE_DIR/homo_sapiens"
  exit 1
fi

bcftools norm \
  -f "${FASTA_BGZ}" \
  -m-any \
  -O z \
  -o "${NORM_VCF}" \
  "${CHR_FIXED_VCF}"

tabix -p vcf "${NORM_VCF}"

log "[INFO] Annotating SNPs/INDELs with VEP (Docker)..."
if [ ! -f "${SNP_VCF_ANN}" ]; then
  INPUT_DIR=$(dirname "$INPUT_SNP_VCF")
  INPUT_FILE=$(basename "$INPUT_SNP_VCF")
  OUTPUT_VCF="${SNV_ANNOTATED_DIR}/$(basename "$INPUT_SNP_VCF" .vcf.gz)_annotated.vcf.gz"

  echo "=========================================="
  echo "Running VEP annotation"
  echo "Input : $INPUT_SNP_VCF"
  echo "Output: $OUTPUT_VCF"
  echo "=========================================="

  docker run --rm \
    --user $(id -u):$(id -g) \
    -v $VEP_DATA:/data \
    -v $INPUT_DIR:/input \
    -v $SNV_ANNOTATED_DIR:/output \
    -v $PLUGIN_DATA:/plugins \
    -v $PLUGIN_DATA/../vep:/vep \
    ensemblorg/ensembl-vep:release_115.0 \
    vep \
      --cache \
      --offline \
      --everything \
      --format vcf \
      --vcf \
      --force_overwrite \
      --assembly GRCh38 \
      --dir_cache /data \
      --dir_plugins /plugins \
      --input_file /input/${INPUT_FILE} \
      --output_file /output/$(basename "$OUTPUT_VCF") \
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

  echo "=========================================="
  echo "VEP annotation complete"
  echo "Output written to: $OUTPUT_VCF"
  echo "=========================================="
else
  log "[INFO] VCF already contains VEP annotation. Using existing: ${SNP_VCF_ANN}"
fi

log "[INFO] Running bcftools stats on SNP VCF..."
if bcftools stats "${SNP_VCF_ANN}" > "${SNP_ANNOT_STATS}" 2>&1; then
    log "[INFO] bcftools stats completed successfully"
else
    cat > "${SNP_ANNOT_STATS}" <<EOF
# bcftools stats placeholder
# VCF file: ${SNP_VCF_ANN}
EOF
fi

TOTAL_SNP_ANN=$(bcftools view -H "${SNP_VCF_ANN}" | wc -l || true)
HIGH_COUNT=$(bcftools view -H "${SNP_VCF_ANN}" | grep -c '|HIGH|' || echo "0")
MODERATE_COUNT=$(bcftools view -H "${SNP_VCF_ANN}" | grep -c '|MODERATE|' || echo "0")
HM_SNP_COUNT=$((HIGH_COUNT + MODERATE_COUNT))

cat > "$SNP_INTERPRETATION_REPORT" <<EOF
TRIO INTERPRETATION REPORT (SNP/INDEL ONLY)

SNP/INDEL:
  Total annotated:               ${TOTAL_SNP_ANN}
  HIGH impact:                   ${HIGH_COUNT}
  MODERATE impact:               ${MODERATE_COUNT}
  HIGH/MODERATE impact total:    ${HM_SNP_COUNT}
EOF

# Combined Report
log "[INFO] PART 2.2: COMBINED REPORT"
COMBINED_REPORT="$WORKFLOW_DIR/trio_combined_interpretation_report.txt"

# Get SV counts from previous step
TOTAL_SV_ANN=$(grep -vc '^#' "$SV_VCF" 2>/dev/null || echo 0)
ACMG_1=$(grep "ACMG_class=1" "$SV_VCF" 2>/dev/null | wc -l || echo 0)
ACMG_3=$(grep "ACMG_class=3" "$SV_VCF" 2>/dev/null | wc -l || echo 0)
ACMG_FULL_3=$(grep "ACMG_class=full_3" "$SV_VCF" 2>/dev/null | wc -l || echo 0)
HM_SV_COUNT=$((ACMG_3 + ACMG_FULL_3))

cat > "$COMBINED_REPORT" <<EOF
TRIO COMBINED INTERPRETATION REPORT
====================================

STRUCTURAL VARIANTS (SV):
  Total annotated:               ${TOTAL_SV_ANN}
  Pathogenic/Likely_pathogenic:  ${HM_SV_COUNT}

SNP/INDEL:
  Total annotated:               ${TOTAL_SNP_ANN}
  HIGH/MODERATE impact total:    ${HM_SNP_COUNT}

SUMMARY:
  Total variants (SV + SNP):     $((TOTAL_SV_ANN + TOTAL_SNP_ANN))
  Pathogenic/Likely pathogenic:  $((HM_SV_COUNT + HM_SNP_COUNT))

Generated: $(date)
EOF

# Annotated VCF QC
log "[INFO] PART 2.3: ANNOTATED VCF QC ANALYSIS"
QC_ANNOTATED_OUTPUT_DIR="$ANALYSIS_DIR/QC_annotated_vcfs"
mkdir -p "$QC_ANNOTATED_OUTPUT_DIR"

log "[INFO] Running Python QC analysis on annotated VCF files..."
conda activate "$ENV_MAIN"
python3 - "$SNP_VCF_ANN" "$SV_ANNOTATED_VCF" "$EXOMISER_PED" "$QC_ANNOTATED_OUTPUT_DIR/annotated_vcf_qc_report.txt" << 'PYTHON_CODE'
#!/usr/bin/env python3
"""
Annotated VCF Column Structure Report
Shows what fields are present in annotated VCFs
"""

import gzip
import re
import sys


def parse_vcf_header(vcf_path):
    """Parse VCF header and extract field definitions."""
    info_fields = {}
    format_fields = {}
    filter_fields = {}
    columns = []
    
    # Determine if file is gzipped
    if vcf_path.endswith('.gz'):
        opener = gzip.open
        mode = 'rt'
    else:
        opener = open
        mode = 'r'
    
    with opener(vcf_path, mode) as f:
        for line in f:
            line = line.strip()
            if line.startswith('##INFO='):
                info_match = re.search(r'##INFO=<ID=([^,]+),Number=([^,]+),Type=([^,]+),Description="([^"]+)">', line)
                if info_match:
                    field_id = info_match.group(1)
                    number = info_match.group(2)
                    field_type = info_match.group(3)
                    description = info_match.group(4)
                    info_fields[field_id] = {
                        'Number': number,
                        'Type': field_type,
                        'Description': description
                    }
            elif line.startswith('##FORMAT='):
                format_match = re.search(r'##FORMAT=<ID=([^,]+),Number=([^,]+),Type=([^,]+),Description="([^"]+)">', line)
                if format_match:
                    field_id = format_match.group(1)
                    number = format_match.group(2)
                    field_type = format_match.group(3)
                    description = format_match.group(4)
                    format_fields[field_id] = {
                        'Number': number,
                        'Type': field_type,
                        'Description': description
                    }
            elif line.startswith('##FILTER='):
                filter_match = re.search(r'##FILTER=<ID=([^,]+),Description="([^"]+)">', line)
                if filter_match:
                    field_id = filter_match.group(1)
                    description = filter_match.group(2)
                    filter_fields[field_id] = description
            elif line.startswith('#CHROM'):
                columns = line.split('\t')
                break
    
    return info_fields, format_fields, filter_fields, columns


def main():
    if len(sys.argv) != 4:
        print("Usage: python3 script.py <snp_vcf> <sv_vcf> <ped_file> <output_txt>")
        sys.exit(1)
    
    snp_vcf_path = sys.argv[1]
    sv_vcf_path = sys.argv[2]
    ped_path = sys.argv[3]
    output_txt = sys.argv[4]
    
    # Parse headers
    snp_info, snp_format, snp_filters, snp_columns = parse_vcf_header(snp_vcf_path)
    sv_info, sv_format, sv_filters, sv_columns = parse_vcf_header(sv_vcf_path)
    
    with open(output_txt, 'w', encoding='utf-8') as f:
        f.write("=" * 80 + "\n")
        f.write("ANNOTATED VCF COLUMN STRUCTURE REPORT\n")
        f.write("=" * 80 + "\n\n")
        
        f.write("=" * 80 + "\n")
        f.write("ANNOTATED SNP VCF FILE\n")
        f.write("=" * 80 + "\n")
        f.write(f"File: {snp_vcf_path}\n\n")
        
        f.write("COLUMNS:\n")
        f.write("-" * 80 + "\n")
        for i, col in enumerate(snp_columns, 1):
            f.write(f"  {i}. {col}\n")
        f.write(f"\nTotal columns: {len(snp_columns)}\n\n")
        
        f.write(f"INFO FIELDS ({len(snp_info)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, field_info in sorted(snp_info.items()):
            f.write(f"  {field_id:30s} | Type: {field_info['Type']:8s} | Number: {field_info['Number']:5s}\n")
            f.write(f"  {field_id:30s} | Description: {field_info['Description']}\n\n")
        
        f.write(f"\nFORMAT FIELDS ({len(snp_format)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, field_info in sorted(snp_format.items()):
            f.write(f"  {field_id:30s} | Type: {field_info['Type']:8s} | Number: {field_info['Number']:5s}\n")
            f.write(f"  {field_id:30s} | Description: {field_info['Description']}\n\n")
        
        f.write(f"\nFILTER DEFINITIONS ({len(snp_filters)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, description in sorted(snp_filters.items()):
            f.write(f"  {field_id:30s} | {description}\n")
        
        f.write("\n\n")
        f.write("=" * 80 + "\n")
        f.write("ANNOTATED SV VCF FILE\n")
        f.write("=" * 80 + "\n")
        f.write(f"File: {sv_vcf_path}\n\n")
        
        f.write("COLUMNS:\n")
        f.write("-" * 80 + "\n")
        for i, col in enumerate(sv_columns, 1):
            f.write(f"  {i}. {col}\n")
        f.write(f"\nTotal columns: {len(sv_columns)}\n\n")
        
        f.write(f"INFO FIELDS ({len(sv_info)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, field_info in sorted(sv_info.items()):
            f.write(f"  {field_id:30s} | Type: {field_info['Type']:8s} | Number: {field_info['Number']:5s}\n")
            f.write(f"  {field_id:30s} | Description: {field_info['Description']}\n\n")
        
        f.write(f"\nFORMAT FIELDS ({len(sv_format)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, field_info in sorted(sv_format.items()):
            f.write(f"  {field_id:30s} | Type: {field_info['Type']:8s} | Number: {field_info['Number']:5s}\n")
            f.write(f"  {field_id:30s} | Description: {field_info['Description']}\n\n")
        
        f.write(f"\nFILTER DEFINITIONS ({len(sv_filters)} total):\n")
        f.write("-" * 80 + "\n")
        for field_id, description in sorted(sv_filters.items()):
            f.write(f"  {field_id:30s} | {description}\n")
        
        f.write("\n\n")
        f.write("=" * 80 + "\n")
        f.write("SUMMARY OF ANNOTATIONS ADDED\n")
        f.write("=" * 80 + "\n")
        f.write(f"SNP VCF: {len(snp_info)} INFO fields, {len(snp_format)} FORMAT fields\n")
        f.write(f"SV VCF: {len(sv_info)} INFO fields, {len(sv_format)} FORMAT fields\n")
        f.write("\n")
    
    print(f"Annotated VCF report generated: {output_txt}")


if __name__ == "__main__":
    main()
PYTHON_CODE

log "[INFO] QC analysis complete. Report saved to: $QC_ANNOTATED_OUTPUT_DIR/annotated_vcf_qc_report.txt"

log "[SUCCESS] Step 2 (SNV/Indel Annotation) completed."
log "Output files:"
log "  Annotated SNP VCF: $SNP_VCF_ANN"
log "  SNP stats: $SNP_ANNOT_STATS"
log "  SNP interpretation report: $SNP_INTERPRETATION_REPORT"
log "  Combined interpretation report: $COMBINED_REPORT"
log "  Annotated VCF QC report: $QC_ANNOTATED_OUTPUT_DIR/annotated_vcf_qc_report.txt"
log ""

############################################
# PART 2: VARIANT PRIORITIZATION WITH EXOMISER
############################################

log "=========================================="
log "PART 2: VARIANT PRIORITIZATION"
log "=========================================="

# Merge SNVs + SVs
log ">>> Merging SNVs + SVs"
cd "$WORKFLOW_INTERMEDIATE"
bcftools merge --force-samples -m both -O z ${SNV_VCF} ${SV_VCF} -o merged_raw.vcf.gz
bcftools sort -O z merged_raw.vcf.gz -o merged.vcf.gz
bcftools index merged.vcf.gz

# Filter variants with comprehensive trio-based filtering
log ">>> Filtering variants with trio-based de novo + QC + rarity pipeline"

VCF="merged.vcf.gz"
PED="$EXOMISER_PED"

OUT_LOF="filtered_LoF.vcf.gz"
OUT_NONCODING="filtered_non_coding.vcf.gz"

# Auto-detect family information from PED file
# PED format: FAM_ID IND_ID FATHER_ID MOTHER_ID SEX PHENOTYPE
# SEX: 1=male, 2=female
# PHENOTYPE: 1=unaffected, 2=affected (proband)
FAM_ID=$(awk '$6==2 {print $1}' "$PED" | head -n1)
CHILD=$(awk '$6==2 {print $2}' "$PED" | head -n1)
CHILD_SEX=$(awk -v C="$CHILD" '$2==C {print $6}' "$PED" | head -n1)
FATHER=$(awk -v C="$CHILD" '$2==C {print $3}' "$PED" | head -n1)
MOTHER=$(awk -v C="$CHILD" '$2==C {print $4}' "$PED" | head -n1)

echo "=========================================="
echo "Auto-detected family information from PED:"
echo "  Family ID: $FAM_ID"
echo "  Proband:   $CHILD (Sex: $CHILD_SEX, 1=male, 2=female)"
echo "  Father:    $FATHER"
echo "  Mother:    $MOTHER"
echo "=========================================="

# Use sample names for bcftools filtering (more reliable for trio analysis)

# ============================================================
# SHARED BASE FILTERING PIPELINE (de novo + QC + rarity)
# ============================================================

BASE_FILTER="
  bcftools view -Ou \"$VCF\" |
  bcftools +fill-tags -Ou -- -t AF |
  bcftools +split-vep -Ou -s worst --vep-info-field CSQ |

  # Robust rarity filter (all gnomAD AF fields)
  bcftools filter -Ou -i '
    (INFO/AF < \${AF_THRESHOLD} || INFO/AF==\".\" || INFO/AF==\"\") &&
    (INFO/gnomAD_AF < \${AF_THRESHOLD} || INFO/gnomAD_AF==\".\" || INFO/gnomAD_AF==\"\") &&
    (INFO/gnomADg_AF < \${AF_THRESHOLD} || INFO/gnomADg_AF==\".\" || INFO/gnomADg_AF==\"\") &&
    (INFO/gnomADg_AF_popmax < \${AF_THRESHOLD} || INFO/gnomADg_AF_popmax==\".\" || INFO/gnomADg_AF_popmax==\"\") &&
    (INFO/gnomAD_exomes_AF < \${AF_THRESHOLD} || INFO/gnomAD_exomes_AF==\".\" || INFO/gnomAD_exomes_AF==\"\") &&
    (INFO/gnomAD_genomes_AF < \${AF_THRESHOLD} || INFO/gnomAD_genomes_AF==\".\" || INFO/gnomAD_genomes_AF==\"\")
  ' |

  # Child genotype
  bcftools filter -Ou -i '
    (GT[$CHILD] ~ \"0/1\" || GT[$CHILD] ~ \"1/1\" ||
     GT[$CHILD] ~ \"1|0\" || GT[$CHILD] ~ \"0|1\" ||
     GT[$CHILD] == \"1\")
  ' |

  # Parents must be reference
  bcftools filter -Ou -i 'GT[$MOTHER]==\"0/0\" && GT[$FATHER]==\"0/0\"' |

  # Allelic balance
  bcftools filter -Ou -i \"
    FORMAT/AD[$CHILD][0] + FORMAT/AD[$CHILD][1] > 0 &&
    FORMAT/AD[$CHILD][1] / (FORMAT/AD[$CHILD][0] + FORMAT/AD[$CHILD][1]) >= \${AB_MIN} &&
    FORMAT/AD[$CHILD][1] / (FORMAT/AD[$CHILD][0] + FORMAT/AD[$CHILD][1]) <= \${AB_MAX}
  \" |

  # Parent alt-read suppression
  bcftools filter -Ou -i '
    FORMAT/AD[$MOTHER][1] == 0 &&
    FORMAT/AD[$FATHER][1] == 0
  ' |

  # Genotype quality
  bcftools filter -Ou -i 'FORMAT/DP[$CHILD]>=\${MIN_DP} && FORMAT/GQ[$CHILD]>=\${MIN_GQ}' |
  bcftools filter -Ou -i 'FORMAT/DP[$MOTHER]>=\${MIN_DP} && FORMAT/GQ[$MOTHER]>=\${MIN_GQ}' |
  bcftools filter -Ou -i 'FORMAT/DP[$FATHER]>=\${MIN_DP} && FORMAT/GQ[$FATHER]>=\${MIN_GQ}' |

  # SVTYPE sanity
  bcftools filter -Ou -i '!(INFO/SVTYPE==\"DEL\" && GT[$CHILD]==\"0/0\")' |
  bcftools filter -Ou -i '!(INFO/SVTYPE==\"DUP\" && GT[$CHILD]==\"0/0\")' |
  bcftools filter -Ou -i '!(INFO/SVTYPE==\"INV\" && GT[$CHILD]==\"0/0\")' |
  bcftools filter -Ou -i '!(INFO/SVTYPE==\"INS\" && GT[$CHILD]==\"0/0\")' |

  # X-linked guard (sex-aware)
  # For males (sex=1): prevent child GT=1 when mother has alt allele
  # For females (sex=2): prevent child GT=0/1 or 1/1 when mother has alt allele
  if [ \"$CHILD_SEX\" == \"1\" ]; then
    bcftools filter -Ou -i '!(CHROM==\"X\" && GT[$CHILD]==\"1\" && GT[$MOTHER]!=\"0/0\")'
  else
    bcftools filter -Ou -i '!(CHROM==\"X\" && (GT[$CHILD]~\"0/1\" || GT[$CHILD]~\"1/1\") && GT[$MOTHER]!=\"0/0\")'
  fi
"

# ============================================================
# 1) LoF-only VCF (coding, high-impact)
# ============================================================

eval "$BASE_FILTER" |
  bcftools filter -Ou -i '
    INFO/Consequence ~ \"stop_gained\" ||
    INFO/Consequence ~ \"frameshift_variant\" ||
    INFO/Consequence ~ \"splice_acceptor_variant\" ||
    INFO/Consequence ~ \"splice_donor_variant\" ||
    INFO/Consequence ~ \"start_lost\" ||
    INFO/Consequence ~ \"stop_lost\"
  ' |
  bcftools filter -Ou -i 'INFO/CADD_PHRED>\${CADD_PHRED_THRESHOLD} || INFO/CADD_PHRED==\".\" || INFO/CADD_PHRED==\"\"' |
  bcftools filter -Ou -i 'INFO/REVEL>\${REVEL_THRESHOLD} || INFO/REVEL==\".\" || INFO/REVEL==\"\"' |
  bcftools filter -Ou -i 'INFO/SpliceAI>\${SPLICEAI_THRESHOLD} || INFO/SpliceAI==\".\" || INFO/SpliceAI==\"\"' |
  bcftools filter -Ou -i '
    INFO/ANNOTSV ~ \"pathogenic\" ||
    INFO/ANNOTSV ~ \"likely_pathogenic\" ||
    INFO/ANNOTSV==\".\" || INFO/ANNOTSV==\"\"
  ' |
  bcftools view -Oz -o "$OUT_LOF"

bcftools index "$OUT_LOF"
echo "Generated LoF VCF: $OUT_LOF"

# ============================================================
# 2) Non-coding VCF (regulatory / intronic / intergenic)
# ============================================================

eval "$BASE_FILTER" |
  bcftools filter -Ou -e '
    INFO/Consequence ~ \"stop_gained\" ||
    INFO/Consequence ~ \"frameshift_variant\" ||
    INFO/Consequence ~ \"splice_acceptor_variant\" ||
    INFO/Consequence ~ \"splice_donor_variant\" ||
    INFO/Consequence ~ \"start_lost\" ||
    INFO/Consequence ~ \"stop_lost\"
  ' |
  bcftools view -Oz -o "$OUT_NONCODING"

bcftools index "$OUT_NONCODING"
echo "Generated non-coding VCF: $OUT_NONCODING"

# ============================================================
# Compound-het candidate genes (from LoF VCF)
# ============================================================

echo "Compound-het candidate genes (>=2 hits in LoF VCF):"
bcftools query -f '%INFO/SYMBOL\n' "$OUT_LOF" \
  | awk '$1!="."' \
  | sort | uniq -c | awk '$1>=2'

# Set VCF paths for Exomiser
VCF_LOF="$OUT_LOF"
VCF_NONCODING="$OUT_NONCODING"

log "VCF for LoF analysis: $VCF_LOF"
log "VCF for non-coding analysis: $VCF_NONCODING"

# Normalize SV VCF for Exomiser (used for both runs)
log ">>> Normalizing SV VCF for Exomiser compatibility"
if [ ! -f "${SV_VCF}" ]; then
    echo "Warning: SV VCF not found: ${SV_VCF}"
    echo "Skipping SV normalization step"
    EXOMISER_INPUT_VCF=""
else
    echo "[1/5] Verifying required tools for SV normalization..."
    for tool in bcftools bgzip tabix; do
        if ! command -v "$tool" &>/dev/null; then
            echo "ERROR: $tool is missing for SV normalization."
            exit 1
        fi
    done

    echo "[2/5] Setting up SV normalization paths..."
    SV_TMP1="$WORKFLOW_INTERMEDIATE/sv.norm.vcf"
    SV_TMP2="$WORKFLOW_INTERMEDIATE/sv.symbolic.vcf"
    SV_OUTPUT="$WORKFLOW_INTERMEDIATE/sv.exomiser.vcf"

    echo "[3/5] Decompressing SV VCF..."
    gunzip -c "${SV_VCF}" > sv.raw.vcf

    echo "[4/5] Normalizing SV VCF..."
    bcftools norm -m -any sv.raw.vcf > "$SV_TMP1"

    echo "[5/5] Converting long alleles to symbolic SVs..."
    awk '
    BEGIN { OFS="\t" }
    $0 ~ /^#/ { print; next }
    {
        ref=$4; alt=$5;
        svtype="NA";
        if ($8 ~ /SVTYPE=[^;]+/) {
            match($8, /SVTYPE=([^;]+)/, a);
            svtype=a[1];
        }
        if (length(ref) > 50 || length(alt) > 50) {
            $4="N";
            $5="<" svtype ">";
        }
        print
    }' "$SV_TMP1" > "$SV_TMP2"

    mv "$SV_TMP2" "$SV_OUTPUT"
    bgzip -f "$SV_OUTPUT"
    tabix -f "$SV_OUTPUT.gz"
    rm -f sv.raw.vcf "$SV_TMP1"

    echo ">>> SV normalization complete"
    EXOMISER_INPUT_VCF="${SV_OUTPUT}.gz"
fi

# Function to generate Exomiser YAML and add batch entry
add_exomiser_batch_entry() {
    local VCF_PATH=$1
    local OUTPUT_DIR=$2
    local OUTPUT_NAME=$3

    log ">>> Adding batch entry for ${OUTPUT_NAME}"

    # Generate Exomiser YAML
    local YAML_FILE="$WORKFLOW_DIR/exomiser_config_${OUTPUT_NAME}.yml"

    # Build HPO terms list for YAML
    HPO_LIST=""
    for hpo in "${HPO_TERMS[@]}"; do
        HPO_LIST="$HPO_LIST    - $hpo"$'\n'
    done

    cat > ${YAML_FILE} <<EOF
sample:
  genomeAssembly: hg38
  proband: "${CHILD}"
  hpoIds:
$HPO_LIST

analysis:
  analysisMode: ${EXOMISER_ANALYSIS_MODE}
  vcf: ${VCF_PATH}

  diseaseIds:
    - ${OMIM_DISEASE_ID}
  inheritanceModes: {}
  frequencySources:
    - THOUSAND_GENOMES
    - TOPMED
    - UK10K
    - EXAC
    - GNOMAD
    - GNOMAD_GENOMES
    - GNOMAD_EXOMES
    - GOMAD
    - ESP
  pathogenicitySources:
    - REVEL
    - MVP
    - ALPHA_MISSENSE
    - REMM
  steps:
    - failedVariantFilter: {}
    - priorityScoreFilter:
        priorityType: ${PRIORITY_TYPE}
        minPriorityScore: ${MIN_PRIORITY_SCORE}
    - inheritanceFilter: {}
    - omimPrioritiser: {}
    - hiPhivePrioritiser: {}
  outputOptions:
    outputContributingVariantsOnly: ${EXOMISER_OUTPUT_CONTRIBUTING_ONLY}
    numGenes: 0
    outputFormats:
      - HTML
      - JSON
      - TSV_GENE
      - TSV_VARIANT
      - VCF
EOF

    # Add batch file entry (single line, no backslashes)
    echo "--analysis ${YAML_FILE} --assembly GRCh38 --vcf ${VCF_PATH} --ped ${EXOMISER_PED} --output-directory ${OUTPUT_DIR} --output-filename ${ANALYSIS_NAME}_${OUTPUT_NAME}_exomiser_results" >> "$EXOMISER_BATCH_FILE"
}

# Create batch file
EXOMISER_BATCH_FILE="$WORKFLOW_DIR/exomiser_batch.txt"
> "$EXOMISER_BATCH_FILE"

# Add LoF entry
add_exomiser_batch_entry "$VCF_LOF" "$WORKFLOW_EXOMISER_OUTPUT_LOF" "LoF"

# Add non-coding entry
add_exomiser_batch_entry "$VCF_NONCODING" "$WORKFLOW_EXOMISER_OUTPUT_NONCODING" "non_coding"

# Run Exomiser in batch mode
log ">>> Running Exomiser in batch mode"
cd ${EXOMISER_DIR}
java -Xms100g -Xmx110g \
  -Dexomiser.data-directory=${EXOMISER_DATA} \
  -Dexomiser.hg38.data-version=2512 \
  -Dexomiser.phenotype.data-version=2512 \
  -Dspring.config.location=${EXOMISER_PROPS} \
  -jar ${EXOMISER_JAR} batch "$EXOMISER_BATCH_FILE"

log ">>> DONE — Exomiser batch analysis completed"
log "Results in: ${WORKFLOW_EXOMISER_OUTPUT_LOF} and ${WORKFLOW_EXOMISER_OUTPUT_NONCODING}"

# Function to extract regions from Exomiser output
extract_regions() {
    local OUTPUT_DIR=$1
    local REGIONS_FILE=$2
    local RUN_NAME=$3

    log ">>> Extracting regions from Exomiser output for IGV visualization (${RUN_NAME})"
    EXOMISER_TSV=$(find ${OUTPUT_DIR} -name "*.tsv" -type f | head -n 1)

    if [ -z "$EXOMISER_TSV" ] || [ ! -f "$EXOMISER_TSV" ]; then
        echo "Warning: Exomiser TSV file not found in ${OUTPUT_DIR}"
        echo "Checking for VCF output instead..."
        EXOMISER_VCF=$(find ${OUTPUT_DIR} -name "*.vcf.gz" -type f | head -n 1)
        if [ -z "$EXOMISER_VCF" ] || [ ! -f "$EXOMISER_VCF" ]; then
            echo "Error: No Exomiser output files found. Cannot extract regions."
            exit 1
        fi
        bcftools view -H "$EXOMISER_VCF" | \
          awk -F'\t' '{
            if ($3 != ".") {
              name = $3
            } else {
              name = $1 ":" $2
            }
            start = $2 - 100
            end = $2 + 100
            if (start < 1) start = 1
            print $1 "\t" start "\t" end "\t" name
          }' > "$REGIONS_FILE"
    else
        tail -n +2 "$EXOMISER_TSV" | \
          awk -F'\t' '{
            if (NF >= 3 && $1 != "" && $2 != "" && $3 != "") {
              chrom = $1
              start = $2 - 100
              end = $3 + 100
              if (start < 1) start = 1
              if (NF >= 4 && $4 != "") {
                name = $4
              } else {
                name = chrom ":" start
              }
              print chrom "\t" start "\t" end "\t" name
            }
          }' > "$REGIONS_FILE"
    fi

    REGION_COUNT=$(wc -l < "$REGIONS_FILE")
    echo "Extracted $REGION_COUNT regions from Exomiser output (${RUN_NAME})"
}

# Extract regions from LoF output
extract_regions "$WORKFLOW_EXOMISER_OUTPUT_LOF" "$IGV_REGIONS_FILE_LOF" "LoF"

# Extract regions from non-coding output
extract_regions "$WORKFLOW_EXOMISER_OUTPUT_NONCODING" "$IGV_REGIONS_FILE_NONCODING" "non_coding"

log "[SUCCESS] Part 2 (Variant Prioritization) completed."

############################################
# PART 3: IGV VISUALIZATION
############################################

log "=========================================="
log "PART 3: IGV VISUALIZATION"
log "=========================================="

# Validate BAM files
VALID_BAM_FILES=()
for bam in "${BAM_FILES[@]}"; do
    if [ -n "$bam" ]; then
        VALID_BAM_FILES+=("$bam")
    fi
done

if [ ${#VALID_BAM_FILES[@]} -eq 0 ]; then
    echo "Error: Please add at least one BAM file to the BAM_FILES array"
    exit 1
fi

for bam in "${VALID_BAM_FILES[@]}"; do
    if [ ! -f "$bam" ]; then
        echo "Error: BAM file not found: $bam"
        exit 1
    fi
done

# Check IGV directory
if [ ! -d "$IGV_INSTALLATION_DIR" ]; then
    echo "Error: IGV directory not found at $IGV_INSTALLATION_DIR"
    exit 1
fi

# Function to run IGV snapshots for a given regions file and output directory
run_igv_snapshots() {
    local REGIONS_FILE=$1
    local OUTPUT_DIR=$2
    local RUN_NAME=$3

    log ">>> Generating IGV snapshots for ${RUN_NAME}"

    # Expand regions
    TEMP_DIR=$(mktemp -d)
    EXPANDED_REGIONS_FILE="$TEMP_DIR/expanded_regions.bed"
    REGION_INFO_FILE="$TEMP_DIR/region_info.txt"

    echo "Expanding regions for ${RUN_NAME}..."
    while IFS=$'\t' read -r chrom start end name; do
        if [[ "$chrom" =~ ^# ]] || [[ "$chrom" =~ ^track ]]; then
            continue
        fi
        region_size=$((end - start))
        if [ "$region_size" -lt 1 ]; then region_size=1; fi
        total_window=$((region_size * VIEWPORT_FRACTION))
        padding=$((total_window / 2))
        expanded_start=$((start - padding))
        expanded_end=$((end + padding))
        if [ "$expanded_start" -lt 1 ]; then expanded_start=1; fi
        echo -e "${chrom}\t${expanded_start}\t${expanded_end}\t${name}" >> "$EXPANDED_REGIONS_FILE"
        echo -e "${name}\t${chrom}\t${start}\t${end}" >> "$REGION_INFO_FILE"
    done < "$REGIONS_FILE"

    cd "$IGV_INSTALLATION_DIR"
    CMD="python3 make_IGV_snapshots.py"
    CMD="$CMD -r $EXPANDED_REGIONS_FILE"
    CMD="$CMD -o $OUTPUT_DIR"
    CMD="$CMD -g $IGV_GENOME"
    CMD="$CMD -mem $IGV_MEMORY"
    CMD="$CMD -w $SNAPSHOT_WIDTH -h $SNAPSHOT_HEIGHT"
    CMD+=" ${VALID_BAM_FILES[@]}"
    eval $CMD

    # Rename output files
    echo "Renaming output files for ${RUN_NAME}..."
    while IFS=$'\t' read -r name chrom start end; do
        for snapshot_file in "$OUTPUT_DIR"/*${name}*.png; do
            if [ -f "$snapshot_file" ]; then
                base_name=$(basename "$snapshot_file")
                new_name="${name}_${chrom}_${start}_${end}.png"
                mv "$snapshot_file" "$OUTPUT_DIR/$new_name"
            fi
        done
    done < "$REGION_INFO_FILE"

    rm -rf "$TEMP_DIR"

    log ">>> IGV snapshots completed for ${RUN_NAME}"
    log "Snapshots saved to: $OUTPUT_DIR"
}

# Run IGV snapshots for LoF results
run_igv_snapshots "$IGV_REGIONS_FILE_LOF" "$IGV_OUTPUT_DIR_LOF" "LoF"

# Run IGV snapshots for non-coding results
run_igv_snapshots "$IGV_REGIONS_FILE_NONCODING" "$IGV_OUTPUT_DIR_NONCODING" "non_coding"

log "[SUCCESS] Part 3 (IGV Visualization) completed."

############################################
# FINAL SUMMARY
############################################

log "=========================================="
log "PIPELINE COMPLETE"
log "=========================================="
log "Annotation results:"
log "  SV annotated: $SV_ANNOTATED_DIR"
log "  SNV annotated: $SNV_ANNOTATED_DIR"
log "Exomiser results:"
log "  LoF results: ${WORKFLOW_EXOMISER_OUTPUT_LOF}"
log "  Non-coding results: ${WORKFLOW_EXOMISER_OUTPUT_NONCODING}"
log "IGV snapshots:"
log "  LoF snapshots: ${IGV_OUTPUT_DIR_LOF}"
log "  Non-coding snapshots: ${IGV_OUTPUT_DIR_NONCODING}"
log "=========================================="
ENDOFSCRIPT

chmod +x "$BASE/2_Run_analysis.sh"

echo "Created: $BASE/2_Run_analysis.sh"

echo ""
echo "=============================================="
echo "Analysis scripts generated successfully!"
echo "=============================================="
echo "Next steps:"
echo "  1. Review Workflow_Explained.md in the repository for installation details"
echo "  2. Review $BASE/0_README_Trio_Analysis_Workflow.md for complete workflow documentation"
echo "  3. Edit $BASE/1_Define_data_specs.txt with your configuration"
echo "  4. Run: cd $BASE && ./2_Run_analysis.sh"
echo "=============================================="