#!/bin/bash

# Variants Prioritization Workflow - Installation Wrapper Script
# This script simplifies the installation process by taking the installation path
# as a command-line argument and automatically configuring everything.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print usage information
usage() {
    echo "Usage: $0 <installation_path>"
    echo ""
    echo "This script will:"
    echo "  - Create all necessary directories"
    echo "  - Set the BASE variable automatically"
    echo "  - Run the full installation"
    echo ""
    echo "Example:"
    echo "  $0 /home/user/trio_analysis"
    exit 1
}

# Check if installation path is provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: Installation path not provided${NC}"
    usage
fi

INSTALL_PATH="$1"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find the latest installer version
LATEST_VERSION=$(ls -t "$SCRIPT_DIR/Versions/" | head -n 1)
INSTALLER_PATH="$SCRIPT_DIR/Versions/$LATEST_VERSION/Variants_Prioritization_Workflow_${LATEST_VERSION}.sh"

# Check if installer exists
if [ ! -f "$INSTALLER_PATH" ]; then
    echo -e "${RED}Error: Installer not found at $INSTALLER_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}=============================================="
echo "Variants Prioritization Workflow Installer"
echo "==============================================${NC}"
echo ""
echo "Installation path: $INSTALL_PATH"
echo "Installer version: $LATEST_VERSION"
echo ""

# Check if installation path exists
if [ -d "$INSTALL_PATH" ]; then
    echo -e "${YELLOW}Warning: Directory already exists: $INSTALL_PATH${NC}"
    read -p "Do you want to continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
fi

# Create installation directory
echo -e "${GREEN}Creating installation directory...${NC}"
mkdir -p "$INSTALL_PATH"

# Create a modified version of the installer with the BASE variable set
TEMP_INSTALLER="/tmp/vep_installer_${USER}_$(date +%s).sh"

echo -e "${GREEN}Configuring installer...${NC}"

# Read the original installer and replace the BASE variable
sed "s|^BASE=.*|BASE=\"$INSTALL_PATH\"|" "$INSTALLER_PATH" > "$TEMP_INSTALLER"

# Make the modified installer executable
chmod +x "$TEMP_INSTALLER"

# Run the installer
echo -e "${GREEN}Starting installation...${NC}"
echo -e "${YELLOW}Note: This may take several hours as it downloads large databases.${NC}"
echo ""

sudo bash "$TEMP_INSTALLER"

# Clean up
rm -f "$TEMP_INSTALLER"

echo ""
echo -e "${GREEN}=============================================="
echo "Installation completed successfully!"
echo "==============================================${NC}"
echo ""
echo "Next steps:"
echo "  1. cd $INSTALL_PATH"
echo "  2. Edit 1_Define_data_specs.txt with your data paths and HPO terms"
echo "  3. Run: ./2_Run_analysis.sh"
echo ""
echo "For more information, see README.md in the repository"
echo -e "${GREEN}==============================================${NC}"
