# VCF Annotation Pipeline

Comprehensive bioinformatics pipeline for **trio-based variant prioritization** in rare Mendelian diseases.

## Overview

This workflow is designed for:
- **Identify de novo variants** in affected children from trio whole-genome sequencing (WGS) data
- **Annotate both structural variants (SVs) and single nucleotide variants (SNVs)/indels**
- **Filter variants** using stringent quality control and rarity criteria
- **Prioritize variants** using phenotype-driven analysis (Exomiser) with HPO terms
- **Generate visual evidence** through automated IGV snapshots

## Installation

Run the installation script on a Linux server:

```bash
cd "/Users/matteozoia/Documents/Lavoro/HES-SO/Projects/Project 1 - TRIOs/10. LAST - Missing Last VEP version only/3. Main Script"
bash Variants_Prioritization_Workflow_Installer_21.06.2026.sh
```

The script automatically:
- Installs all required tools (VEP via Docker, AnnotSV, Exomiser, bcftools, samtools, bedtools)
- Downloads annotation databases (CADD, dbNSFP, SpliceAI, REVEL, AlphaMissense, LOFTEE, OpenTargets, gnomAD v4, ClinVar)
- Sets up conda environments
- Generates analysis scripts

## Usage

After installation:

1. Edit `1_Define_data_specs.txt` with your data paths and HPO terms
2. Run the analysis:
```bash
./2_Run_analysis.sh
```

## Tools Included

- **VEP** (Variant Effect Predictor) - Annotates SNVs/indels with functional consequences
- **AnnotSV** - Annotates structural variants with clinical significance
- **Exomiser** - Phenotype-driven variant prioritization using HPO terms
- **bcftools** - VCF manipulation and trio-based de novo detection
- **samtools/bedtools** - BAM/SAM file processing and genomic interval operations
- **IGV Snapshot Automator** - Automated generation of IGV screenshots

## Workflow

The pipeline performs:
1. **SV Annotation** via AnnotSV
2. **SNV/Indel Annotation** via VEP (Docker-based)
3. **Variant Filtering** - Trio-based de novo detection with quality control
4. **Phenotype Prioritization** - Exomiser with HPO terms
5. **Visualization** - Automated IGV snapshots for top candidates

## Version Control

This repository uses git for version control. Each commit is automatically saved as a new version. Use the `git_commit_versioned.sh` script to commit changes with automatic version tagging.

```bash
./git_commit_versioned.sh "Your commit message"
```

## Repository

https://github.com/MolecularBiologyTech/vcf_annotation

## License

See individual tool licenses for specific usage terms.
