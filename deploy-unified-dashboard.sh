#!/bin/bash
# Deploy the unified AI Box Dashboard
# Single container solution with embedded frontend and backend

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${YELLOW}=== Deploying AI Box Unified Dashboard ===${NC}"

# Check permissions
if [[ ! -w "/opt/ai-box" ]]; then
    echo -e "${RED}Error: Need write permissions to /opt/ai-box${NC}"
    echo "Run with: sudo $0"
    exit 1
fi

# Stop ALL existing dashboard-related containers
echo -e "\n${BLUE}Stopping existing dashboard services...${NC}"
for container in dashboard dashboard-backend dcgm-exporter dcgm; do
    if docker ps -a | grep -q $container; then
        echo "  Stopping $container..."
        docker stop $container 2>/dev/null || true
        docker rm $container 2>/dev/null || true
    fi
done

# Copy the unified dashboard
echo -e "\n${BLUE}Installing unified dashboard...${NC}"
cp /home/mandrake/AI-Deployment/dashboard-unified.py /opt/ai-box/dashboard.py
chmod +x /opt/ai-box/dashboard.py

# Create a simple Dockerfile
cat > /opt/ai-box/Dockerfile.dashboard << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir flask==2.3.3

# Copy the application
COPY dashboard.py /app/

# Expose port 80
EXPOSE 80

# Run the application
CMD ["python", "-u", "dashboard.py"]
EOF

# Create docker-compose for the unified dashboard
cat > /opt/ai-box/docker-compose.dashboard.yml << 'EOF'
version: '3.8'

services:
  dashboard:
    build:
      context: /opt/ai-box
      dockerfile: Dockerfile.dashboard
    image: aibox-dashboard:latest
    container_name: dashboard
    ports:
      - "80:80"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - PYTHONUNBUFFERED=1
    restart: unless-stopped
    networks:
      - ai-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-network:
    external: true
EOF

# Build and deploy
echo -e "\n${BLUE}Building dashboard image...${NC}"
cd /opt/ai-box
docker compose -f docker-compose.dashboard.yml build

echo -e "\n${BLUE}Starting unified dashboard...${NC}"
docker compose -f docker-compose.dashboard.yml up -d

# Wait for startup
echo -e "\n${YELLOW}Waiting for dashboard to initialize...${NC}"
sleep 5

# Verify it's working
echo -e "\n${BLUE}Verifying dashboard...${NC}"

# Check if container is running
if docker ps | grep -q dashboard; then
    echo -e "  ✓ Dashboard container: ${GREEN}Running${NC}"
else
    echo -e "  ✗ Dashboard container: ${RED}Failed${NC}"
    echo "    Logs:"
    docker logs dashboard --tail 20
    exit 1
fi

# Test API endpoints
echo -e "\n${BLUE}Testing API endpoints...${NC}"

# Test health
if curl -s -f http://localhost/health > /dev/null 2>&1; then
    echo -e "  ✓ Health check: ${GREEN}OK${NC}"
else
    echo -e "  ✗ Health check: ${RED}Failed${NC}"
fi

# Test services API
services_response=$(curl -s http://localhost/api/services 2>/dev/null)
if [[ "$services_response" == *"services"* ]]; then
    echo -e "  ✓ Services API: ${GREEN}OK${NC}"
    
    # Count services
    service_count=$(echo "$services_response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(len(data.get('services', [])))
" 2>/dev/null || echo "0")
    
    echo -e "  ✓ Services detected: ${GREEN}${service_count}${NC}"
    
    # List services
    echo -e "\n${BLUE}Active services:${NC}"
    echo "$services_response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for s in data.get('services', []):
        print(f\"  - {s['name']} ({s['status']}) - {s['category']}\")
except:
    pass
" 2>/dev/null || echo "  Could not parse services"
else
    echo -e "  ✗ Services API: ${RED}Failed${NC}"
fi

# Test GPU metrics
if curl -s http://localhost/api/gpu/metrics | grep -q "gpus" 2>/dev/null; then
    echo -e "  ✓ GPU metrics API: ${GREEN}OK${NC}"
else
    echo -e "  ✗ GPU metrics API: ${RED}Failed${NC}"
fi

echo -e "\n${GREEN}=== Dashboard Deployment Complete ===${NC}"
echo -e "\n${BLUE}Access the dashboard at:${NC} ${CYAN}http://localhost${NC}"
echo -e "\n${YELLOW}Features:${NC}"
echo -e "  • Single container solution (no separate backend)"
echo -e "  • Shows ALL services on ai-network dynamically"
echo -e "  • Real-time service status and resource usage"
echo -e "  • NVIDIA driver and CUDA version display"
echo -e "  • GPU metrics for each card"
echo -e "  • Start/stop/restart controls"
echo -e "  • Automatic categorization of services"
echo -e "  • 2-second cache for performance"
echo -e "\n${BLUE}API Endpoints:${NC}"
echo -e "  • ${CYAN}/api/services${NC} - All services with stats"
echo -e "  • ${CYAN}/api/system${NC} - System and GPU information"
echo -e "  • ${CYAN}/api/gpu/metrics${NC} - Detailed GPU metrics"
echo -e "  • ${CYAN}/api/services/<name>/<action>${NC} - Service control"
echo -e "  • ${CYAN}/health${NC} - Health check"
echo -e "  • ${CYAN}/metrics${NC} - Prometheus-style metrics"

# Troubleshooting info
echo -e "\n${BLUE}Troubleshooting:${NC}"
echo -e "  View logs: ${CYAN}docker logs dashboard -f${NC}"
echo -e "  Restart: ${CYAN}docker restart dashboard${NC}"
echo -e "  Check services: ${CYAN}curl http://localhost/api/services | jq${NC}"