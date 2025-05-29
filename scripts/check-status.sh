#!/bin/bash
# check-status.sh - Check current AI Box installation status

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== AI Box Installation Status ===${NC}\n"

# Check NVIDIA Driver
echo -e "${BLUE}NVIDIA Driver:${NC}"
if command -v nvidia-smi &> /dev/null; then
    DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    echo -e "  ${GREEN}✓${NC} Installed: Version $DRIVER_VERSION"
    
    # Show GPUs
    echo -e "\n${BLUE}GPUs Detected:${NC}"
    nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader | while read line; do
        echo -e "  ${GREEN}✓${NC} $line"
    done
else
    echo -e "  ${RED}✗${NC} Not installed"
fi

# Check Docker
echo -e "\n${BLUE}Docker:${NC}"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | sed 's/,$//')
    echo -e "  ${GREEN}✓${NC} Installed: Version $DOCKER_VERSION"
    
    # Check NVIDIA runtime
    if docker info 2>/dev/null | grep -q "nvidia"; then
        echo -e "  ${GREEN}✓${NC} NVIDIA runtime configured"
    else
        echo -e "  ${YELLOW}!${NC} NVIDIA runtime not configured"
    fi
    
    # Check Docker Compose
    if docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version | cut -d' ' -f4)
        echo -e "  ${GREEN}✓${NC} Docker Compose: $COMPOSE_VERSION"
    else
        echo -e "  ${RED}✗${NC} Docker Compose not installed"
    fi
else
    echo -e "  ${RED}✗${NC} Not installed"
fi

# Check AI Services
echo -e "\n${BLUE}AI Services:${NC}"
if command -v docker &> /dev/null; then
    SERVICES=("localai" "ollama" "forge" "dcgm-exporter")
    
    for SERVICE in "${SERVICES[@]}"; do
        if docker ps -q -f name="^${SERVICE}$" | grep -q .; then
            # Get port mapping
            PORT=$(docker port "$SERVICE" 2>/dev/null | head -1 | cut -d':' -f2)
            echo -e "  ${GREEN}✓${NC} $SERVICE: Running (port $PORT)"
        elif docker ps -aq -f name="^${SERVICE}$" | grep -q .; then
            echo -e "  ${YELLOW}!${NC} $SERVICE: Stopped"
        else
            echo -e "  ${RED}✗${NC} $SERVICE: Not deployed"
        fi
    done
else
    echo -e "  ${YELLOW}!${NC} Cannot check - Docker not installed"
fi

# Check Directories
echo -e "\n${BLUE}Directories:${NC}"
DIRS=(
    "/opt/ai-box:AI Box root"
    "/opt/ai-box/models:Models directory"
    "/opt/ai-box/outputs:Outputs directory"
)

for DIR_INFO in "${DIRS[@]}"; do
    DIR=$(echo "$DIR_INFO" | cut -d':' -f1)
    DESC=$(echo "$DIR_INFO" | cut -d':' -f2)
    
    if [[ -d "$DIR" ]]; then
        SIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1)
        echo -e "  ${GREEN}✓${NC} $DESC: $SIZE"
    else
        echo -e "  ${RED}✗${NC} $DESC: Not found"
    fi
done

# Check Disk Space
echo -e "\n${BLUE}Disk Space:${NC}"
DISK_INFO=$(df -h /opt 2>/dev/null | awk 'NR==2 {print $4 " free of " $2}')
echo -e "  💾 /opt: $DISK_INFO"

# Check Running Processes
echo -e "\n${BLUE}GPU Processes:${NC}"
if command -v nvidia-smi &> /dev/null; then
    PROCS=$(nvidia-smi --query-compute-apps=pid,name,used_memory --format=csv,noheader 2>/dev/null | wc -l)
    if [[ $PROCS -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} $PROCS GPU process(es) running"
        nvidia-smi --query-compute-apps=pid,name,used_memory --format=csv,noheader 2>/dev/null | while read line; do
            echo "    - $line"
        done
    else
        echo -e "  ${YELLOW}!${NC} No GPU processes running"
    fi
fi

# Check Network Ports
echo -e "\n${BLUE}Network Ports:${NC}"
PORTS=("8080:LocalAI" "11434:Ollama" "7860:Forge" "9400:DCGM")

for PORT_INFO in "${PORTS[@]}"; do
    PORT=$(echo "$PORT_INFO" | cut -d':' -f1)
    SERVICE=$(echo "$PORT_INFO" | cut -d':' -f2)
    
    if lsof -i:$PORT &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Port $PORT ($SERVICE): In use"
    else
        echo -e "  ${YELLOW}!${NC} Port $PORT ($SERVICE): Available"
    fi
done

# Summary
echo -e "\n${BLUE}=== Summary ===${NC}"

# Count statuses
if command -v nvidia-smi &> /dev/null && command -v docker &> /dev/null && docker ps -q -f name="localai" | grep -q .; then
    echo -e "${GREEN}✓ AI Box appears to be fully deployed and running${NC}"
elif command -v nvidia-smi &> /dev/null && command -v docker &> /dev/null; then
    echo -e "${YELLOW}! System is ready but services need to be deployed${NC}"
else
    echo -e "${RED}✗ System needs initial setup${NC}"
fi

echo -e "\nRun ${BLUE}./setup.sh${NC} to install or update your deployment"