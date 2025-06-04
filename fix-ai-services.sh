#!/bin/bash
# Fix AI Box Services - ComfyUI, SD Forge, and Dashboard
# Addresses CUDA compatibility and missing configurations

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}=== AI Box Services Fix Script ===${NC}"
echo -e "${BLUE}This script will fix ComfyUI, SD Forge, and Dashboard issues${NC}\n"

# Function to check if running as root
check_root() {
    # Skip root check if --dangerously-skip-permissions is passed
    if [[ "$*" == *"--dangerously-skip-permissions"* ]]; then
        echo -e "${YELLOW}Warning: Running without root permissions${NC}"
        return 0
    fi
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root or with sudo${NC}"
        exit 1
    fi
}

# 1. Fix SD Forge with CUDA 12.1
fix_forge() {
    echo -e "\n${YELLOW}[1/4] Fixing SD Forge CUDA compatibility...${NC}"
    
    # Stop existing forge
    docker stop forge 2>/dev/null || true
    docker rm forge 2>/dev/null || true
    
    # Create fixed docker-compose for Forge
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
      - COMMANDLINE_ARGS=--listen --port 7860 --api --xformers --enable-insecure-extension-access --skip-torch-cuda-test --skip-version-check --no-download-sd-model
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
    
    # Create model directories
    mkdir -p /opt/ai-box/models/{stable-diffusion,loras,vae}
    mkdir -p /opt/ai-box/outputs/forge
    mkdir -p /opt/ai-box/forge-extensions
    
    # Start Forge
    cd /opt/ai-box
    docker compose -f docker-compose.forge.yml up -d
    
    echo -e "${GREEN}SD Forge started with CUDA 12.1 fix${NC}"
    echo -e "${YELLOW}Note: You'll need to download at least one model to use Forge${NC}"
}

# 2. Fix ComfyUI GPU access
fix_comfyui() {
    echo -e "\n${YELLOW}[2/4] Fixing ComfyUI GPU access...${NC}"
    
    # Stop existing comfyui
    docker stop comfyui 2>/dev/null || true
    docker rm comfyui 2>/dev/null || true
    
    # Create fixed docker-compose for ComfyUI
    cat > /opt/ai-box/docker-compose.comfyui.yml << 'EOF'
version: '3.8'

services:
  comfyui:
    image: yanwk/comfyui-boot:latest
    container_name: comfyui
    ports:
      - "8188:8188"
    volumes:
      - /opt/ai-box/comfyui:/workspace
      - /opt/ai-box/models:/workspace/models
      - /opt/ai-box/comfyui/output:/workspace/output
      - /usr/local/cuda-12.1/lib64:/usr/local/cuda/lib64:ro
    environment:
      - CLI_ARGS=--listen --port 8188
      - LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
      - CUDA_HOME=/usr/local/cuda
      - CUDA_VISIBLE_DEVICES=0
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['0']
              capabilities: [gpu]
    restart: unless-stopped
    networks:
      - ai-network
    shm_size: 8gb

networks:
  ai-network:
    external: true
EOF
    
    # Create ComfyUI directories
    mkdir -p /opt/ai-box/comfyui/{output,custom_nodes}
    
    # Start ComfyUI
    cd /opt/ai-box
    docker compose -f docker-compose.comfyui.yml up -d
    
    echo -e "${GREEN}ComfyUI started with GPU access${NC}"
}

