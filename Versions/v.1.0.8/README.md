# Variants Prioritization Workflow - Installation and Usage Guide

## Quick Start

### Installation (Recommended Method)

Use the simple installation wrapper script:

```bash
./Variants_Prioritization_Workflow_Installer_wrapper.sh /path/to/installation/directory
```

This will:
- Create all necessary directories
- Set the BASE variable automatically
- Run the full installation
- Install all tools and databases

**Example:**
```bash
./Variants_Prioritization_Workflow_Installer_wrapper.sh /home/user/trio_analysis
```

### Installation (Manual Method)

If you prefer manual installation:

1. Download the latest installer from the `Versions/` directory
2. Edit the `BASE` variable at the top of the script to your desired installation path
3. Run with sudo:
```bash
sudo bash Versions/v.1.0.8/Variants_Prioritization_Workflow_Installer_v.1.0.8.sh
```

---

## 1. Purpose of the Installation

This installation sets up a complete bioinformatics pipeline for **trio-based variant prioritization**. The workflow is designed to:

- **Identify de novo variants** in affected children from trio whole-genome sequencing (WGS) data
- **Annotate both structural variants (SVs) and single nucleotide variants (SNVs)/indels**
- **Filter variants** using stringent quality control and rarity criteria
- **Prioritize variants** using phenotype-driven analysis (Exomiser) with HPO terms
- **Generate visual evidence** through automated IGV snapshots

The pipeline is specifically optimized for rare Mendelian diseases where de novo mutations are a strong genetic signal, particularly in severe early-onset conditions.

---

## 2. Installation and Configuration Overview

The installation script (Variants_Prioritization_Workflow_Installer_v.1.0.8.sh) automatically:

1. **Installs all required tools** (VEP via Docker, AnnotSV, Exomiser, bcftools, samtools, bedtools)
2. **Downloads annotation databases** (CADD, dbNSFP, SpliceAI, REVEL, AlphaMissense, LOFTEE, OpenTargets, gnomAD v4, ClinVar)
3. **Sets up conda environments** (trio-annot-env, multiqc-env)
4. **Configures Docker** for VEP execution
5. **Generates configuration files** (1_Define_data_specs.txt, 2_Run_analysis.sh)

After installation, users only need to:
- Edit 1_Define_data_specs.txt with their data paths and HPO terms
- Run 2_Run_analysis.sh to execute the complete pipeline

---

## 3. Tools Used/Installed and Their Purpose

### Core Bioinformatics Tools

| Tool | Version | Purpose |
|------|---------|---------|
| **VEP** (Variant Effect Predictor) | 115.0 (Docker) | Annotates SNVs/indels with functional consequences, gene names, and pathogenicity scores via Docker container |
| **AnnotSV** | v3.5.10 | Annotates structural variants (SVs) with clinical significance, gene overlap, and population frequency |
| **Exomiser** | 15.0.0 | Phenotype-driven variant prioritization using HPO terms and disease databases |
| **bcftools** | 1.21 | VCF manipulation, filtering, and trio-based de novo detection |
| **samtools** | Latest | BAM/SAM file processing and genome indexing |
| **bedtools** | Latest | Genomic interval operations and region analysis |
| **Docker** | Latest | Containerization platform for VEP execution |

### Annotation Databases

#### VEP Annotation Databases (for SNVs/Indels)

| Database | Purpose |
|----------|---------|
| **ClinVar** | Clinical significance annotations (pathogenic/benign classifications) |
| **CADD** (v1.6) | Combined Annotation Dependent Depletion scores for pathogenicity prediction (downloaded separately for VEP) |
| **dbNSFP** (v5.3.1) | Comprehensive functional annotation database with multiple prediction scores |
| **SpliceAI** | Deep learning-based splice site effect prediction |
| **REVEL** | Rare Exome Variant Ensemble Learner for missense variant pathogenicity |
| **AlphaMissense** | Deep learning-based missense variant pathogenicity prediction |
| **LOFTEE** | Loss-of-function transcript effect estimator for filtering spurious LoF variants |
| **OpenTargets** | Drug target associations and therapeutic insights |
| **gnomAD v4** | Latest population frequency data from large-scale sequencing projects |
| **VEP Cache** (GRCh38) | Pre-computed variant annotations for fast lookup (Docker-based, v115.0) |

#### AnnotSV Annotation Databases (for Structural Variants)

| Database | Purpose |
|----------|---------|
| **ClinVar** | Clinical significance annotations for SVs |
| **CADD** (via AnnotSV) | CADD scores for SV pathogenicity prediction (downloaded automatically during AnnotSV annotation installation) |
| **gnomAD** | Population frequency data for SVs |
| **AnnotSV Annotations** | SV-specific annotations including ACMG classifications, gene overlap, and clinical significance |

### Supporting Tools

