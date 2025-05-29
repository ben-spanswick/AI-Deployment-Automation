#!/bin/bash
# setup.sh - Dynamic AI Box Setup Script with Re-run Detection
# Supports flexible GPU configurations and safe re-deployment

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration files
CONFIG_FILE="${SCRIPT_DIR}/.deployment.conf"
STATE_FILE="${SCRIPT_DIR}/.deployment-state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Default values
DEFAULT_DEPLOY_METHOD="ansible"
DEFAULT_LOCALAI_PORT=8080
DEFAULT_OLLAMA_PORT=11434
DEFAULT_FORGE_PORT=7860
DEFAULT_DCGM_PORT=9400
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
skip() { echo -e "${CYAN}[SKIP]${NC} $1"; }

# State management functions
save_state() {
    local key=$1
    local value=$2
    if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$STATE_FILE"
    else
        echo "${key}=${value}" >> "$STATE_FILE"
    fi
}

get_state() {
    local key=$1
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2 || echo ""
    else
        echo ""
    fi
}

check_state() {
    local key=$1
    local state=$(get_state "$key")
    [[ "$state" == "completed" ]]
}

# Create directory structure
create_directory_structure() {
    log "Creating AI Box directory structure..."
    
    local dirs=(
        "/opt/ai-box"
        "/opt/ai-box/models"
        "/opt/ai-box/models/stable-diffusion"
        "/opt/ai-box/models/stable-diffusion/SDXL"
        "/opt/ai-box/models/loras"
        "/opt/ai-box/models/vae"
        "/opt/ai-box/models/embeddings"
        "/opt/ai-box/outputs"
        "/opt/ai-box/outputs/forge"
        "/opt/ai-box/nginx"
        "/opt/ai-box/nginx/html"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            sudo mkdir -p "$dir"
            sudo chown -R $USER:$USER "$dir"
            log "Created: $dir"
        else
            skip "Directory exists: $dir"
        fi
    done
    
    success "Directory structure ready"
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove any temporary files created during deployment
    local temp_files=(
        "${SCRIPT_DIR}/ansible/*.retry"
        "${SCRIPT_DIR}/.ansible-*"
        "/tmp/ai-box-*"
    )
    
    for pattern in "${temp_files[@]}"; do
        if ls $pattern 2>/dev/null | grep -q .; then
            rm -f $pattern
            log "Removed: $pattern"
        fi
    done
    
    success "Cleanup completed"
}

# Check if resuming after reboot
check_resume_after_reboot() {
    if [[ "$(get_state 'resume_after_reboot')" == "true" ]]; then
        log "Resuming deployment after reboot..."
        
        # Check if driver is now working
        if check_nvidia_driver; then
            success "NVIDIA driver loaded successfully!"
            save_state "nvidia_driver" "completed"
            save_state "resume_after_reboot" "false"
            save_state "needs_reboot" "false"
        else
            error "NVIDIA driver still not functional after reboot"
            error "Please check driver installation and try again"
            exit 1
        fi
    fi
}

# Handle NVIDIA driver installation
handle_nvidia_driver_install() {
    if check_state "nvidia_driver" || check_nvidia_driver; then
        skip "NVIDIA driver already installed and loaded"
        save_state "nvidia_driver" "completed"
        return 0
    fi
    
    warn "NVIDIA driver installation required"
    echo
    echo "Installing NVIDIA drivers requires a system reboot to load the kernel modules."
    echo "After installation, you will need to:"
    echo "  1. Reboot your system"
    echo "  2. Run this script again to continue deployment"
    echo
    read -p "Install NVIDIA drivers now? [Y/n]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "NVIDIA drivers are required. Exiting."
        exit 1
    fi
    
    # Mark that we need reboot after driver install
    save_state "needs_reboot" "true"
    
    # Install drivers (via ansible or direct)
    case $DEPLOY_METHOD in
        ansible)
            cd "${SCRIPT_DIR}/ansible"
            ansible-playbook -i inventory.yml playbook.yml --tags nvidia -v
            ;;
        *)
            error "Please use Ansible deployment method for initial system setup"
            exit 1
            ;;
    esac
    
    save_state "nvidia_driver" "installed_needs_reboot"
    
    echo
    echo -e "${YELLOW}${BOLD}=== REBOOT REQUIRED ===${NC}"
    echo
    echo "NVIDIA drivers have been installed but require a reboot to load."
    echo
    echo "Please:"
    echo "  1. Save any work and close applications"
    echo "  2. Reboot your system: ${BOLD}sudo reboot${NC}"
    echo "  3. After reboot, run: ${BOLD}cd $(pwd) && ./setup.sh${NC}"
    echo
    echo "The script will resume from where it left off."
    echo
    
    # Save progress
    save_state "resume_after_reboot" "true"
    exit 0
}

