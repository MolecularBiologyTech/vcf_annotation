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

# Increment minor version for significant changes
NEW_MINOR=$((MINOR + 1))
NEW_VERSION="${PROJECT_NAME}_v.${MAJOR}.${NEW_MINOR}.0"

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
    
    # Generate a commit message with the detailed diff
    COMMIT_MESSAGE="Version $NEW_VERSION: Changes from $CURRENT_VERSION

$(echo "$DIFF_OUTPUT")"
fi

# Change to repository directory
cd "$REPO_DIR"

# Stage the new version
git add "$NEW_DIR"

# Commit changes
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
