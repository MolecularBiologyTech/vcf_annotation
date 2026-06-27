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
cd "11. VEP re-do last script that worked of deleted on p2solo"
bash install_VEP_and_plugins_13.06.2026.sh
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

`11. VEP re-do last script that worked of deleted on p2solo/install_VEP_and_plugins_13.06.2026.sh`

## Version Control

This repository uses git for version control. Each commit is automatically saved as a new version.

```bash
git add .
git commit -m "Your commit message"
git push
```

## Repository

https://github.com/MolecularBiologyTech/vcf_annotation

## License

See individual tool licenses for specific usage terms.