# System checks
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
    
    if [[ "$OS" != "ubuntu" ]] || [[ ! "$VER" =~ ^(20\.04|22\.04|24\.04)$ ]]; then
        error "This script requires Ubuntu 20.04, 22.04, or 24.04"
        error "Detected: $OS $VER"
        exit 1
    fi
    
    log "Detected OS: Ubuntu $VER"
}

check_existing_services() {
    log "Checking existing AI Box services..."
    
    local services=("localai" "ollama" "forge" "dcgm-exporter")
    local running_services=()
    local stopped_services=()
    
    if command -v docker &> /dev/null; then
        for service in "${services[@]}"; do
            if docker ps -q -f name="^${service}$" 2>/dev/null | grep -q .; then
                running_services+=("$service")
            elif docker ps -aq -f name="^${service}$" 2>/dev/null | grep -q .; then
                stopped_services+=("$service")
            fi
        done
    fi
    
    if [[ ${#running_services[@]} -gt 0 ]]; then
        echo
        success "Found running services: ${running_services[*]}"
        echo
        echo "What would you like to do with existing services?"
        echo "1) Keep them running (recommended)"
        echo "2) Restart with new configuration only"
        echo "3) Stop services but keep data"
        echo "4) Remove everything and redeploy (WARNING: data loss)"
        
        read -p "Enter choice [1-4] (default: 1): " service_choice
        case $service_choice in
            1|"") 
                SKIP_DEPLOYMENT=true
                skip "Keeping existing services as-is"
                ;;
            2) 
                RESTART_SERVICES=true
                log "Will restart services with new configuration"
                ;;
            3)
                STOP_SERVICES=true
                log "Will stop services but preserve data"
                ;;
            4) 
                warn "This will DELETE all container data!"
                read -p "Are you SURE? Type 'yes' to confirm: " confirm
                if [[ "$confirm" == "yes" ]]; then
                    REMOVE_SERVICES=true
                    warn "Will remove and redeploy all services"
                else
                    SKIP_DEPLOYMENT=true
                    skip "Cancelled - keeping existing services"
                fi
                ;;
        esac
    fi
    
    if [[ ${#stopped_services[@]} -gt 0 ]]; then
        warn "Found stopped services: ${stopped_services[*]}"
        echo "These will be removed and redeployed"
    fi
}

detect_gpus() {
    log "Detecting GPU configuration..."
    
    # Check for saved GPU state
    local saved_gpu_count=$(get_state "gpu_count")
    
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
    
    # Check if GPU configuration changed
    if [[ -n "$saved_gpu_count" ]] && [[ "$GPU_COUNT" != "$saved_gpu_count" ]]; then
        warn "GPU configuration has changed!"
        warn "Previous: $saved_gpu_count GPUs, Current: $GPU_COUNT GPUs"
        echo "You may need to reconfigure GPU assignments"
    fi
    
    # Save current GPU state
    save_state "gpu_count" "$GPU_COUNT"
    save_state "gpu_model" "$GPU_MODEL"
}

check_disk_space() {
    log "Checking disk space..."
    
    local required_gb=100
    local available_gb=$(df -BG /opt 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [[ $available_gb -lt $required_gb ]]; then
        warn "Low disk space: ${available_gb}GB available, ${required_gb}GB recommended"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        skip "Disk space OK: ${available_gb}GB available"
    fi
}

check_nvidia_driver() {
    if command -v nvidia-smi &> /dev/null; then
        local current_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | tr -d ' ')
        local required_version="${DEFAULT_DRIVER_VERSION}"
        
        if [[ "$current_version" == "$required_version"* ]]; then
            skip "NVIDIA driver $current_version already installed"
            return 0
        else
            warn "NVIDIA driver $current_version installed, but $required_version recommended"
            return 1
        fi
    else
        return 1
    fi
}

check_docker() {
    if command -v docker &> /dev/null && docker --version &> /dev/null; then
        skip "Docker already installed: $(docker --version)"
        
        # Check if nvidia runtime is configured
        if docker info 2>/dev/null | grep -q "nvidia"; then
            skip "NVIDIA container runtime already configured"
            return 0
        else
            warn "Docker installed but NVIDIA runtime not configured"
            return 1
        fi
    else
        return 1
    fi
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

prompt_gpu_assignment() {
    echo
    echo -e "${BOLD}GPU Assignment Configuration${NC}"
    echo "You have $GPU_COUNT GPU(s) available"
    echo
    echo "How would you like to assign GPUs to services?"
    echo "1) Automatic - Distribute GPUs across services"
    echo "2) Manual - Specify GPU assignment per service"
    echo "3) Single GPU - Use only one GPU for all services"
    echo "4) All GPUs - All services use all available GPUs (recommended for LLMs)"
    
    read -p "Enter choice [1-4] (default: 4): " gpu_choice
    
    case $gpu_choice in
        1)
            AUTO_GPU_ASSIGN=true
            if [[ $GPU_COUNT -ge 2 ]]; then
                LOCALAI_GPUS="0"
                OLLAMA_GPUS="1"
                FORGE_GPUS="0,1"
            else
                LOCALAI_GPUS="0"
                OLLAMA_GPUS="0"
                FORGE_GPUS="0"
            fi
            ;;
        2)
            AUTO_GPU_ASSIGN=false
            echo
            echo "Available GPUs: 0-$((GPU_COUNT-1))"
            read -p "LocalAI GPU(s) [comma-separated] (default: 0,1): " LOCALAI_GPUS
            LOCALAI_GPUS=${LOCALAI_GPUS:-"0,1"}
            
            read -p "Ollama GPU(s) [comma-separated] (default: 0,1): " OLLAMA_GPUS
            OLLAMA_GPUS=${OLLAMA_GPUS:-"0,1"}
            
            read -p "Forge GPU(s) [comma-separated] (default: 0,1): " FORGE_GPUS
            FORGE_GPUS=${FORGE_GPUS:-"0,1"}
            ;;
        3)
            AUTO_GPU_ASSIGN=false
            read -p "Which GPU to use [0-$((GPU_COUNT-1))] (default: 0): " SINGLE_GPU
            SINGLE_GPU=${SINGLE_GPU:-"0"}
            LOCALAI_GPUS="$SINGLE_GPU"
            OLLAMA_GPUS="$SINGLE_GPU"
            FORGE_GPUS="$SINGLE_GPU"
            ;;
        4|"")
            AUTO_GPU_ASSIGN=true
            # All services use all GPUs
            ALL_GPUS=$(seq -s, 0 $((GPU_COUNT-1)))
            LOCALAI_GPUS="$ALL_GPUS"
            OLLAMA_GPUS="$ALL_GPUS"
            FORGE_GPUS="$ALL_GPUS"
            ;;
    esac
    
    echo
    success "GPU Assignment:"
    echo "  LocalAI: GPU(s) $LOCALAI_GPUS"
    echo "  Ollama: GPU(s) $OLLAMA_GPUS"
    echo "  Forge: GPU(s) $FORGE_GPUS"
}

