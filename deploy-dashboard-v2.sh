#!/bin/bash
# Deploy the improved AI Box Dashboard v2

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${YELLOW}=== Deploying AI Box Dashboard v2 ===${NC}"

# Check if running with proper permissions
if [[ ! -w "/opt/ai-box" ]]; then
    echo -e "${RED}Error: Need write permissions to /opt/ai-box${NC}"
    echo "Run with: sudo $0"
    exit 1
fi

# Stop existing dashboard services
echo -e "\n${BLUE}Stopping existing dashboard services...${NC}"
docker stop dashboard dashboard-backend dcgm-exporter 2>/dev/null || true
docker rm dashboard dashboard-backend dcgm-exporter 2>/dev/null || true

# Copy new files
echo -e "\n${BLUE}Installing new dashboard files...${NC}"
cp /home/mandrake/AI-Deployment/dashboard-v2.html /opt/ai-box/nginx/html/index.html
cp /home/mandrake/AI-Deployment/dashboard-backend-v2.py /opt/ai-box/dashboard-backend.py
chmod +x /opt/ai-box/dashboard-backend.py

# Create requirements file for backend
cat > /opt/ai-box/requirements.txt << 'EOF'
flask==2.3.3
flask-cors==4.0.0
docker==5.0.3
psutil==5.9.5
requests==2.28.2
EOF

# Create Dockerfile for backend
cat > /opt/ai-box/dashboard-backend.Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application
COPY dashboard-backend.py .

# Run the application
CMD ["python", "-u", "dashboard-backend.py"]
EOF

# Update nginx configuration
echo -e "\n${BLUE}Updating nginx configuration...${NC}"
cat > /opt/ai-box/nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Increase timeouts for slow backend responses
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;

    # Enable gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/json;

    server {
        listen 80;
        server_name localhost;

        # Frontend
        location / {
            root /usr/share/nginx/html;
            index index.html;
            try_files $uri $uri/ /index.html;
        }

        # API endpoints
        location /api/ {
            proxy_pass http://dashboard-backend:5000/api/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Disable buffering for real-time updates
            proxy_buffering off;
            proxy_cache off;
        }

        # GPU metrics from DCGM
        location /metrics {
            proxy_pass http://dcgm-exporter:9400/metrics;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        # Health check endpoint
        location /health {
            proxy_pass http://dashboard-backend:5000/health;
            proxy_set_header Host $host;
        }
    }
}
EOF

# Create docker-compose for dashboard services
echo -e "\n${BLUE}Creating docker-compose configuration...${NC}"
cat > /opt/ai-box/docker-compose.dashboard-v2.yml << 'EOF'
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
      - PYTHONUNBUFFERED=1
      - FLASK_APP=dashboard-backend.py
    restart: unless-stopped
    networks:
      - ai-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  dcgm-exporter:
    image: nvcr.io/nvidia/k8s/dcgm-exporter:3.1.8-3.1.5-ubuntu20.04
    container_name: dcgm-exporter
    ports:
      - "9400:9400"
    environment:
      - DCGM_EXPORTER_LISTEN=0.0.0.0:9400
      - DCGM_EXPORTER_KUBERNETES=false
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

# Build and start services
echo -e "\n${BLUE}Building and starting dashboard services...${NC}"
cd /opt/ai-box
docker compose -f docker-compose.dashboard-v2.yml build
docker compose -f docker-compose.dashboard-v2.yml up -d

# Wait for services to start
echo -e "\n${YELLOW}Waiting for services to initialize...${NC}"
sleep 10

# Check service status
echo -e "\n${BLUE}Checking service status...${NC}"
for service in dashboard dashboard-backend dcgm-exporter; do
    if docker ps | grep -q $service; then
        echo -e "  ✓ $service: ${GREEN}Running${NC}"
    else
        echo -e "  ✗ $service: ${RED}Failed${NC}"
        echo "    Logs:"
        docker logs $service --tail 10 2>&1 | sed 's/^/    /'
    fi
done

# Test API endpoints
echo -e "\n${BLUE}Testing API endpoints...${NC}"
sleep 2

# Test health endpoint
if curl -s -f http://localhost/health > /dev/null 2>&1; then
    echo -e "  ✓ Health check: ${GREEN}OK${NC}"
else
    echo -e "  ✗ Health check: ${RED}Failed${NC}"
fi

# Test services endpoint
if curl -s -f http://localhost/api/services > /dev/null 2>&1; then
    echo -e "  ✓ Services API: ${GREEN}OK${NC}"
else
    echo -e "  ✗ Services API: ${RED}Failed${NC}"
fi

# Test system endpoint
if curl -s -f http://localhost/api/system > /dev/null 2>&1; then
    echo -e "  ✓ System API: ${GREEN}OK${NC}"
else
    echo -e "  ✗ System API: ${RED}Failed${NC}"
fi

echo -e "\n${GREEN}=== Dashboard v2 Deployment Complete ===${NC}"
echo -e "\n${BLUE}Access the dashboard at:${NC} ${CYAN}http://localhost${NC}"
echo -e "\n${YELLOW}Features:${NC}"
echo -e "  • Shows ALL services dynamically"
echo -e "  • Displays NVIDIA driver and CUDA versions"
echo -e "  • Real-time resource usage for each service"
echo -e "  • Start/stop/restart controls for all services"
echo -e "  • Improved performance with 2-second cache"
echo -e "  • Detailed GPU metrics per card"
echo -e "\n${BLUE}API Endpoints:${NC}"
echo -e "  • /api/services - List all services with stats"
echo -e "  • /api/system - System and GPU information"
echo -e "  • /api/gpu/metrics - Detailed GPU metrics"
echo -e "  • /api/services/<name>/<action> - Control services"