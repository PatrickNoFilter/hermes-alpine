#!/bin/bash
# Quick script to render an HTML file to MP4 using html-video CLI
# Usage: ./render-html-video.sh <project-name> <template-id> <html-file>

set -e
cd /root/html-video

PROJECT_NAME="$1"
TEMPLATE_ID="$2"
HTML_FILE="$3"

# Create project
PROJECT_ID=$(node packages/cli/dist/bin.js project-create --name "$PROJECT_NAME" | jq -r '.project_id')
echo "Created project: $PROJECT_ID"

# Set template
node packages/cli/dist/bin.js project-set-template "$PROJECT_ID" --template "$TEMPLATE_ID"
echo "Set template: $TEMPLATE_ID"

# Add HTML asset
node packages/cli/dist/bin.js project-add-asset "$PROJECT_ID" --file "$HTML_FILE"
echo "Added asset: $HTML_FILE"

# Render
node packages/cli/dist/bin.js project-render "$PROJECT_ID"
echo "Render complete!"