prompt_service_ports() {
    echo
    echo -e "${BOLD}Service Port Configuration${NC}"
    echo "Configure ports for each service (press Enter for defaults)"
    
    read -p "LocalAI port (default: $DEFAULT_LOCALAI_PORT): " LOCALAI_PORT
    LOCALAI_PORT=${LOCALAI_PORT:-$DEFAULT_LOCALAI_PORT}
    
    read -p "Ollama port (default: $DEFAULT_OLLAMA_PORT): " OLLAMA_PORT
    OLLAMA_PORT=${OLLAMA_PORT:-$DEFAULT_OLLAMA_PORT}
    
    read -p "Forge port (default: $DEFAULT_FORGE_PORT): " FORGE_PORT
    FORGE_PORT=${FORGE_PORT:-$DEFAULT_FORGE_PORT}
    
    read -p "DCGM Metrics port (default: $DEFAULT_DCGM_PORT): " DCGM_PORT
    DCGM_PORT=${DCGM_PORT:-$DEFAULT_DCGM_PORT}
    
    # Check for port conflicts
    for port in $LOCALAI_PORT $OLLAMA_PORT $FORGE_PORT $DCGM_PORT; do
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
LOCALAI_GPUS=$LOCALAI_GPUS
OLLAMA_GPUS=$OLLAMA_GPUS
FORGE_GPUS=$FORGE_GPUS

# Service Ports
LOCALAI_PORT=$LOCALAI_PORT
OLLAMA_PORT=$OLLAMA_PORT
FORGE_PORT=$FORGE_PORT
DCGM_PORT=$DCGM_PORT

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
          localai_gpus: "${LOCALAI_GPUS}"
          ollama_gpus: "${OLLAMA_GPUS}"
          forge_gpus: "${FORGE_GPUS}"
          
          # Service ports
          localai_port: ${LOCALAI_PORT}
          ollama_port: ${OLLAMA_PORT}
          forge_port: ${FORGE_PORT}
          dcgm_port: ${DCGM_PORT}
          
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
LOCALAI_GPUS=${LOCALAI_GPUS}
OLLAMA_GPUS=${OLLAMA_GPUS}
FORGE_GPUS=${FORGE_GPUS}

# Service Ports
LOCALAI_PORT=${LOCALAI_PORT}
OLLAMA_PORT=${OLLAMA_PORT}
FORGE_PORT=${FORGE_PORT}
DCGM_PORT=${DCGM_PORT}

# Optional Features
ENABLE_DCGM=${ENABLE_DCGM}
ENABLE_WATCHTOWER=${ENABLE_WATCHTOWER}
ENABLE_DASHBOARD=${ENABLE_DASHBOARD}

# Paths
MODELS_DIR=/opt/ai-box/models
OUTPUTS_DIR=/opt/ai-box/outputs

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
    echo "    - LocalAI: Port $LOCALAI_PORT (GPU $LOCALAI_GPUS)"
    echo "    - Ollama: Port $OLLAMA_PORT (GPU $OLLAMA_GPUS)"
    echo "    - Forge: Port $FORGE_PORT (GPU $FORGE_GPUS)"
    echo
    
    read -p "Proceed with deployment? [Y/n]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warn "Deployment cancelled"
        exit 0
    fi
    
    # Remove existing services if requested
    if [[ "${REMOVE_SERVICES:-false}" == "true" ]]; then
        log "Removing existing services..."
        if [[ -f "/opt/ai-box/docker-compose.yml" ]]; then
            cd /opt/ai-box
            docker compose down -v || true
            cd - > /dev/null
        fi
    fi
    
    case $DEPLOY_METHOD in
        ansible)
            log "Running Ansible deployment..."
            cd "${SCRIPT_DIR}/ansible"
            
            # Check if we need to install NVIDIA driver
            if ! check_state "nvidia_driver" || ! check_nvidia_driver; then
                handle_nvidia_driver_install  # This may exit for reboot
            fi
            
            if ! check_state "docker" || ! check_docker; then
                ansible-playbook -i inventory.yml playbook.yml --tags docker -v
                save_state "docker" "completed"
            fi
            
            # Deploy services
            ansible-playbook -i inventory.yml playbook.yml --tags services -v
            save_state "services" "completed"
            ;;
            
        docker)
            log "Running Docker Compose deployment..."
            
            # Check prerequisites
            if ! check_docker; then
                error "Docker is not installed. Please run with Ansible deployment method first."
                exit 1
            fi
            
            cd "${SCRIPT_DIR}/docker"
            
            if [[ "${RESTART_SERVICES:-false}" == "true" ]]; then
                docker compose restart
            else
                docker compose up -d
            fi
            save_state "services" "completed"
            ;;
            
        hybrid)
            log "Running hybrid deployment..."
            cd "${SCRIPT_DIR}/ansible"
            
            # System setup only
            if ! check_state "system_setup"; then
                ansible-playbook -i inventory.yml playbook.yml --tags system,docker -v
                save_state "system_setup" "completed"
            fi
            
            echo
            success "System setup complete!"
            echo "To start services, run:"
            echo "  cd ${SCRIPT_DIR}/docker && docker compose up -d"
            ;;
    esac
}

