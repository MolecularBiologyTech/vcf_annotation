#!/bin/bash
set -e

############################################
# BASE DIRECTORIES
############################################
BASE="/mnt/raid0/home/p2solo/Matteo_scripts/scripts/VARIANT_PRIORITIZATION_ANALYSIS"

DOCKER_DATA="$BASE/docker-data"
VEP_DATA="$BASE/vep_data"
PLUGIN_DATA="$DOCKER_DATA/plugins"

BASESPACE_DIR="$BASE/BaseSpaceCLI"
BASESPACE_BIN="$BASESPACE_DIR/bs"

mkdir -p "$BASE" "$DOCKER_DATA" "$VEP_DATA" "$PLUGIN_DATA" "$BASESPACE_DIR"
mkdir -p "$PLUGIN_DATA"/{dbnsfp,spliceai,loftee,gnomad,curated_lof}

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
    "$BASESPACE_BIN" auth
fi

############################################
# DOCKER + REQUIRED TOOLS
############################################
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

############################################
# PERMISSIONS
############################################
sudo chown -R "$USER":"$USER" "$DOCKER_DATA" "$VEP_DATA" "$PLUGIN_DATA"
sudo chmod -R a+rwx "$DOCKER_DATA" "$VEP_DATA" "$PLUGIN_DATA"

############################################
# VEP 115 INSTALL (CACHE INTO VEP_DATA)
############################################
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

############################################
# SPLICEAI DOWNLOAD (BaseSpace → PLUGIN_DATA/spliceai)
############################################
OUTDIR="$PLUGIN_DATA/spliceai"
mkdir -p "$OUTDIR"

FILES=(16534036123 16534036125 16534036127 16534036128)

for ID in "${FILES[@]}"; do
    "$BASESPACE_BIN" download file --id "$ID" --output "$OUTDIR"
done

############################################
# LOFTEE (GRCh38 DATA → PLUGIN_DATA/loftee)
############################################
mkdir -p "$PLUGIN_DATA/loftee"
cd "$PLUGIN_DATA/loftee"

wget -c "https://s3.amazonaws.com/bcbio_nextgen/human_ancestor.fa.gz"
wget -c "https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/gerp_conservation_scores.homo_sapiens.GRCh38.bw"
wget -c "https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/loftee.sql.gz"

############################################
# REQUIRED LoFTEE PLUGIN FILES (GRCh38 → /plugins)
############################################
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

############################################
# MOVE LoFTEE FILES INTO CORRECT DIRECTORY
############################################
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

############################################
# INSTALL MaxEntScan (→ /plugins/maxEntScan)
############################################
echo "[LoFTEE] Installing MaxEntScan splice-site scoring scripts..."

MAXENT_DIR="$PLUGIN_DATA/maxEntScan"
mkdir -p "$MAXENT_DIR"
cd "$MAXENT_DIR"

curl -L "https://raw.githubusercontent.com/konradjk/loftee/master/maxEntScan/score3.pl" -o score3.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/master/maxEntScan/score5.pl" -o score5.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/master/maxEntScan/maxentscan_score3.pl" -o maxentscan_score3.pl
curl -L "https://raw.githubusercontent.com/konradjk/loftee/master/maxEntScan/maxentscan_score5.pl" -o maxentscan_score5.pl

chmod +x *.pl

############################################
# INSTALL LoFTEE splice_data
############################################
echo "[LoFTEE] Installing splice_data..."

SPLICE_DATA_DIR="$PLUGIN_DATA/loftee/splice_data"
mkdir -p "$SPLICE_DATA_DIR/donor_motifs" "$SPLICE_DATA_DIR/acceptor_motifs" "$SPLICE_DATA_DIR/pwm"

curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_data/donor_motifs/ese.txt" -o "$SPLICE_DATA_DIR/donor_motifs/ese.txt"
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_data/donor_motifs/ess.txt" -o "$SPLICE_DATA_DIR/donor_motifs/ess.txt"

curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_data/acceptor_motifs/ese.txt" -o "$SPLICE_DATA_DIR/acceptor_motifs/ese.txt"
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_data/acceptor_motifs/ess.txt" -o "$SPLICE_DATA_DIR/acceptor_motifs/ess.txt"

curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_data/pwm/donor_pwm.txt" -o "$SPLICE_DATA_DIR/pwm/donor_pwm.txt"
curl -L "https://raw.githubusercontent.com/konradjk/loftee/grch38/splice_data/pwm/acceptor_pwm.txt" -o "$SPLICE_DATA_DIR/pwm/acceptor_pwm.txt"

############################################
# dbNSFP 5.3.1a + index
############################################
cd "$PLUGIN_DATA/dbnsfp"

wget -c "https://dist.genos.us/academic/e55b09/dbNSFP5.3.1a_grch38.gz"

DBNSFP_FILE="$PLUGIN_DATA/dbnsfp/dbNSFP5.3.1a_grch38.gz"

if [ -s "$DBNSFP_FILE" ]; then
    tabix -f -s 1 -b 2 -e 2 "$DBNSFP_FILE"
fi

############################################
# VEP PLUGIN .pm FILES
############################################
cd "$PLUGIN_DATA"

wget -q -O LoFtool.pm https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/LoFtool.pm
wget -q -O LoFtool_scores.txt https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/LoFtool_scores.txt
wget -q -O SpliceAI.pm https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/SpliceAI.pm
wget -q -O dbNSFP.pm https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/dbNSFP.pm
wget -q -O dbNSFP_replacement_logic https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/dbNSFP_replacement_logic
wget -q -O gnomADc.pm https://raw.githubusercontent.com/Ensembl/VEP_plugins/release/115/gnomADc.pm

chmod a+r LoFtool.pm LoFtool_scores.txt SpliceAI.pm dbNSFP.pm dbNSFP_replacement_logic gnomADc.pm

############################################
# gnomAD GENOMES v4.1.1
############################################
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

############################################
# gnomAD curated LoF — FIXED SORTING + INDEXING
############################################
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

############################################
# FIX 1 — LoFTEE helper scripts must exist in /plugins
############################################
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

############################################
# FIX 2 — LoFTEE splice_data must exist at /vep/loftee/splice_data
############################################
echo "[LoFTEE] Copying splice_data to /vep/loftee..."
mkdir -p "$PLUGIN_DATA/../vep/loftee"
cp -r "$PLUGIN_DATA/loftee/splice_data" "$PLUGIN_DATA/../vep/loftee/"

############################################
# FIX 3 — Merge gnomAD genomes into a single file
############################################
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

############################################
# FIX 4 — dbNSFP README required
############################################
echo "[dbNSFP] Creating README..."
if [ ! -f "$PLUGIN_DATA/dbnsfp/README.txt" ]; then
    echo "dbNSFP 5.3.1a dataset" > "$PLUGIN_DATA/dbnsfp/README.txt"
fi

echo "=========================================="
echo "INSTALLER COMPLETE"
echo "VEP cache:      $VEP_DATA"
echo "Plugins root:   $PLUGIN_DATA  (mounted as /plugins)"
echo "Docker data:    $DOCKER_DATA"
echo "=========================================="

