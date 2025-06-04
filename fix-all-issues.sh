#!/bin/bash
# Comprehensive fix for AI Box issues

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}=== AI Box Comprehensive Fix ===${NC}"

# 1. Fix Setup Script for Proper Container Management
echo -e "\n${BLUE}[1/4] Patching setup.sh for proper container cleanup...${NC}"

# Create a backup
cp /home/mandrake/AI-Deployment/setup.sh /home/mandrake/AI-Deployment/setup.sh.bak

# Patch the reset function to properly stop ALL containers
sed -i '/run_as_user docker compose down/c\
                # Stop ALL containers on ai-network first\
                echo "Stopping all AI Box services..."\
                docker ps -q --filter "network=ai-network" | xargs -r docker stop\
                docker ps -aq --filter "network=ai-network" | xargs -r docker rm\
                \
                # Also try docker-compose down if compose file exists\
                if [[ -f "/opt/ai-box/docker-compose.yml" ]]; then\
                    cd /opt/ai-box\
                    run_as_user docker compose down || true\
                fi' /home/mandrake/AI-Deployment/setup.sh

echo -e "${GREEN}✓ Setup script patched${NC}"

# 2. Update Service Definitions for No-Model Start
echo -e "\n${BLUE}[2/4] Updating service definitions...${NC}"

# Update n8n with secure cookie fix
sed -i 's/SERVICE_ENV\["n8n"\]="[^"]*"/SERVICE_ENV["n8n"]="N8N_SECURE_COOKIE=false;N8N_HOST=0.0.0.0;N8N_PORT=5678;NODE_ENV=production;WEBHOOK_URL=http:\/\/localhost:5678\/"/' /home/mandrake/AI-Deployment/setup.sh

# Update Forge environment to skip model download
sed -i 's/SERVICE_ENV\["forge"\]="[^"]*"/SERVICE_ENV["forge"]="COMMANDLINE_ARGS=--listen --api --xformers --medvram --skip-torch-cuda-test --skip-version-check --no-download-sd-model"/' /home/mandrake/AI-Deployment/setup.sh

# Update ComfyUI to use CUDA 12.1 image
sed -i 's/SERVICE_IMAGES\["comfyui"\]="[^"]*"/SERVICE_IMAGES["comfyui"]="yanwk\/comfyui-boot:cu121"/' /home/mandrake/AI-Deployment/setup.sh

echo -e "${GREEN}✓ Service definitions updated${NC}"

# 3. Create Dashboard Backend Service
echo -e "\n${BLUE}[3/4] Creating dashboard backend service...${NC}"

# Create dashboard backend Python script
cat > /opt/ai-box/dashboard-backend.py << 'EOF'
#!/usr/bin/env python3
from flask import Flask, jsonify
from flask_cors import CORS
import docker
import requests
import os

app = Flask(__name__)
CORS(app)

client = docker.from_env()

@app.route('/api/services')
def get_services():
    try:
        containers = client.containers.list(all=True)
        services = []
        
        for container in containers:
            if 'ai-network' in [n.name for n in container.attrs['NetworkSettings']['Networks'].values()]:
                services.append({
                    'name': container.name,
                    'status': container.status,
                    'image': container.image.tags[0] if container.image.tags else 'unknown',
                    'ports': container.ports
                })
        
        return jsonify(services)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/services/<service_name>/<action>')
def control_service(service_name, action):
    try:
        container = client.containers.get(service_name)
        
        if action == 'start':
            container.start()
        elif action == 'stop':
            container.stop()
        elif action == 'restart':
            container.restart()
        else:
            return jsonify({'error': 'Invalid action'}), 400
            
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

chmod +x /opt/ai-box/dashboard-backend.py

# Create Dockerfile for dashboard backend
cat > /opt/ai-box/dashboard-backend.Dockerfile << 'EOF'
FROM python:3.9-slim
WORKDIR /app
RUN pip install flask flask-cors docker requests
COPY dashboard-backend.py /app/
CMD ["python", "-u", "dashboard-backend.py"]
EOF

