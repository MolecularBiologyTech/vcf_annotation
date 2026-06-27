# VEP Installation Script

Installation script for VEP (Variant Effect Predictor) with plugins for variant annotation in bioinformatics pipelines.

## Overview

This script installs VEP and essential annotation plugins:
- **VEP** (Variant Effect Predictor) - Annotates SNVs/indels with functional consequences
- **SpliceAI** - Deep learning-based splice site effect prediction
- **dbNSFP** - Comprehensive functional annotation database
- **LOFTEE** - Loss-of-function transcript effect estimator
- **OpenTargets** - Drug target associations

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

## Script Location

`Versions/v1.0.0/Variants_Prioritization_Workflow_Installer_v1.0.0.sh`

## Version Control

This repository uses git for version control with structured version folders.

**To create a new version:**

1. Modify the installer script in the latest version folder (e.g., `Versions/v1.0.0/Variants_Prioritization_Workflow_Installer_v1.0.0.sh`)
2. Run the version update script:
```bash
./update_version.sh
```

This script will:
- Automatically increment the version number (e.g., v1.0.0 → v1.0.1)
- Copy your modified script to the new version folder
- Compare the old and new versions using git diff
- Auto-generate a detailed commit message with the full diff
- Restore the original version to its unmodified state
- Commit, tag, and push to GitHub

The original version remains unmodified both locally and on GitHub, while your changes are preserved in the new version.

**Manual version control:**
```bash
git add .
git commit -m "Your commit message"
git push
```

## Repository

https://github.com/MolecularBiologyTech/vcf_annotation

## License

See individual tool licenses for specific usage terms.