show_completion() {
    # Set defaults if variables are not set (e.g., when keeping existing services)
    TARGET_HOST=${TARGET_HOST:-localhost}
    LOCALAI_PORT=${LOCALAI_PORT:-8080}
    OLLAMA_PORT=${OLLAMA_PORT:-11434}
    FORGE_PORT=${FORGE_PORT:-7860}
    DCGM_PORT=${DCGM_PORT:-9400}
    ENABLE_DCGM=${ENABLE_DCGM:-true}
    ENABLE_DASHBOARD=${ENABLE_DASHBOARD:-false}
    
    echo
    success "Deployment Complete!"
    echo
    echo -e "${BOLD}${CYAN}=== Access Your Services ===${NC}"
    echo
    echo "🧠 LocalAI (OpenAI-compatible API):"
    echo "   URL: http://${TARGET_HOST}:${LOCALAI_PORT}"
    echo "   API: http://${TARGET_HOST}:${LOCALAI_PORT}/v1/completions"
    echo
    echo "🦙 Ollama (Model Management):"
    echo "   URL: http://${TARGET_HOST}:${OLLAMA_PORT}"
    echo "   CLI: docker exec ollama ollama run llama2"
    echo
    echo "🎨 Stable Diffusion Forge:"
    echo "   URL: http://${TARGET_HOST}:${FORGE_PORT}"
    echo "   API: http://${TARGET_HOST}:${FORGE_PORT}/sdapi/v1/txt2img"
    
    if [[ "$ENABLE_DCGM" == "true" ]]; then
        echo
        echo "📊 GPU Metrics:"
        echo "   URL: http://${TARGET_HOST}:${DCGM_PORT}/metrics"
    fi
    
    if [[ "$ENABLE_DASHBOARD" == "true" ]]; then
        echo
        echo "🎯 Web Dashboard:"
        echo "   URL: http://${TARGET_HOST} (port 80)"
        echo "   Features: Service status, GPU monitoring, quick access"
    else
        echo
        echo "📌 Note: Web Dashboard is not enabled."
        echo "   To enable it, run setup again and choose 'Y' when asked about the dashboard."
    fi
    
    # Check if dashboard container is actually running
    if docker ps -q -f name="nginx-dashboard" | grep -q .; then
        echo
        echo "✅ Web Dashboard is running on port 80"
        echo "   Access it at: http://${TARGET_HOST}"
    fi
    
    echo
    echo -e "${BOLD}${CYAN}=== Directory Structure ===${NC}"
    echo "Models: /opt/ai-box/models/"
    echo "  ├── LocalAI models: /opt/ai-box/models/*.gguf"
    echo "  ├── SD models: /opt/ai-box/models/stable-diffusion/"
    echo "  ├── LoRA models: /opt/ai-box/models/loras/"
    echo "  └── VAE models: /opt/ai-box/models/vae/"
    echo "Outputs: /opt/ai-box/outputs/"
    
    echo
    echo -e "${BOLD}${CYAN}=== Useful Commands ===${NC}"
    echo "Check status: ${SCRIPT_DIR}/scripts/check-status.sh"
    echo "View logs: cd /opt/ai-box && docker compose logs -f [service]"
    echo "Restart services: cd /opt/ai-box && docker compose restart"
    echo "Update services: cd /opt/ai-box && docker compose pull && docker compose up -d"
    
    echo
    echo "Configuration saved to: $CONFIG_FILE"
    echo "Deployment state saved to: $STATE_FILE"
    
    # Cleanup
    cleanup_temp_files
}

