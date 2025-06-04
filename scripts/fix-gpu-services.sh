#!/bin/bash
# Fix GPU services for AI Box

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Fixing AI Box GPU services...${NC}"

# Stop all services
echo "Stopping current services..."
cd /opt/ai-box
docker compose down

# Backup current compose file
echo "Backing up current configuration..."
cp docker-compose.yml docker-compose.yml.bak

# Use the fixed compose file
echo "Applying fixed configuration..."
cp docker-compose-fixed.yml docker-compose.yml

# Update dashboard files to fix slowness
echo "Updating dashboard..."
if [[ -f "/home/mandrake/AI-Deployment/dashboard.html" ]]; then
    sudo cp /home/mandrake/AI-Deployment/dashboard.html /opt/ai-box/nginx/html/index.html
fi

# Ensure all directories exist
echo "Ensuring directories exist..."
mkdir -p /opt/ai-box/{models,outputs,localai/cache,ollama/models,chromadb,n8n,whisper/models,comfyui,nginx/html}
mkdir -p /opt/ai-box/models/{stable-diffusion,loras,vae}
mkdir -p /opt/ai-box/outputs/forge
mkdir -p /opt/ai-box/comfyui/output

# Set permissions
chown -R $USER:$USER /opt/ai-box

# Start services
echo "Starting services with fixed GPU configuration..."
docker compose up -d

# Wait for services to start
echo "Waiting for services to initialize..."
sleep 10

# Check status
echo -e "\n${YELLOW}Service Status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Show logs for any failing services
echo -e "\n${YELLOW}Checking for errors...${NC}"
for service in forge comfyui dcgm whisper chromadb; do
    if ! docker ps | grep -q "$service"; then
        echo -e "${RED}$service is not running. Recent logs:${NC}"
        docker logs $service --tail 10 2>&1 || true
        echo "---"
    fi
done

echo -e "\n${GREEN}Fix applied!${NC}"
echo "Access services at:"
echo "  - Dashboard: http://localhost"
echo "  - SD Forge: http://localhost:7860"
echo "  - ComfyUI: http://localhost:8188"
echo "  - ChromaDB: http://localhost:8000"
echo "  - Whisper: http://localhost:9000"
echo ""
echo "If services are still failing, check logs with: docker logs [service-name]"