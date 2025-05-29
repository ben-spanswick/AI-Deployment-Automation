#!/bin/bash
# setup.sh - Dynamic AI Box Setup Script
# Supports flexible GPU configurations and deployment options

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration file
CONFIG_FILE="${SCRIPT_DIR}/.deployment.conf"

# Default values
DEFAULT_DEPLOY_METHOD="ansible"
DEFAULT_TEXTGEN_PORT=8080
DEFAULT_SD_PORT=8081
DEFAULT_FASTAPI_PORT=8000
DEFAULT_DRIVER_VERSION="535"

# Functions
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║        AI Box Deployment Setup           ║"
    echo "║   Flexible Multi-GPU AI Workstation      ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root"
        echo "Please run as a regular user with sudo privileges"
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        error "Cannot detect OS. This script requires Ubuntu 20.04 or 22.04"
        exit 1
    fi
    
    if [[ "$OS" != "ubuntu" ]] || [[ ! "$VER" =~ ^(20\.04|22\.04)$ ]]; then
        error "This script requires Ubuntu 20.04 or 22.04"
        error "Detected: $OS $VER"
        exit 1
    fi
    
    log "Detected OS: Ubuntu $VER"
}

detect_gpus() {
    log "Detecting GPU configuration..."
    
    # Run GPU detection script
    if [[ -f "${SCRIPT_DIR}/scripts/gpu-detect.sh" ]]; then
        source "${SCRIPT_DIR}/scripts/gpu-detect.sh"
    else
        # Fallback GPU detection
        if command -v nvidia-smi &> /dev/null; then
            GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
            GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        elif command -v lspci &> /dev/null; then
            GPU_COUNT=$(lspci | grep -i nvidia | grep -i vga | wc -l)
            GPU_MODEL=$(lspci | grep -i nvidia | grep -i vga | head -1 | sed 's/.*: //')
        else
            GPU_COUNT=0
            GPU_MODEL="Unknown"
        fi
    fi
    
    if [[ $GPU_COUNT -eq 0 ]]; then
        error "No NVIDIA GPUs detected!"
        echo "This deployment requires NVIDIA GPUs"
        exit 1
    fi
    
    success "Detected $GPU_COUNT NVIDIA GPU(s): $GPU_MODEL"
}

prompt_deployment_method() {
    echo
    echo -e "${BOLD}Select deployment method:${NC}"
    echo "1) Ansible (Recommended) - Full system configuration"
    echo "2) Docker Compose - Container-only deployment"
    echo "3) Hybrid - Ansible for system setup, manual Docker Compose"
    
    read -p "Enter choice [1-3] (default: 1): " choice
    case $choice in
        1|"") DEPLOY_METHOD="ansible" ;;
        2) DEPLOY_METHOD="docker" ;;
        3) DEPLOY_METHOD="hybrid" ;;
        *) error "Invalid choice"; exit 1 ;;
    esac
    
    log "Selected deployment method: $DEPLOY_METHOD"
}

prompt_gpu_assignment() {
    echo
    echo -e "${BOLD}GPU Assignment Configuration${NC}"
    echo "You have $GPU_COUNT GPU(s) available"
    echo
    echo "How would you like to assign GPUs to services?"
    echo "1) Automatic - Distribute GPUs across services"
    echo "2) Manual - Specify GPU assignment per service"
    echo "3) Single GPU - Use only one GPU for all services"
    
    read -p "Enter choice [1-3] (default: 1): " gpu_choice
    
    case $gpu_choice in
        1|"")
            AUTO_GPU_ASSIGN=true
            if [[ $GPU_COUNT -ge 2 ]]; then
                TEXTGEN_GPUS="0"
                SD_GPUS="1"
                FASTAPI_GPUS="0,1"
            else
                TEXTGEN_GPUS="0"
                SD_GPUS="0"
                FASTAPI_GPUS="0"
            fi
            ;;
        2)
            AUTO_GPU_ASSIGN=false
            echo
            echo "Available GPUs: 0-$((GPU_COUNT-1))"
            read -p "Text Generation GPU(s) [comma-separated] (default: 0): " TEXTGEN_GPUS
            TEXTGEN_GPUS=${TEXTGEN_GPUS:-"0"}
            
            read -p "Stable Diffusion GPU(s) [comma-separated] (default: 1): " SD_GPUS
            SD_GPUS=${SD_GPUS:-"1"}
            
            read -p "FastAPI GPU(s) [comma-separated] (default: 0,1): " FASTAPI_GPUS
            FASTAPI_GPUS=${FASTAPI_GPUS:-"0,1"}
            ;;
        3)
            AUTO_GPU_ASSIGN=false
            read -p "Which GPU to use [0-$((GPU_COUNT-1))] (default: 0): " SINGLE_GPU
            SINGLE_GPU=${SINGLE_GPU:-"0"}
            TEXTGEN_GPUS="$SINGLE_GPU"
            SD_GPUS="$SINGLE_GPU"
            FASTAPI_GPUS="$SINGLE_GPU"
            ;;
    esac
    
    echo
    success "GPU Assignment:"
    echo "  Text Generation: GPU(s) $TEXTGEN_GPUS"
    echo "  Stable Diffusion: GPU(s) $SD_GPUS"
    echo "  FastAPI: GPU(s) $FASTAPI_GPUS"
}

