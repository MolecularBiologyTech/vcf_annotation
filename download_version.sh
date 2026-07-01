#!/bin/bash
set -e

# Variants Annotation Prioritization Version Downloader
# This script allows you to download a specific version of the workflow

REPO_URL="https://github.com/MolecularBiologyTech/vcf_annotation"
REPO_NAME="Variants_AnnotationPrioritization"

echo "=========================================="
echo "Variants Annotation Prioritization Version Downloader"
echo "=========================================="
echo ""

# Fetch all available tags from GitHub
echo "Fetching available versions from GitHub..."
TAGS=$(git ls-remote --tags "$REPO_URL.git" | awk -F'/' '{print $3}' | sort -V | tail -20)

if [ -z "$TAGS" ]; then
    echo "Error: No versions found on GitHub"
    exit 1
fi

echo ""
echo "Available versions:"
echo "$TAGS" | nl -w2 -s'. '
echo ""

# Ask user to select a version
echo "Enter the number of the version you want to download (or press Enter for latest):"
read -r SELECTION

if [ -z "$SELECTION" ]; then
    # Download latest version
    SELECTED_TAG=$(echo "$TAGS" | tail -n1)
    echo "Downloading latest version: $SELECTED_TAG"
else
    # Download selected version
    SELECTED_TAG=$(echo "$TAGS" | sed -n "${SELECTION}p")
    if [ -z "$SELECTED_TAG" ]; then
        echo "Error: Invalid selection"
        exit 1
    fi
    echo "Downloading version: $SELECTED_TAG"
fi

# Create download directory
DOWNLOAD_DIR="${REPO_NAME}_${SELECTED_TAG}"
echo ""
echo "Creating download directory: $DOWNLOAD_DIR"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

# Download the specific version
echo ""
echo "Downloading from GitHub..."
git clone --depth 1 --branch "$SELECTED_TAG" "$REPO_URL.git" temp_repo

# Extract the version-specific installer
INSTALLER_FILE="temp_repo/Versions/$SELECTED_TAG/Variants_Prioritization_Workflow_Installer_${SELECTED_TAG}.sh"

if [ ! -f "$INSTALLER_FILE" ]; then
    echo "Error: Installer file not found for version $SELECTED_TAG"
    echo "Looking for: $INSTALLER_FILE"
    exit 1
fi

# Copy the installer to the download directory
cp "$INSTALLER_FILE" "./Variants_Prioritization_Workflow_Installer_${SELECTED_TAG}.sh"
chmod +x "./Variants_Prioritization_Workflow_Installer_${SELECTED_TAG}.sh"

# Copy README if available
if [ -f "temp_repo/README.md" ]; then
    cp "temp_repo/README.md" "./README.md"
fi

# Clean up
rm -rf temp_repo

echo ""
echo "=========================================="
echo "Download complete!"
echo "=========================================="
echo "Downloaded: Variants_Prioritization_Workflow_Installer_${SELECTED_TAG}.sh"
echo "Location: $(pwd)"
echo ""
echo "To install, edit the BASE variable in the installer and run:"
echo "  sudo bash Variants_Prioritization_Workflow_Installer_${SELECTED_TAG}.sh"
echo "=========================================="
