#!/bin/bash
# Deploy Portainer for Docker management

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Deploying Portainer CE${NC}"
echo

# Check if Portainer is already running
if docker ps | grep -q portainer; then
    echo -e "${YELLOW}Portainer is already running!${NC}"
    echo "Access it at: http://localhost:9000"
    exit 0
fi

# Create volume for Portainer data
docker volume create portainer_data

# Deploy Portainer
docker run -d \
  -p 9000:9000 \
  --name portainer \
  --restart=unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  --network ai-network \
  portainer/portainer-ce:latest

echo
echo -e "${GREEN}✓ Portainer deployed successfully!${NC}"
echo
echo "Access Portainer at: http://localhost:9000"
echo
echo "First time setup:"
echo "1. Create an admin user"
echo "2. Choose 'Docker - Manage the local Docker environment'"
echo "3. Click Connect"
echo
echo "Portainer provides:"
echo "- Container management (start/stop/restart/logs)"
echo "- Image management"
echo "- Network and volume management"
echo "- Resource monitoring"
echo "- Container console access"