prompt_service_ports() {
    echo
    echo -e "${BOLD}Service Port Configuration${NC}"
    echo "Configure ports for each service (press Enter for defaults)"
    
    read -p "Text Generation WebUI port (default: $DEFAULT_TEXTGEN_PORT): " TEXTGEN_PORT
    TEXTGEN_PORT=${TEXTGEN_PORT:-$DEFAULT_TEXTGEN_PORT}
    
    read -p "Stable Diffusion WebUI port (default: $DEFAULT_SD_PORT): " SD_PORT
    SD_PORT=${SD_PORT:-$DEFAULT_SD_PORT}
    
    read -p "FastAPI port (default: $DEFAULT_FASTAPI_PORT): " FASTAPI_PORT
    FASTAPI_PORT=${FASTAPI_PORT:-$DEFAULT_FASTAPI_PORT}
    
    # Check for port conflicts
    for port in $TEXTGEN_PORT $SD_PORT $FASTAPI_PORT; do
        if lsof -i:$port &> /dev/null; then
            warn "Port $port is already in use!"
        fi
    done
}

prompt_optional_features() {
    echo
    echo -e "${BOLD}Optional Features${NC}"
    
    read -p "Enable GPU monitoring (DCGM)? [Y/n]: " -n 1 -r
    echo
    ENABLE_DCGM=$([[ $REPLY =~ ^[Yy]$ ]] && echo "true" || echo "false")
    
    read -p "Enable automatic updates (Watchtower)? [y/N]: " -n 1 -r
    echo
    ENABLE_WATCHTOWER=$([[ $REPLY =~ ^[Yy]$ ]] && echo "true" || echo "false")
    
    read -p "Enable web dashboard? [Y/n]: " -n 1 -r
    echo
    ENABLE_DASHBOARD=$([[ $REPLY =~ ^[Yy]$ ]] && echo "true" || echo "false")
}

prompt_deployment_target() {
    echo
    echo -e "${BOLD}Deployment Target${NC}"
    echo "1) Local machine (this computer)"
    echo "2) Remote machine (SSH)"
    
    read -p "Enter choice [1-2] (default: 1): " target_choice
    
    case $target_choice in
        1|"")
            DEPLOY_TARGET="local"
            TARGET_HOST="localhost"
            TARGET_USER="$USER"
            ;;
        2)
            DEPLOY_TARGET="remote"
            read -p "Remote hostname/IP: " TARGET_HOST
            read -p "Remote username (default: $USER): " TARGET_USER
            TARGET_USER=${TARGET_USER:-$USER}
            read -p "SSH key path (default: ~/.ssh/id_rsa): " SSH_KEY
            SSH_KEY=${SSH_KEY:-"$HOME/.ssh/id_rsa"}
            ;;
    esac
}

save_configuration() {
    log "Saving configuration..."
    
    cat > "$CONFIG_FILE" << EOF
# AI Box Deployment Configuration
# Generated on $(date)

# Deployment
DEPLOY_METHOD=$DEPLOY_METHOD
DEPLOY_TARGET=$DEPLOY_TARGET
TARGET_HOST=$TARGET_HOST
TARGET_USER=$TARGET_USER
SSH_KEY=${SSH_KEY:-}

# System
OS_VERSION=$VER
GPU_COUNT=$GPU_COUNT
GPU_MODEL="$GPU_MODEL"
NVIDIA_DRIVER_VERSION=$DEFAULT_DRIVER_VERSION

# GPU Assignment
AUTO_GPU_ASSIGN=$AUTO_GPU_ASSIGN
TEXTGEN_GPUS=$TEXTGEN_GPUS
SD_GPUS=$SD_GPUS
FASTAPI_GPUS=$FASTAPI_GPUS

# Service Ports
TEXTGEN_PORT=$TEXTGEN_PORT
SD_PORT=$SD_PORT
FASTAPI_PORT=$FASTAPI_PORT

# Optional Features
ENABLE_DCGM=$ENABLE_DCGM
ENABLE_WATCHTOWER=$ENABLE_WATCHTOWER
ENABLE_DASHBOARD=$ENABLE_DASHBOARD

# Paths
AI_BOX_DIR=/opt/ai-box
MODELS_DIR=/opt/ai-box/models
OUTPUTS_DIR=/opt/ai-box/outputs
EOF
    
    success "Configuration saved to $CONFIG_FILE"
}

