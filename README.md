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

## Repository

https://github.com/MolecularBiologyTech/vcf_annotation

## License

See individual tool licenses for specific usage terms.