| Tool | Purpose |
|------|---------|
| **Miniconda** | Python/R package management and conda environments |
| **MultiQC** | Aggregates quality control metrics from multiple tools |
| **IGV Snapshot Automator** | Automated generation of IGV screenshots for variant visualization |
| **bcftools plugins** (mendelian, trio-dnm) | Specialized plugins for trio analysis |

### Conda Environments

- **trio-annot-env**: Main environment for annotation and filtering (includes bcftools, samtools, bedtools, pandas)
- **multiqc-env**: Environment for quality control reporting

---

## 4. Annotations Added to VCF Files for Variant Prioritization

### SV Annotations (via AnnotSV)

The SV annotation pipeline adds the following fields to the INFO column:

| Annotation | Description | Use in Prioritization |
|------------|-------------|----------------------|
| **ACMG_class** | ACMG classification (1-3, full_3) | Identifies clinically significant SVs |
| **SV_chrom, SV_start, SV_end** | Genomic coordinates | Enables region-based analysis |
| **SVTYPE** | Type of SV (DEL, DUP, INV, INS) | Differentiates variant classes |
| **SVLEN** | Length of SV | Size-based filtering |
| **AnnotSVtype** | Clinical significance (pathogenic, likely_pathogenic) | Direct clinical relevance |
| **Gene** | Overlapping gene symbols | Gene-based prioritization |
| **gnomAD_AF** | Population frequency | Rarity filtering |
| **gnomADg_AF** | gnomAD genome frequency | Population-specific rarity |
| **gnomADg_AF_popmax** | Maximum population frequency | Conservative rarity filtering |

### SNV/Indel Annotations (via VEP Docker)

The VEP pipeline (executed via Docker container) adds comprehensive annotations via the CSQ INFO field using multiple plugins:

| Annotation | Description | Use in Prioritization |
|------------|-------------|----------------------|
| **Consequence** | Variant consequence (e.g., stop_gained, frameshift) | Identifies high-impact variants |
| **SYMBOL** | Gene symbol | Gene-based prioritization |
| **CADD_PHRED** | CADD Phred-scaled score (v1.6) | Pathogenicity prediction (score >20 = top 1%) |
| **REVEL** | Rare Exome Variant Ensemble Learner score | Missense variant pathogenicity (score >0.5 = likely pathogenic) |
| **SpliceAI** | Deep learning splice site prediction | Splice variant assessment (score >0.2 = significant) |
| **AlphaMissense** | Deep learning missense pathogenicity | State-of-the-art missense variant prediction |
| **dbNSFP** | Multiple functional prediction scores | Comprehensive variant annotation |
| **LOFTEE** | Loss-of-function transcript effect | Filters spurious LoF variants |
| **OpenTargets** | Drug target associations | Therapeutic insights |
| **gnomAD v4 AF** | Latest population frequencies (v4) | Updated rarity filtering |
| **CLNSIG, CLNREVSTAT, CLNDN** | ClinVar clinical significance | Known disease associations |
| **gnomAD_AF, gnomADg_AF** | Legacy population frequencies | Cross-reference rarity metrics |

### Combined Annotation Strategy

The workflow uses a **tiered annotation approach**:

1. **Functional impact** (Consequence: stop_gained, frameshift, splice variants)
2. **Pathogenicity scores** (CADD >20, REVEL >0.5, SpliceAI >0.2)
3. **Clinical evidence** (ClinVar pathogenic, ACMG classifications)
4. **Population rarity** (all gnomAD AF fields <0.001)
5. **Gene-level information** (symbol for phenotype matching)

---

## 5. De Novo Variant Identification Using bcftools and Exomiser

### Trio-Based De Novo Detection with bcftools

The pipeline uses a **comprehensive filtering strategy** to identify true de novo variants:

#### Step 1: Genotype Pattern Filtering

```
Child:  0/1 or 1/1 (heterozygous or homozygous alternate)
Father: 0/0 (homozygous reference)
Mother: 0/0 (homozygous reference)
```

This ensures the variant is present in the affected child but absent in both parents.

#### Step 2: Allelic Balance Filtering

```
Child ALT fraction: 0.3 ≤ (ALT_AD / (REF_AD + ALT_AD)) ≤ 0.7
Parents ALT reads: 0 (no alt reads)
```

This prevents:
- False de novo calls from sequencing noise
- Parental mosaicism misclassification
- Mapping artifacts

#### Step 3: Genotype Quality Filtering

```
DP ≥ 10 (depth) for all trio members
GQ ≥ 20 (genotype quality) for all trio members
```

Ensures reliable genotype calls.

#### Step 4: Population Rarity Filtering

```
All gnomAD AF fields < 0.001 OR missing
```

De novo pathogenic variants are typically ultra-rare in population databases.

#### Step 5: SVTYPE Sanity Checks

```
Excludes SVs where child GT = 0/0 for that SVTYPE
```

Prevents spurious SV records where the variant is not actually present in the child.

#### Step 6: X-Linked Guard (Sex-Aware)