# 3. Fix Dashboard backend
fix_dashboard() {
    echo -e "\n${YELLOW}[3/4] Fixing Dashboard backend service...${NC}"
    
    # Create dashboard backend dockerfile
    cat > /opt/ai-box/dashboard-backend.Dockerfile << 'EOF'
FROM python:3.9-slim
WORKDIR /app
RUN pip install flask flask-cors docker requests
COPY dashboard-backend.py /app/
CMD ["python", "-u", "dashboard-backend.py"]
EOF
    
    # Copy dashboard backend script
    if [[ -f "/home/mandrake/AI-Deployment/dashboard-backend.py" ]]; then
        cp /home/mandrake/AI-Deployment/dashboard-backend.py /opt/ai-box/
    elif [[ -f "/home/mandrake/AI-Box-Backup-20250602-223614/dashboard-backend.py" ]]; then
        cp /home/mandrake/AI-Box-Backup-20250602-223614/dashboard-backend.py /opt/ai-box/
    else
        echo -e "${RED}dashboard-backend.py not found!${NC}"
        return 1
    fi
    
    # Update docker-compose for dashboard
    cat > /opt/ai-box/docker-compose-dashboard-fixed.yml << 'EOF'
version: '3.8'

services:
  dashboard:
    image: nginx:alpine
    container_name: dashboard
    ports:
      - "80:80"
    volumes:
      - /opt/ai-box/nginx/html:/usr/share/nginx/html:ro
      - /opt/ai-box/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    restart: unless-stopped
    networks:
      - ai-network
    depends_on:
      - dashboard-backend

  dashboard-backend:
    build:
      context: /opt/ai-box
      dockerfile: dashboard-backend.Dockerfile
    container_name: dashboard-backend
    ports:
      - "5000:5000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - FLASK_APP=dashboard-backend.py
    restart: unless-stopped
    networks:
      - ai-network

networks:
  ai-network:
    external: true
EOF
    
    # Update nginx config to proxy backend
    if [[ -f "/opt/ai-box/nginx/nginx.conf" ]]; then
        # Backup original
        cp /opt/ai-box/nginx/nginx.conf /opt/ai-box/nginx/nginx.conf.bak
        
        # Add backend proxy to nginx config
        sed -i '/location \/metrics {/,/}/c\
        location /metrics {\
            proxy_pass http://dcgm-exporter:9400/metrics;\
            proxy_set_header Host $host;\
            proxy_set_header X-Real-IP $remote_addr;\
        }\
\
        location /api/ {\
            proxy_pass http://dashboard-backend:5000/api/;\
            proxy_set_header Host $host;\
            proxy_set_header X-Real-IP $remote_addr;\
        }' /opt/ai-box/nginx/nginx.conf
    fi
    
    # Stop existing dashboard
    docker stop dashboard 2>/dev/null || true
    docker rm dashboard 2>/dev/null || true
    
    # Start dashboard with backend
    cd /opt/ai-box
    docker compose -f docker-compose-dashboard-fixed.yml up -d --build
    
    echo -e "${GREEN}Dashboard and backend services started${NC}"
}

# 4. Verify all services
verify_services() {
    echo -e "\n${YELLOW}[4/4] Verifying services...${NC}"
    
    sleep 10  # Give services time to start
    
    echo -e "\n${BLUE}Service Status:${NC}"
    
    # Check Forge
    if docker ps | grep -q forge; then
        echo -e "  SD Forge: ${GREEN}Running${NC}"
        if docker logs forge 2>&1 | tail -5 | grep -q "No checkpoints found"; then
            echo -e "    ${YELLOW}⚠ No models found - download a model to use Forge${NC}"
        fi
    else
        echo -e "  SD Forge: ${RED}Not running${NC}"
    fi
    
    # Check ComfyUI
    if docker ps | grep -q comfyui; then
        echo -e "  ComfyUI: ${GREEN}Running${NC}"
        if curl -s http://localhost:8188 > /dev/null 2>&1; then
            echo -e "    ${GREEN}✓ Web UI accessible at http://localhost:8188${NC}"
        fi
    else
        echo -e "  ComfyUI: ${RED}Not running${NC}"
    fi
    
    # Check Dashboard
    if docker ps | grep -q dashboard; then
        echo -e "  Dashboard: ${GREEN}Running${NC}"
        if curl -s http://localhost > /dev/null 2>&1; then
            echo -e "    ${GREEN}✓ Web UI accessible at http://localhost${NC}"
        fi
    fi
    
    # Check Dashboard Backend
    if docker ps | grep -q dashboard-backend; then
        echo -e "  Dashboard Backend: ${GREEN}Running${NC}"
    else
        echo -e "  Dashboard Backend: ${RED}Not running${NC}"
    fi
    
    # Check DCGM
    if docker ps | grep -q dcgm-exporter; then
        echo -e "  DCGM GPU Metrics: ${GREEN}Running${NC}"
    fi
}

# Main execution
main() {
    check_root "$@"
    
    echo -e "${BLUE}Starting fixes...${NC}"
    
    fix_forge
    fix_comfyui
    fix_dashboard
    verify_services
    
    echo -e "\n${GREEN}=== Fix Complete ===${NC}"
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo -e "1. Download SD models to /opt/ai-box/models/stable-diffusion/"
    echo -e "2. Access services:"
    echo -e "   - Dashboard: http://localhost"
    echo -e "   - SD Forge: http://localhost:7860"
    echo -e "   - ComfyUI: http://localhost:8188"
    echo -e "\n${BLUE}Debug Commands:${NC}"
    echo -e "  docker logs forge -f"
    echo -e "  docker logs comfyui -f"
    echo -e "  docker logs dashboard-backend -f"
}

# Run main
main "$@"