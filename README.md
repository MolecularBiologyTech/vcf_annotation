# Trio-Based De Novo Variant Detection and Prioritization Workflow

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
```
CSQ=Consequence|SYMBOL|CADD_PHRED|REVEL|SpliceAI|AlphaMissense|CLNSIG|CLNREVSTAT|...
```

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
```
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
```

---

## Installation

Run the installation script on a Linux server:

```bash
cd "Versions/v1.0.0"
bash Variants_Prioritization_Workflow_Installer_v1.0.0.sh
```

The script automatically:
- Installs Docker
- Downloads VEP Docker container
- Downloads and indexes annotation databases
- Configures plugin directories

## Requirements

- Linux server with sudo access
- Docker
- Internet connection for downloading databases

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

## Repository

https://github.com/MolecularBiologyTech/vcf_annotation

## License

See individual tool licenses for specific usage terms.

---

**Version**: 1.0  
**Last Updated**: 2026-06-21  
**Genome Assembly**: GRCh38  
**Analysis Type**: Trio-based de novo variant detection and prioritization
