#!/bin/bash
# Fix SD Forge CUDA environment

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}Fixing SD Forge CUDA environment...${NC}"

# Check CUDA 12.1 installation
echo -e "${BLUE}Checking CUDA 12.1 installation...${NC}"
if [[ ! -d "/usr/local/cuda-12.1" ]]; then
    echo -e "${RED}ERROR: CUDA 12.1 not found at /usr/local/cuda-12.1${NC}"
    echo "Please install CUDA 12.1 first using the main setup script option 6"
    exit 1
fi

# Check current CUDA symlink
echo -e "${BLUE}Current CUDA configuration:${NC}"
ls -la /usr/local/cuda* | grep -E "cuda($|->)"

# Stop forge container
echo -e "\n${YELLOW}Stopping SD Forge...${NC}"
docker stop forge 2>/dev/null || true
docker rm forge 2>/dev/null || true

# Create a custom docker-compose override for Forge
echo -e "\n${YELLOW}Creating Forge-specific configuration...${NC}"
cat > /opt/ai-box/docker-compose.forge.yml << 'EOF'
version: '3.8'

services:
  forge:
    image: nykk3/stable-diffusion-webui-forge:latest
    container_name: forge
    ports:
      - "7860:7860"
    volumes:
      - /opt/ai-box/models/stable-diffusion:/app/stable-diffusion-webui/models/Stable-diffusion
      - /opt/ai-box/models/loras:/app/stable-diffusion-webui/models/Lora
      - /opt/ai-box/models/vae:/app/stable-diffusion-webui/models/VAE
      - /opt/ai-box/outputs/forge:/app/stable-diffusion-webui/outputs
      - /opt/ai-box/forge-extensions:/app/stable-diffusion-webui/extensions
      - /usr/local/cuda-12.1/lib64:/usr/local/cuda/lib64:ro
      - /usr/local/cuda-12.1/compat:/usr/local/cuda/compat:ro
    environment:
      - COMMANDLINE_ARGS=--listen --port 7860 --api --xformers --enable-insecure-extension-access --skip-torch-cuda-test --skip-version-check --no-download-sd-model --lowvram
      - LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/compat:$LD_LIBRARY_PATH
      - CUDA_HOME=/usr/local/cuda
      - PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
      - TORCH_CUDA_ARCH_LIST=8.6;8.9
      - CUDA_MODULE_LOADING=LAZY
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    restart: unless-stopped
    networks:
      - ai-network
    shm_size: 8gb

networks:
  ai-network:
    external: true
EOF

# Test GPU access in a container
echo -e "\n${YELLOW}Testing GPU access with CUDA 12.1 libraries...${NC}"
docker run --rm --gpus all \
    -v /usr/local/cuda-12.1/lib64:/usr/local/cuda/lib64:ro \
    -e LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH \
    nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi

if [[ $? -ne 0 ]]; then
    echo -e "${RED}GPU test failed!${NC}"
    exit 1
fi

# Start Forge with the fixed configuration
echo -e "\n${YELLOW}Starting SD Forge with CUDA 12.1 environment...${NC}"
cd /opt/ai-box
docker compose -f docker-compose.forge.yml up -d

# Wait for startup
echo -e "\n${YELLOW}Waiting for Forge to initialize...${NC}"
sleep 10

# Check if it's running
if docker ps | grep -q forge; then
    echo -e "${GREEN}SD Forge container is running!${NC}"
    
    # Show recent logs
    echo -e "\n${BLUE}Recent Forge logs:${NC}"
    docker logs forge --tail 30
    
    # Check if web UI is responding
    echo -e "\n${YELLOW}Checking web UI...${NC}"
    sleep 5
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:7860 | grep -q "200\|302"; then
        echo -e "${GREEN}SD Forge web UI is responding!${NC}"
        echo -e "Access it at: ${BLUE}http://localhost:7860${NC}"
    else
        echo -e "${YELLOW}Web UI not ready yet, check in a few moments${NC}"
    fi
else
    echo -e "${RED}SD Forge failed to start!${NC}"
    echo -e "\n${RED}Error logs:${NC}"
    docker logs forge --tail 50
fi

echo -e "\n${BLUE}Debug commands:${NC}"
echo "  Check logs:     docker logs forge -f"
echo "  Check GPU:      docker exec forge nvidia-smi"
echo "  Check Python:   docker exec forge python -c 'import torch; print(torch.cuda.is_available())'"
echo "  Restart:        docker restart forge"