# Create docker-compose override for dashboard with backend
cat > /opt/ai-box/docker-compose.dashboard.yml << 'EOF'
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
      - dcgm-exporter

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

  dcgm-exporter:
    image: nvcr.io/nvidia/k8s/dcgm-exporter:3.1.8-3.1.5-ubuntu20.04
    container_name: dcgm-exporter
    ports:
      - "9400:9400"
    environment:
      - DCGM_EXPORTER_LISTEN=0.0.0.0:9400
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              capabilities: [gpu]
              count: all
    restart: unless-stopped
    cap_add:
      - SYS_ADMIN
    networks:
      - ai-network

networks:
  ai-network:
    external: true
EOF

# Update nginx config to proxy both metrics and API
cat > /opt/ai-box/nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        listen 80;
        server_name localhost;

        location / {
            root /usr/share/nginx/html;
            index index.html;
        }

        location /metrics {
            proxy_pass http://dcgm-exporter:9400/metrics;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        location /api/ {
            proxy_pass http://dashboard-backend:5000/api/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

echo -e "${GREEN}✓ Dashboard backend created${NC}"

# 4. Fix CUDA mounts in docker-compose generation
echo -e "\n${BLUE}[4/4] Adding CUDA fix to docker-compose generation...${NC}"

# Add CUDA mount logic to add_service_to_compose function
# This is a bit complex to sed, so we'll add instructions
cat > /home/mandrake/AI-Deployment/cuda-mount-patch.txt << 'EOF'
# Add this to the add_service_to_compose function after the volumes section:

    # Add CUDA 12.1 library mounts for Forge
    if [[ "$service" == "forge" ]] && [[ -d "/usr/local/cuda-12.1" ]]; then
        echo "      # CUDA 12.1 compatibility fix" >> "/opt/ai-box/docker-compose.yml"
        echo "      - /usr/local/cuda-12.1/lib64:/usr/local/cuda/lib64:ro" >> "/opt/ai-box/docker-compose.yml"
        echo "      - /usr/local/cuda-12.1/compat:/usr/local/cuda/compat:ro" >> "/opt/ai-box/docker-compose.yml"
    fi
    
    # Add shm_size for GPU services
    if [[ "$service" == "forge" ]] || [[ "$service" == "comfyui" ]]; then
        echo "    shm_size: 8gb" >> "/opt/ai-box/docker-compose.yml"
    fi
EOF

echo -e "${GREEN}✓ CUDA mount instructions created${NC}"

# Deploy the fixed dashboard
echo -e "\n${YELLOW}Deploying fixed dashboard...${NC}"

# Stop existing dashboard services
docker stop dashboard dashboard-backend dcgm-exporter 2>/dev/null || true
docker rm dashboard dashboard-backend dcgm-exporter 2>/dev/null || true

# Start dashboard with backend
cd /opt/ai-box
docker compose -f docker-compose.dashboard.yml up -d --build

echo -e "\n${GREEN}=== Fix Complete ===${NC}"
echo -e "\n${BLUE}Summary of changes:${NC}"
echo -e "1. ✓ Setup script now properly stops ALL containers when resetting"
echo -e "2. ✓ SD Forge and ComfyUI configured to start without models"
echo -e "3. ✓ n8n secure cookie issue fixed"
echo -e "4. ✓ Dashboard backend deployed for dynamic service status"
echo -e "5. ✓ GPU metrics available at /metrics"
echo -e "\n${YELLOW}Note:${NC} You need to manually add the CUDA mount logic to setup.sh"
echo -e "See: ${BLUE}/home/mandrake/AI-Deployment/cuda-mount-patch.txt${NC}"
echo -e "\n${GREEN}Dashboard should now show dynamic service status and GPU metrics!${NC}"