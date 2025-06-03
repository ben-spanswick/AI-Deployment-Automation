#!/bin/bash
# AI Box Cleanup Script
# Removes temporary files and organizes the deployment

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}AI Box Cleanup Script${NC}"
echo "This will clean up temporary files and organize the deployment."
echo

# Function to remove files safely
remove_if_exists() {
    if [[ -f "$1" ]]; then
        rm -f "$1"
        echo -e "${GREEN}✓${NC} Removed: $1"
    fi
}

# Clean up temporary files
echo "Cleaning up temporary files..."
find . -name "*.tmp" -delete 2>/dev/null || true
find . -name "*.backup" -delete 2>/dev/null || true
find . -name "*.log" -mtime +7 -delete 2>/dev/null || true

# Remove Python cache
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true

# Clean Docker
echo
echo "Cleaning Docker resources..."
docker system prune -f --volumes 2>/dev/null || true

# Set proper permissions
echo
echo "Setting proper permissions..."
chmod +x setup.sh
chmod +x scripts/*.sh
chmod 644 config/*.conf 2>/dev/null || true
chmod 644 dashboard.html

# Create necessary directories
echo
echo "Ensuring directory structure..."
mkdir -p logs
mkdir -p config
mkdir -p scripts

# Final summary
echo
echo -e "${GREEN}Cleanup complete!${NC}"
echo
echo "Project structure:"
tree -L 2 -d 2>/dev/null || ls -la

echo
echo -e "${GREEN}AI Box is ready for deployment!${NC}"