# Main execution
main() {
    print_banner
    check_root
    detect_os
    
    # Initialize state file
    if [[ ! -f "$STATE_FILE" ]]; then
        touch "$STATE_FILE"
        log "Created deployment state file"
    fi
    
    # Check system status
    check_disk_space
    detect_gpus
    check_resume_after_reboot  # Check if we're resuming after reboot
    create_directory_structure  # Create directories early
    check_existing_services
    
    # Skip deployment if requested
    if [[ "${SKIP_DEPLOYMENT:-false}" == "true" ]]; then
        show_completion
        exit 0
    fi
    
    # Check for existing configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        echo
        log "Found existing configuration from $(stat -c %y "$CONFIG_FILE" | cut -d' ' -f1)"
        source "$CONFIG_FILE"
        
        echo "Previous settings:"
        echo "  - Method: $DEPLOY_METHOD"
        echo "  - GPUs: $GPU_COUNT x $GPU_MODEL"
        echo "  - Services: LocalAI:$LOCALAI_PORT, Ollama:$OLLAMA_PORT, Forge:$FORGE_PORT"
        echo
        
        read -p "Use existing configuration? [Y/n]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            generate_ansible_inventory
            generate_docker_env
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

# Handle interruption
trap 'echo -e "\n${YELLOW}Deployment interrupted. Run again to resume.${NC}"; exit 130' INT TERM

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi