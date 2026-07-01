#!/bin/bash
set -e

# Configuration
REPO_DIR="/Users/matteozoia/Documents/Lavoro/GitHub/vcf_annotation"
VERSIONS_DIR="$REPO_DIR/Versions"
PROJECT_NAME="Variants_AnnotationPrioritization"

# Get current version (find latest version)
CURRENT_VERSION=$(ls -1 "$VERSIONS_DIR" | sort -V | tail -n 1)

if [ -z "$CURRENT_VERSION" ]; then
    echo "Error: No versions found in $VERSIONS_DIR"
    exit 1
fi

echo "Current version: $CURRENT_VERSION"

# Parse version numbers (format: Variants_AnnotationPrioritization_v.1.0.0)
MAJOR=$(echo $CURRENT_VERSION | cut -d. -f2 | cut -d_ -f2)
MINOR=$(echo $CURRENT_VERSION | cut -d. -f3)
PATCH=$(echo $CURRENT_VERSION | cut -d. -f4)

# Increment patch version
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="${PROJECT_NAME}_v.${MAJOR}.${MINOR}.${NEW_PATCH}"

echo "New version: $NEW_VERSION"

# Source file path (the modified latest version)
SOURCE_FILE="$VERSIONS_DIR/$CURRENT_VERSION/Variants_Prioritization_Workflow_Installer_${CURRENT_VERSION}.sh"

# Check if source file exists
if [ ! -f "$SOURCE_FILE" ]; then
    echo "Error: Source file not found: $SOURCE_FILE"
    exit 1
fi

# Create new version directory
NEW_DIR="$VERSIONS_DIR/$NEW_VERSION"
mkdir -p "$NEW_DIR"

# Copy the MODIFIED file with new name
DEST_FILE="$NEW_DIR/Variants_Prioritization_Workflow_Installer_${NEW_VERSION}.sh"
cp "$SOURCE_FILE" "$DEST_FILE"
chmod +x "$DEST_FILE"

echo "Copied modified file to: $DEST_FILE"

# Copy README.md to new version directory
if [ -f "$REPO_DIR/README.md" ]; then
    cp "$REPO_DIR/README.md" "$NEW_DIR/README.md"
    echo "Copied README.md to: $NEW_DIR/README.md"
fi

# Generate commit message by comparing the two versions (BEFORE restoring)
echo ""
echo "Comparing $CURRENT_VERSION to $NEW_VERSION..."
echo ""

# Use git show to get the original version from git, then compare
git show HEAD:"Versions/$CURRENT_VERSION/Variants_Prioritization_Workflow_Installer_${CURRENT_VERSION}.sh" > /tmp/original_${CURRENT_VERSION}.sh
DIFF_OUTPUT=$(diff -u /tmp/original_${CURRENT_VERSION}.sh "$DEST_FILE" || true)
rm /tmp/original_${CURRENT_VERSION}.sh

if [ -z "$DIFF_OUTPUT" ]; then
    echo "Warning: No differences detected between versions"
    COMMIT_MESSAGE="Version $NEW_VERSION: No changes detected"
else
    # Create a summary of changes
    echo "Changes detected:"
    echo "$DIFF_OUTPUT"
    echo ""

    # Analyze changes to generate descriptive commit message
    CHANGE_SUMMARY=""
    
    # Check for BASE variable in 1_Define_data_specs.txt
    if echo "$DIFF_OUTPUT" | grep -q 'BASE="\$BASE"'; then
        CHANGE_SUMMARY="- Added BASE variable to 1_Define_data_specs.txt"
    fi
    
    # Check for auto-detect BASE removal
    if echo "$DIFF_OUTPUT" | grep -q "AUTO-DETECT BASE FROM INSTALLATION"; then
        CHANGE_SUMMARY="$CHANGE_SUMMARY
- Removed BASE auto-detection in 2_Run_analysis.sh"
    fi
    
    # Check for README copy
    if echo "$DIFF_OUTPUT" | grep -q "Copy README to BASE directory"; then
        CHANGE_SUMMARY="$CHANGE_SUMMARY
- Added README copy to BASE directory during installation"
    fi
    
    # Check for VEP version changes
    if echo "$DIFF_OUTPUT" | grep -q "release_115"; then
        CHANGE_SUMMARY="$CHANGE_SUMMARY
- Updated VEP to version 115"
    fi
    
    # Check for plugin changes
    if echo "$DIFF_OUTPUT" | grep -q "dbNSFP5.3.1a"; then
        CHANGE_SUMMARY="$CHANGE_SUMMARY
- Updated dbNSFP to 5.3.1a"
    fi
    
    # Check for gnomAD changes
    if echo "$DIFF_OUTPUT" | grep -q "gnomad.genomes.v4.1.1"; then
        CHANGE_SUMMARY="$CHANGE_SUMMARY
- Updated gnomAD to v4.1.1"
    fi

    # If no specific changes detected, use generic message
    if [ -z "$CHANGE_SUMMARY" ]; then
        COMMIT_MESSAGE="Version $NEW_VERSION: Updated installer from $CURRENT_VERSION"
    else
        COMMIT_MESSAGE="Version $NEW_VERSION: Updated installer from $CURRENT_VERSION
$CHANGE_SUMMARY"
    fi
fi

# Change to repository directory
cd "$REPO_DIR"

# Stage the new version
git add "$NEW_DIR"

# Commit changes

# Show the diff and ask if user wants to amend commit message
echo ""
echo "=========================================="
echo "Commit created with message:"
echo "$COMMIT_MESSAGE"
echo "=========================================="
echo ""
echo "Do you want to amend the commit message? (y/n)"
read -r AMEND_RESPONSE

if [[ "$AMEND_RESPONSE" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Please enter new commit message (press Ctrl+D when done):"
    NEW_MESSAGE=$(cat)
    
    if [ -n "$NEW_MESSAGE" ]; then
        git commit --amend -m "$NEW_MESSAGE"
        COMMIT_MESSAGE="$NEW_MESSAGE"
        echo "Commit message amended."
    else
        echo "No changes made to commit message."
    fi
fi
git commit -m "$COMMIT_MESSAGE"

# Create git tag
git tag -a "$NEW_VERSION" -m "$COMMIT_MESSAGE"

# Restore the original version to its unmodified state from git
echo ""
echo "Restoring $CURRENT_VERSION to its original state..."
git checkout HEAD -- "$VERSIONS_DIR/$CURRENT_VERSION/"

# Push to GitHub
git push
git push origin "$NEW_VERSION"

echo ""
echo "=========================================="
echo "Successfully created and pushed version $NEW_VERSION"
echo "Original version $CURRENT_VERSION has been restored to its unmodified state"
echo "=========================================="