The implementation is sex-aware and handles both males and females correctly:

```
For chrX in males (sex=1): if child GT=1, mother must be 0/0
For chrX in females (sex=2): if child GT=0/1 or 1/1, mother must be 0/0
```

**For proband girls:** The allelic balance filtering (0.3-0.7 range) works correctly on chrX because females have two X chromosomes and can be heterozygous (0/1) or homozygous alternate (1/1), just like on autosomes. The X-linked guard prevents misclassification of inherited maternal X-linked variants as de novo by ensuring the mother is homozygous reference (0/0) when the child has an alternate allele on chrX.

Prevents misclassification of inherited maternal X-linked variants as de novo for both sexes.

### Variant Classification

After filtering, variants are split into two categories:

#### LoF (Loss of Function) VCF - Coding Variants

**Additional filters applied:**
- Consequence: stop_gained, frameshift, splice_acceptor, splice_donor, start_lost, stop_lost
- CADD_PHRED > 20 OR missing
- REVEL > 0.5 OR missing
- SpliceAI > 0.2 OR missing
- ANNOTSV contains "pathogenic" OR "likely_pathogenic" OR missing

These filters ensure only high-impact protein-truncating variants with strong pathogenicity evidence are prioritized.

#### Non-Coding VCF - Regulatory/Intergenic Variants

**Excludes** all high-impact coding consequences, focusing on:
- Regulatory elements
- Intronic regions
- Intergenic regions

### Exomiser Prioritization

After bcftools filtering, Exomiser adds phenotype-driven prioritization:

#### Input to Exomiser

- **Filtered VCFs** (LoF and non-coding)
- **PED file** with trio structure
- **HPO terms** describing patient phenotype
- **OMIM disease ID** for known disease associations

#### Exomiser Analysis Steps

1. **Failed Variant Filter** - Removes variants that fail basic quality checks
2. **Priority Score Filter** - Applies minimum priority score threshold (default: 0.501)
3. **Inheritance Filter** - Enforces de novo inheritance pattern
4. **OMIM Prioritiser** - Matches variants to known OMIM diseases
5. **hiPhive Prioritiser** - Uses phenotype similarity via HPO terms

#### Exomiser Output

Exomiser produces ranked lists of candidate variants with:
- **Gene-level scores** - How well the gene matches the phenotype
- **Variant-level scores** - Combined evidence from inheritance, frequency, and pathogenicity
- **HTML reports** - Interactive visualization of results
- **TSV files** - Tabular data for downstream analysis
- **VCF files** - Annotated VCF with Exomiser scores

### Compound-Heterozygous Detection

The pipeline also identifies **compound-heterozygous candidates** by counting genes with ≥2 hits in the LoF VCF. This helps identify cases where two different damaging alleles in the same gene (one from each parent) cause disease.

---

## 6. Visualization via IGV Snapshot Automator

After variant prioritization, the pipeline generates automated IGV snapshots for visual validation of candidate variants.

### IGV Snapshot Process

The IGV Snapshot Automator creates PNG images of genomic regions around prioritized variants:

#### Input to IGV Snapshot

- **BAM files** for proband, father, and mother
- **Variant regions** (chromosome, start, end positions) from Exomiser results
- **Reference genome** for proper alignment visualization

#### IGV Snapshot Generation Steps

1. **Region Extraction** - Extracts genomic coordinates from Exomiser output files
2. **IGV Loading** - Loads BAM files and reference genome in headless mode (using xvfb)
3. **Snapshot Capture** - Captures PNG images at specified genomic regions
4. **Organized Output** - Saves snapshots in LoF and non-coding subdirectories

#### IGV Snapshot Output

The IGV snapshot process produces:
- **PNG images** of variant regions showing read alignments for all trio members
- **LoF snapshots** - Images for loss-of-function variant regions
- **Non-coding snapshots** - Images for regulatory/intergenic variant regions
- **Visual evidence** - Enables manual inspection of variant calls and alignment quality

#### Purpose of IGV Visualization

IGV snapshots provide:
- **Read-level validation** - Verify that variant calls are supported by sequencing data
- **Allelic balance confirmation** - Visual check of heterozygous/homozygous status
- **Mapping quality assessment** - Identify potential mapping artifacts
- **Manual review** - Enable expert review of borderline cases
- **Clinical reporting** - Provide visual evidence for clinical interpretation

---

## Summary

The workflow integrates:

1. **Comprehensive annotation** (VEP + AnnotSV) for both SVs and SNVs
2. **Stringent trio-based filtering** using bcftools to identify true de novo variants
3. **Phenotype-driven prioritization** using Exomiser with HPO terms
4. **Quality control** through MultiQC reports
5. **Visual validation** through automated IGV snapshots

This multi-layered approach ensures that only high-confidence, clinically relevant variants are prioritized for further investigation, reducing false positives and increasing diagnostic yield for rare Mendelian diseases.