generate_ansible_inventory() {
    log "Generating Ansible inventory..."
    
    cat > "${SCRIPT_DIR}/ansible/inventory.yml" << EOF
all:
  children:
    ai_boxes:
      hosts:
        ${TARGET_HOST}:
          ansible_host: ${TARGET_HOST}
          ansible_user: ${TARGET_USER}
          ${SSH_KEY:+ansible_ssh_private_key_file: $SSH_KEY}
          ansible_python_interpreter: /usr/bin/python3
          
          # Hardware configuration
          gpu_count: ${GPU_COUNT}
          gpu_model: "${GPU_MODEL}"
          
          # GPU assignments
          textgen_gpus: "${TEXTGEN_GPUS}"
          sd_gpus: "${SD_GPUS}"
          fastapi_gpus: "${FASTAPI_GPUS}"
          
          # Service ports
          textgen_port: ${TEXTGEN_PORT}
          stablediffusion_port: ${SD_PORT}
          fastapi_port: ${FASTAPI_PORT}
          
          # Optional features
          enable_dcgm: ${ENABLE_DCGM}
          enable_watchtower: ${ENABLE_WATCHTOWER}
          enable_dashboard: ${ENABLE_DASHBOARD}
EOF
}

generate_docker_env() {
    log "Generating Docker environment file..."
    
    cat > "${SCRIPT_DIR}/docker/.env" << EOF
# AI Box Docker Environment
# Generated on $(date)

# GPU Configuration
GPU_COUNT=${GPU_COUNT}
TEXTGEN_GPUS=${TEXTGEN_GPUS}
SD_GPUS=${SD_GPUS}
FASTAPI_GPUS=${FASTAPI_GPUS}

# Service Ports
TEXTGEN_PORT=${TEXTGEN_PORT}
SD_PORT=${SD_PORT}
FASTAPI_PORT=${FASTAPI_PORT}
DCGM_PORT=9400
NGINX_PORT=80

# Optional Features
ENABLE_DCGM=${ENABLE_DCGM}
ENABLE_WATCHTOWER=${ENABLE_WATCHTOWER}
ENABLE_DASHBOARD=${ENABLE_DASHBOARD}

# Paths
MODELS_DIR=./models
OUTPUTS_DIR=./outputs

# Container Settings
COMPOSE_PROJECT_NAME=ai-box
TZ=UTC
PUID=1000
PGID=1000
EOF
}

run_deployment() {
    echo
    echo -e "${BOLD}Ready to Deploy!${NC}"
    echo
    echo "Configuration Summary:"
    echo "  Deployment Method: $DEPLOY_METHOD"
    echo "  Target: $TARGET_HOST"
    echo "  GPUs: $GPU_COUNT x $GPU_MODEL"
    echo "  Services:"
    echo "    - Text Generation WebUI: Port $TEXTGEN_PORT (GPU $TEXTGEN_GPUS)"
    echo "    - Stable Diffusion WebUI: Port $SD_PORT (GPU $SD_GPUS)"
    echo "    - FastAPI: Port $FASTAPI_PORT (GPU $FASTAPI_GPUS)"
    echo
    
    read -p "Proceed with deployment? [Y/n]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warn "Deployment cancelled"
        exit 0
    fi
    
    case $DEPLOY_METHOD in
        ansible)
            log "Running Ansible deployment..."
            cd "${SCRIPT_DIR}/ansible"
            ansible-playbook -i inventory.yml playbook.yml -v
            ;;
        docker)
            log "Running Docker Compose deployment..."
            cd "${SCRIPT_DIR}/docker"
            docker compose up -d
            ;;
        hybrid)
            log "Running hybrid deployment..."
            cd "${SCRIPT_DIR}/ansible"
            ansible-playbook -i inventory.yml playbook.yml --tags system,docker -v
            echo
            success "System setup complete!"
            echo "To start services, run:"
            echo "  cd ${SCRIPT_DIR}/docker && docker compose up -d"
            ;;
    esac
}

show_completion() {
    echo
    success "Deployment Complete!"
    echo
    echo "Access your services:"
    echo "  Text Generation: http://${TARGET_HOST}:${TEXTGEN_PORT}"
    echo "  Stable Diffusion: http://${TARGET_HOST}:${SD_PORT}"
    echo "  API Docs: http://${TARGET_HOST}:${FASTAPI_PORT}/docs"
    
    if [[ "$ENABLE_DCGM" == "true" ]]; then
        echo "  GPU Metrics: http://${TARGET_HOST}:9400/metrics"
    fi
    
    if [[ "$ENABLE_DASHBOARD" == "true" ]]; then
        echo "  Dashboard: http://${TARGET_HOST}"
    fi
    
    echo
    echo "Configuration saved to: $CONFIG_FILE"
    echo
    echo "Useful commands:"
    echo "  Check status: ${SCRIPT_DIR}/scripts/health-check.sh"
    echo "  View logs: cd ${AI_BOX_DIR} && docker compose logs -f"
    echo "  Cleanup: ${SCRIPT_DIR}/scripts/cleanup.sh"
}

# Main execution
main() {
    print_banner
    check_root
    detect_os
    detect_gpus
    
    # Check for existing configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        echo
        read -p "Found existing configuration. Use it? [Y/n]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            source "$CONFIG_FILE"
            run_deployment
            show_completion
            exit 0
        fi
    fi
    
    # Interactive configuration
    prompt_deployment_method
    prompt_deployment_target
    prompt_gpu_assignment
    prompt_service_ports
    prompt_optional_features
    
    # Save and generate configs
    save_configuration
    generate_ansible_inventory
    generate_docker_env
    
    # Run deployment
    run_deployment
    show_completion
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi