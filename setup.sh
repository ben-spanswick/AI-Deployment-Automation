#!/bin/bash
# AI Box - Unified GPU-Accelerated AI Services Platform
# setup.sh - Dynamic service deployment and management
# Version: 2.0.0

set -euo pipefail

# Error handling
trap 'error_handler $? $LINENO' ERR

error_handler() {
    local exit_code=$1
    local line_number=$2
    echo -e "${RED}[ERROR]${NC} Script failed with exit code $exit_code at line $line_number" >&2
    echo -e "${RED}[ERROR]${NC} Check logs for more details" >&2
    exit $exit_code
}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration files
CONFIG_DIR="${SCRIPT_DIR}/config"
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="${CONFIG_DIR}/deployment.conf"
STATE_FILE="${CONFIG_DIR}/deployment-state"
SERVICES_FILE="${CONFIG_DIR}/deployed-services.json"

# Log file
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Service Registry - Extensible service definitions
declare -A SERVICE_INFO
declare -A SERVICE_PORTS
declare -A SERVICE_IMAGES
declare -A SERVICE_VOLUMES
declare -A SERVICE_ENV
declare -A SERVICE_REQUIRES

# LLM Services
SERVICE_INFO["localai"]="LocalAI|OpenAI-compatible LLM API|llm"
SERVICE_PORTS["localai"]="8080"
SERVICE_IMAGES["localai"]="quay.io/go-skynet/local-ai:latest-gpu-nvidia-cuda-12"
SERVICE_VOLUMES["localai"]="models:/build/models;localai/cache:/tmp/generated"
SERVICE_ENV["localai"]="THREADS=8;DEBUG=false"

SERVICE_INFO["ollama"]="Ollama|Simple LLM management with CLI|llm"
SERVICE_PORTS["ollama"]="11434"
SERVICE_IMAGES["ollama"]="ollama/ollama:latest"
SERVICE_VOLUMES["ollama"]="ollama/models:/root/.ollama"
SERVICE_ENV["ollama"]="OLLAMA_HOST=0.0.0.0"

# ChromaDB - Vector database for embeddings
SERVICE_INFO["chromadb"]="ChromaDB|Vector database for RAG/embeddings|database"
SERVICE_PORTS["chromadb"]="8000"
SERVICE_IMAGES["chromadb"]="chromadb/chroma:latest"
SERVICE_VOLUMES["chromadb"]="chromadb:/chroma/chroma"
SERVICE_ENV["chromadb"]="IS_PERSISTENT=TRUE;PERSIST_DIRECTORY=/chroma/chroma;ANONYMIZED_TELEMETRY=FALSE"
SERVICE_REQUIRES["chromadb"]=""

# n8n - Workflow automation
SERVICE_INFO["n8n"]="n8n|Workflow automation for AI chains|automation"
SERVICE_PORTS["n8n"]="5678"
SERVICE_IMAGES["n8n"]="n8nio/n8n:latest"
SERVICE_VOLUMES["n8n"]="n8n:/home/node/.n8n"
SERVICE_ENV["n8n"]="N8N_SECURE_COOKIE=false;N8N_HOST=0.0.0.0"
SERVICE_REQUIRES["n8n"]=""

# Whisper - Speech to text
SERVICE_INFO["whisper"]="Whisper|OpenAI speech-to-text|audio"
SERVICE_PORTS["whisper"]="9000"
SERVICE_IMAGES["whisper"]="onerahmet/openai-whisper-asr-webservice:latest-gpu"
SERVICE_VOLUMES["whisper"]="whisper/models:/app/models"
SERVICE_ENV["whisper"]="ASR_MODEL=base;ASR_ENGINE=openai_whisper"

# Image Generation Services
SERVICE_INFO["forge"]="SD Forge|Optimized Stable Diffusion WebUI|image"
SERVICE_PORTS["forge"]="7860"
SERVICE_IMAGES["forge"]="nykk3/stable-diffusion-webui-forge:latest"
SERVICE_VOLUMES["forge"]="models/stable-diffusion:/app/stable-diffusion-webui/models/Stable-diffusion;models/loras:/app/stable-diffusion-webui/models/Lora;models/vae:/app/stable-diffusion-webui/models/VAE;outputs/forge:/app/stable-diffusion-webui/outputs"
SERVICE_ENV["forge"]="COMMANDLINE_ARGS=--listen --api --xformers --medvram"

SERVICE_INFO["comfyui"]="ComfyUI|Node-based workflow (FLUX support!)|image"
SERVICE_PORTS["comfyui"]="8188"
SERVICE_IMAGES["comfyui"]="yanwk/comfyui-boot:latest"
SERVICE_VOLUMES["comfyui"]="comfyui:/workspace;models:/workspace/models;comfyui/output:/workspace/output"
SERVICE_ENV["comfyui"]="CLI_ARGS=--listen"

# Image generation services - keeping only Forge and ComfyUI
# Removed: AUTOMATIC1111 (redundant with Forge), InvokeAI (redundant UI), Fooocus (simplified UI, redundant)

# Training/Tools - Currently empty (Kohya_ss removed due to compatibility issues)

# Support Services
SERVICE_INFO["dcgm"]="DCGM Exporter|NVIDIA GPU metrics|support"
SERVICE_PORTS["dcgm"]="9400"
SERVICE_IMAGES["dcgm"]="nvcr.io/nvidia/k8s/dcgm-exporter:3.1.8-3.1.5-ubuntu20.04"
SERVICE_VOLUMES["dcgm"]=""
SERVICE_ENV["dcgm"]="DCGM_EXPORTER_LISTEN=0.0.0.0:9400;DCGM_EXPORTER_KUBERNETES=false"
SERVICE_REQUIRES["dcgm"]=""

SERVICE_INFO["dashboard"]="Web Dashboard|Unified control panel|support"
SERVICE_PORTS["dashboard"]="80"
SERVICE_IMAGES["dashboard"]="nginx:alpine"
SERVICE_VOLUMES["dashboard"]="nginx/html:/usr/share/nginx/html:ro;nginx/nginx.conf:/etc/nginx/nginx.conf:ro"
SERVICE_ENV["dashboard"]=""
SERVICE_REQUIRES["dashboard"]=""

# Functions
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Print banner
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════╗"
    echo "║        AI Box Modular Setup v2.0           ║"
    echo "║     Dynamic Service Management System       ║"
    echo "╚════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check if running with sudo
    if [[ $EUID -eq 0 ]]; then
        error "Please run this script without sudo"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if user is in docker group
    if ! groups | grep -q docker; then
        error "User $USER is not in the docker group"
        echo "Run: sudo usermod -aG docker $USER"
        exit 1
    fi
    
    # Check NVIDIA drivers
    if ! command -v nvidia-smi &> /dev/null; then
        error "NVIDIA drivers not found. Please install NVIDIA drivers."
        exit 1
    fi
    
    # Check NVIDIA Container Toolkit
    if ! docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi &> /dev/null; then
        error "NVIDIA Container Toolkit not working properly"
        exit 1
    fi
    
    # Check disk space (require at least 50GB free)
    local free_space=$(df /opt 2>/dev/null || df / | awk 'NR==2 {print $4}')
    local required_space=$((50 * 1024 * 1024))  # 50GB in KB
    if [[ $free_space -lt $required_space ]]; then
        error "Insufficient disk space. At least 50GB free space required."
        echo "Available: $(($free_space / 1024 / 1024))GB"
        exit 1
    fi
    
    # Create AI Box directory if it doesn't exist
    if [[ ! -d "/opt/ai-box" ]]; then
        sudo mkdir -p /opt/ai-box
        sudo chown $USER:$USER /opt/ai-box
    fi
    
    success "System requirements check passed"
}

# Detect GPUs
detect_gpus() {
    log "Detecting GPUs..."
    
    # Get GPU count
    GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
    
    if [[ $GPU_COUNT -eq 0 ]]; then
        error "No GPUs detected"
        exit 1
    fi
    
    # Get GPU model (first GPU)
    GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
    
    success "Detected $GPU_COUNT GPU(s): $GPU_MODEL"
    
    # Save to config
    echo "GPU_COUNT=$GPU_COUNT" >> "$CONFIG_FILE"
    echo "GPU_MODEL=\"$GPU_MODEL\"" >> "$CONFIG_FILE"
}

# Custom service selection
custom_service_selection() {
    echo
    echo -e "${BOLD}Custom Service Selection${NC}"
    echo "Select services to deploy (space-separated numbers):"
    
    local i=1
    local service_array=()
    
    # Build service array and display options
    for service in "${!SERVICE_INFO[@]}"; do
        service_array+=("$service")
        IFS='|' read -r name desc category <<< "${SERVICE_INFO[$service]}"
        echo "$i) $service - $name: $desc"
        ((i++))
    done
    
    read -p "Enter numbers (e.g., 1 3 5): " selections
    
    SELECTED_SERVICES=""
    for num in $selections; do
        if [[ $num -ge 1 ]] && [[ $num -le ${#service_array[@]} ]]; then
            SELECTED_SERVICES+="${service_array[$((num-1))]} "
        fi
    done
    
    # Trim trailing space
    SELECTED_SERVICES=${SELECTED_SERVICES% }
}

# Update existing services
update_existing_services() {
    log "Updating existing services..."
    
    if [[ -z "$DEPLOYED_SERVICES" ]]; then
        warn "No services are currently deployed!"
        return
    fi
    
    echo "Select update method:"
    echo "1) Update images only (pull latest versions)"
    echo "2) Reset configurations to defaults"
    echo "3) Cancel"
    
    read -p "Enter choice [1-3]: " update_choice
    
    case $update_choice in
        1)
            echo "Pulling latest images for deployed services..."
            
            # Pull images in parallel for better performance
            local pull_pids=()
            for service in $DEPLOYED_SERVICES; do
                local image="${SERVICE_IMAGES[$service]}"
                log "Starting update for $service..."
                docker pull "$image" &
                pull_pids+=($!)
            done
            
            # Wait for all pulls to complete
            log "Waiting for all image updates to complete..."
            local failed_pulls=0
            for pid in "${pull_pids[@]}"; do
                if ! wait $pid; then
                    ((failed_pulls++))
                fi
            done
            
            if [[ $failed_pulls -gt 0 ]]; then
                warn "$failed_pulls image(s) failed to update"
            else
                success "All images updated successfully"
            fi
            
            echo
            read -p "Restart services with new images? [y/N]: " restart
            
            if [[ "$restart" =~ ^[Yy]$ ]]; then
                cd /opt/ai-box
                docker compose down
                docker compose up -d
                success "Services updated and restarted"
            else
                log "Images updated. Restart manually when ready."
            fi
            ;;
        2)
            warn "This will reset all service configurations to defaults!"
            read -p "Are you sure? Type 'yes' to confirm: " confirm
            
            if [[ "$confirm" == "yes" ]]; then
                # Stop all services
                cd /opt/ai-box
                docker compose down
                
                # Regenerate configuration
                SELECTED_SERVICES="$DEPLOYED_SERVICES"
                generate_dynamic_docker_compose
                
                # Start services with new config
                docker compose up -d
                success "Services reset to default configurations"
            else
                log "Update cancelled"
            fi
            ;;
        *)
            log "Update cancelled"
            ;;
    esac
}

# Load existing deployment state
load_deployed_services() {
    if [[ -f "$SERVICES_FILE" ]]; then
        # Check if jq is available
        if ! command -v jq &> /dev/null; then
            warn "jq not found. Installing jq for JSON parsing..."
            sudo apt-get update && sudo apt-get install -y jq
        fi
        
        # Parse with error handling
        DEPLOYED_SERVICES=$(cat "$SERVICES_FILE" | jq -r '.services[]' 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
        
        # Validate the parsed result
        if [[ -z "$DEPLOYED_SERVICES" ]] && [[ -s "$SERVICES_FILE" ]]; then
            warn "Failed to parse services file. It may be corrupted."
            # Try to recover by reading raw content
            local raw_content=$(cat "$SERVICES_FILE")
            if [[ "$raw_content" =~ \"services\":\[(.*)\] ]]; then
                DEPLOYED_SERVICES=$(echo "${BASH_REMATCH[1]}" | sed 's/"//g' | sed 's/,/ /g')
                log "Recovered services: $DEPLOYED_SERVICES"
            fi
        fi
    else
        DEPLOYED_SERVICES=""
    fi
}

# Save deployment state
save_deployed_services() {
    local services_json='{"services":['
    local first=true
    
    for service in $1; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            services_json+=","
        fi
        services_json+="\"$service\""
    done
    
    services_json+=']}'
    echo "$services_json" > "$SERVICES_FILE"
}

# Check if service container already exists
check_existing_container() {
    local service=$1
    
    # Check if container exists (running or stopped)
    if docker ps -a --format "{{.Names}}" | grep -q "^${service}$"; then
        return 0
    else
        return 1
    fi
}

# Handle existing service
handle_existing_service() {
    local service=$1
    
    if check_existing_container "$service"; then
        echo
        warn "Service '$service' already exists!"
        echo "Options:"
        echo "1) Skip - Keep existing configuration"
        echo "2) Update - Reset to default configuration"
        echo "3) Remove - Remove completely and start fresh"
        
        read -p "Choose option [1-3] (default: 1): " choice
        
        case ${choice:-1} in
            1)
                log "Skipping $service - keeping existing configuration"
                return 1  # Skip this service
                ;;
            2)
                log "Updating $service to default configuration"
                docker stop "$service" 2>/dev/null || true
                docker rm "$service" 2>/dev/null || true
                return 0  # Continue with setup
                ;;
            3)
                log "Removing $service completely"
                docker stop "$service" 2>/dev/null || true
                docker rm "$service" 2>/dev/null || true
                remove_service_directories "$service"
                return 0  # Continue with setup
                ;;
            *)
                log "Invalid choice - skipping $service"
                return 1  # Skip this service
                ;;
        esac
    fi
    
    return 0  # Service doesn't exist, continue normally
}

# Create directory structure for a service
create_service_directories() {
    local service=$1
    local volumes="${SERVICE_VOLUMES[$service]}"
    
    log "Creating directories for $service..."
    
    # Parse volume mappings
    IFS=';' read -ra VOLUME_ARRAY <<< "$volumes"
    for volume in "${VOLUME_ARRAY[@]}"; do
        if [[ -n "$volume" ]]; then
            local host_path="${volume%%:*}"
            
            # Handle relative paths
            if [[ ! "$host_path" =~ ^/ ]]; then
                host_path="/opt/ai-box/$host_path"
            fi
            
            # Create directory if it doesn't exist
            if [[ ! -d "$host_path" ]]; then
                # Check if this is a file path (contains extension or ends with .conf)
                if [[ "$host_path" =~ \.[a-zA-Z0-9]+$ ]]; then
                    # It's a file, create parent directory
                    local parent_dir=$(dirname "$host_path")
                    if [[ ! -d "$parent_dir" ]]; then
                        sudo mkdir -p "$parent_dir"
                        sudo chown -R $USER:$USER "$parent_dir"
                        log "Created parent directory: $parent_dir"
                    fi
                else
                    # It's a directory
                    sudo mkdir -p "$host_path"
                    sudo chown -R $USER:$USER "$host_path"
                    log "Created: $host_path"
                fi
            fi
        fi
    done
}

# Remove service directories (with confirmation)
remove_service_directories() {
    local service=$1
    local volumes="${SERVICE_VOLUMES[$service]}"
    
    warn "Remove data directories for $service?"
    read -p "This will DELETE all data! Type 'yes' to confirm: " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        IFS=';' read -ra VOLUME_ARRAY <<< "$volumes"
        for volume in "${VOLUME_ARRAY[@]}"; do
            if [[ -n "$volume" ]]; then
                local host_path="${volume%%:*}"
                if [[ ! "$host_path" =~ ^/ ]]; then
                    host_path="/opt/ai-box/$host_path"
                fi
                
                # Only remove service-specific directories
                if [[ "$host_path" =~ $service ]] && [[ -d "$host_path" ]]; then
                    sudo rm -rf "$host_path"
                    log "Removed: $host_path"
                fi
            fi
        done
    else
        log "Keeping data directories"
    fi
}

# Dynamic service selection with current state
prompt_service_management() {
    load_deployed_services
    
    echo
    echo -e "${BOLD}${CYAN}=== AI Service Management ===${NC}"
    echo
    
    # Categorize services
    local llm_services=""
    local image_services=""
    local training_services=""
    local support_services=""
    
    for service in "${!SERVICE_INFO[@]}"; do
        IFS='|' read -r name desc category <<< "${SERVICE_INFO[$service]}"
        case $category in
            "llm") llm_services+="$service " ;;
            "image") image_services+="$service " ;;
            "training") training_services+="$service " ;;
            "support") support_services+="$service " ;;
        esac
    done
    
    # Display by category
    echo -e "${BOLD}LLM Services:${NC}"
    for service in $llm_services; do
        display_service_status "$service"
    done
    
    echo -e "\n${BOLD}Image Generation:${NC}"
    for service in $image_services; do
        display_service_status "$service"
    done
    
    echo -e "\n${BOLD}Training Tools:${NC}"
    for service in $training_services; do
        display_service_status "$service"
    done
    
    echo -e "\n${BOLD}Support Services:${NC}"
    for service in $support_services; do
        display_service_status "$service"
    done
    
    echo
    echo "Options:"
    echo "1) Quick setup (LocalAI + Ollama + Forge + Dashboard)"
    echo "2) Add services"
    echo "3) Remove services"
    echo "4) Update existing services"
    echo "5) Custom selection"
    
    read -p "Enter choice [1-5]: " choice
    
    case $choice in
        1) SELECTED_SERVICES="localai ollama forge dashboard dcgm" ;;
        2) select_services_to_add ;;
        3) select_services_to_remove ;;
        4) update_existing_services ;;
        5) custom_service_selection ;;
    esac
}

# Display service status
display_service_status() {
    local service=$1
    IFS='|' read -r name desc category <<< "${SERVICE_INFO[$service]}"
    
    local status="[ ]"
    local color=$NC
    
    # Check if deployed
    if [[ " $DEPLOYED_SERVICES " =~ " $service " ]]; then
        # Check if running
        if docker ps -q -f name="^${service}$" | grep -q .; then
            status="[✓]"
            color=$GREEN
        else
            status="[○]"
            color=$YELLOW
        fi
    fi
    
    printf "${color}%-12s %-25s${NC} - %s\n" "$status $service" "$name" "$desc"
}

# Add new services
select_services_to_add() {
    echo
    echo "Select services to ADD:"
    
    local available_services=""
    for service in "${!SERVICE_INFO[@]}"; do
        if [[ ! " $DEPLOYED_SERVICES " =~ " $service " ]]; then
            available_services+="$service "
        fi
    done
    
    if [[ -z "$available_services" ]]; then
        warn "All services are already deployed!"
        return
    fi
    
    # Show available services
    local i=1
    local service_array=($available_services)
    for service in "${service_array[@]}"; do
        IFS='|' read -r name desc category <<< "${SERVICE_INFO[$service]}"
        echo "$i) $service - $name: $desc"
        ((i++))
    done
    
    read -p "Enter numbers to add (space-separated): " selections
    
    SELECTED_SERVICES="$DEPLOYED_SERVICES"
    for num in $selections; do
        if [[ $num -ge 1 ]] && [[ $num -le ${#service_array[@]} ]]; then
            SELECTED_SERVICES+=" ${service_array[$((num-1))]}"
        fi
    done
}

# Remove existing services
select_services_to_remove() {
    if [[ -z "$DEPLOYED_SERVICES" ]]; then
        warn "No services are currently deployed!"
        return
    fi
    
    echo
    echo "Select services to REMOVE:"
    
    local i=1
    local service_array=($DEPLOYED_SERVICES)
    for service in "${service_array[@]}"; do
        IFS='|' read -r name desc category <<< "${SERVICE_INFO[$service]}"
        echo "$i) $service - $name"
        ((i++))
    done
    
    read -p "Enter numbers to remove (space-separated): " selections
    
    local services_to_remove=""
    for num in $selections; do
        if [[ $num -ge 1 ]] && [[ $num -le ${#service_array[@]} ]]; then
            services_to_remove+="${service_array[$((num-1))]} "
        fi
    done
    
    # Remove from deployed list
    SELECTED_SERVICES=""
    for service in $DEPLOYED_SERVICES; do
        if [[ ! " $services_to_remove " =~ " $service " ]]; then
            SELECTED_SERVICES+="$service "
        fi
    done
    
    # Stop and remove containers
    for service in $services_to_remove; do
        log "Removing $service..."
        docker stop "$service" 2>/dev/null || true
        docker rm "$service" 2>/dev/null || true
        remove_service_directories "$service"
    done
}

# Generate dynamic docker-compose
generate_dynamic_docker_compose() {
    log "Generating docker-compose.yml..."
    
    cat > "/opt/ai-box/docker-compose.yml" << 'EOF'
# AI Box Dynamic Docker Compose
# Generated by setup.sh

services:
EOF

    # Add each selected service
    for service in $SELECTED_SERVICES; do
        add_service_to_compose "$service"
    done
    
    # Add networks and volumes
    cat >> "/opt/ai-box/docker-compose.yml" << 'EOF'

networks:
  ai-network:
    driver: bridge
    name: ai-network
    ipam:
      config:
        - subnet: 172.20.0.0/16

volumes:
EOF

    # Add named volumes - collect unique volumes first
    local unique_volumes=()
    for service in $SELECTED_SERVICES; do
        local volumes="${SERVICE_VOLUMES[$service]}"
        if [[ -n "$volumes" ]]; then
            IFS=';' read -ra VOLUME_ARRAY <<< "$volumes"
            for volume in "${VOLUME_ARRAY[@]}"; do
                local vol_name="${volume%%:*}"
                # Only process true named volumes (single word, no slashes)
                if [[ "$vol_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    local vol_key="${vol_name}-data"
                    # Add to array if not already present
                    if [[ ! " ${unique_volumes[@]} " =~ " ${vol_key} " ]]; then
                        unique_volumes+=("$vol_key")
                    fi
                fi
            done
        fi
    done
    
    # Write unique volumes to compose file
    for vol in "${unique_volumes[@]}"; do
        echo "  $vol:" >> "/opt/ai-box/docker-compose.yml"
        echo "    driver: local" >> "/opt/ai-box/docker-compose.yml"
    done
}

# Add service to docker-compose
add_service_to_compose() {
    local service=$1
    local image="${SERVICE_IMAGES[$service]}"
    local port="${SERVICE_PORTS[$service]}"
    local volumes="${SERVICE_VOLUMES[$service]}"
    local env="${SERVICE_ENV[$service]}"
    local gpus="${service^^}_GPUS"  # e.g., LOCALAI_GPUS
    local port_var="${service^^}_PORT"  # e.g., LOCALAI_PORT
    
    cat >> "/opt/ai-box/docker-compose.yml" << EOF
  $service:
    image: $image
    container_name: $service
    ports:
      - "${!port_var:-$port}:$port"
EOF

    # Add volumes
    if [[ -n "$volumes" ]]; then
        echo "    volumes:" >> "/opt/ai-box/docker-compose.yml"
        IFS=';' read -ra VOLUME_ARRAY <<< "$volumes"
        for volume in "${VOLUME_ARRAY[@]}"; do
            local host_path="${volume%%:*}"
            local container_path="${volume#*:}"
            
            # Convert relative to absolute paths
            if [[ ! "$host_path" =~ ^/ ]]; then
                host_path="/opt/ai-box/$host_path"
            fi
            
            echo "      - $host_path:$container_path" >> "/opt/ai-box/docker-compose.yml"
        done
    fi
    
    # Add environment
    if [[ -n "$env" ]]; then
        echo "    environment:" >> "/opt/ai-box/docker-compose.yml"
        IFS=';' read -ra ENV_ARRAY <<< "$env"
        for env_var in "${ENV_ARRAY[@]}"; do
            echo "      - $env_var" >> "/opt/ai-box/docker-compose.yml"
        done
        
        # Add GPU assignment
        if [[ -n "${!gpus+x}" ]] && [[ -n "${!gpus}" ]]; then
            echo "      - CUDA_VISIBLE_DEVICES=${!gpus}" >> "/opt/ai-box/docker-compose.yml"
        fi
    fi
    
    # Add GPU deployment
    if [[ "$service" != "dashboard" ]] && [[ -n "${!gpus+x}" ]] && [[ -n "${!gpus}" ]]; then
        cat >> "/opt/ai-box/docker-compose.yml" << EOF
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: [$(echo ${!gpus} | sed "s/,/','/g" | sed "s/^/'/" | sed "s/$/'/")]
              capabilities: [gpu]
EOF
    fi
    
    # Common settings
    cat >> "/opt/ai-box/docker-compose.yml" << EOF
    restart: unless-stopped
    networks:
      - ai-network

EOF
}

# Port management
check_and_assign_ports() {
    log "Checking port availability..."
    
    for service in $SELECTED_SERVICES; do
        local default_port="${SERVICE_PORTS[$service]}"
        local port_var="${service^^}_PORT"
        
        # Check if port is in use
        if lsof -i:$default_port &> /dev/null; then
            warn "Port $default_port is in use!"
            read -p "Enter alternative port for $service: " alt_port
            eval "$port_var=$alt_port"
        else
            eval "$port_var=$default_port"
        fi
    done
}

# Load GPU assignments from existing containers
load_existing_gpu_assignments() {
    for service in $DEPLOYED_SERVICES; do
        if [[ "$service" == "dashboard" ]] || [[ "$service" == "dcgm" ]]; then
            continue  # Skip non-GPU services
        fi
        
        local gpu_var="${service^^}_GPUS"
        
        # Try to get GPU assignment from running container
        if docker ps -q -f name="^${service}$" | grep -q .; then
            local gpu_devices=$(docker inspect "$service" 2>/dev/null | jq -r '.[0].HostConfig.DeviceRequests[0].DeviceIDs[]' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
            if [[ -n "$gpu_devices" ]]; then
                eval "$gpu_var=\"$gpu_devices\""
                log "Loaded GPU assignment for $service: $gpu_devices"
            fi
        fi
    done
}

# GPU assignment for selected services
assign_gpus_to_services() {
    echo
    echo -e "${BOLD}GPU Assignment${NC}"
    echo "Detected GPUs: $GPU_COUNT"
    
    # First load existing assignments
    load_existing_gpu_assignments
    
    # Smart defaults
    local gpu_per_service=$((GPU_COUNT / $(echo $SELECTED_SERVICES | wc -w)))
    local gpu_index=0
    
    for service in $SELECTED_SERVICES; do
        if [[ "$service" == "dashboard" ]] || [[ "$service" == "dcgm" ]]; then
            continue  # Skip non-GPU services
        fi
        
        local gpu_var="${service^^}_GPUS"
        
        # Skip if already assigned (from existing container)
        if [[ -n "${!gpu_var+x}" ]] && [[ -n "${!gpu_var}" ]]; then
            echo "Using existing GPU assignment for $service: ${!gpu_var}"
            continue
        fi
        
        # Suggest GPUs
        local suggested_gpus=""
        if [[ $gpu_per_service -gt 0 ]]; then
            for ((i=0; i<$gpu_per_service; i++)); do
                if [[ $gpu_index -lt $GPU_COUNT ]]; then
                    suggested_gpus+="$gpu_index,"
                    ((gpu_index++))
                fi
            done
            suggested_gpus=${suggested_gpus%,}  # Remove trailing comma
        else
            suggested_gpus="0"  # Default to first GPU
        fi
        
        read -p "GPUs for $service (default: $suggested_gpus): " gpus
        gpus=${gpus:-$suggested_gpus}
        
        # Validate GPU assignment
        IFS=',' read -ra GPU_ARRAY <<< "$gpus"
        local valid_assignment=true
        for gpu_id in "${GPU_ARRAY[@]}"; do
            if ! [[ "$gpu_id" =~ ^[0-9]+$ ]] || [[ $gpu_id -ge $GPU_COUNT ]]; then
                error "Invalid GPU ID: $gpu_id (must be 0-$((GPU_COUNT-1)))"
                valid_assignment=false
                break
            fi
        done
        
        if [[ "$valid_assignment" == "false" ]]; then
            warn "Using default GPU assignment: $suggested_gpus"
            eval "$gpu_var=$suggested_gpus"
        else
            eval "$gpu_var=$gpus"
        fi
    done
}

# Main execution flow
main() {
    print_banner
    check_system_requirements
    load_deployed_services
    
    # Show current state
    if [[ -n "$DEPLOYED_SERVICES" ]]; then
        echo
        echo -e "${BOLD}Current Deployment:${NC}"
        for service in $DEPLOYED_SERVICES; do
            if docker ps -q -f name="^${service}$" | grep -q .; then
                echo -e "  ${GREEN}✓${NC} $service - Running"
            else
                echo -e "  ${YELLOW}○${NC} $service - Stopped"
            fi
        done
    fi
    
    # Check for orphaned containers (exist but not in deployed list)
    echo
    log "Checking for orphaned containers..."
    local orphaned_services=""
    for service in "${!SERVICE_INFO[@]}"; do
        if check_existing_container "$service" && [[ ! " $DEPLOYED_SERVICES " =~ " $service " ]]; then
            orphaned_services+="$service "
        fi
    done
    
    if [[ -n "$orphaned_services" ]]; then
        warn "Found orphaned containers: $orphaned_services"
        echo "These containers exist but are not tracked in the deployment state."
        read -p "Add them to the deployment state? [y/N]: " add_orphans
        
        if [[ "$add_orphans" =~ ^[Yy]$ ]]; then
            DEPLOYED_SERVICES+=" $orphaned_services"
            save_deployed_services "$DEPLOYED_SERVICES"
            log "Added orphaned containers to deployment state"
        fi
    fi
    
    # Service management
    prompt_service_management
    
    # GPU detection and assignment
    detect_gpus
    assign_gpus_to_services
    
    # Port management
    check_and_assign_ports
    
    # Process each selected service
    FINAL_SERVICES=""
    for service in $SELECTED_SERVICES; do
        # Check if service already exists (container or in deployed list)
        if [[ ! " $DEPLOYED_SERVICES " =~ " $service " ]]; then
            # New service - check if container exists from previous run
            if handle_existing_service "$service"; then
                create_service_directories "$service"
                FINAL_SERVICES+="$service "
            else
                # Service was skipped but exists - still include it if it's running
                if check_existing_container "$service"; then
                    FINAL_SERVICES+="$service "
                fi
            fi
        else
            # Service is in deployed list - keep it
            FINAL_SERVICES+="$service "
        fi
    done
    
    # Update selected services to only include those we're keeping
    SELECTED_SERVICES="${FINAL_SERVICES% }"
    
    # Generate configuration
    generate_dynamic_docker_compose
    save_deployed_services "$SELECTED_SERVICES"
    
    # Deploy
    cd /opt/ai-box
    log "Starting services..."
    
    if ! docker compose up -d 2>&1 | tee /tmp/docker-compose.log; then
        error "Failed to start services!"
        echo "Check the log at /tmp/docker-compose.log for details"
        echo
        echo "Common issues:"
        echo "- Port conflicts: Check if ports are already in use"
        echo "- GPU conflicts: Verify GPU assignments"
        echo "- Out of memory: Check available system memory"
        exit 1
    fi
    
    # Verify services are starting
    log "Verifying services..."
    sleep 5
    local failed_services=""
    for service in $SELECTED_SERVICES; do
        if ! docker ps | grep -q "$service"; then
            failed_services+="$service "
        fi
    done
    
    if [[ -n "$failed_services" ]]; then
        warn "Some services may not have started properly: $failed_services"
        echo "Check logs with: docker logs [service-name]"
    fi
    
    # Show results
    show_deployment_summary
}

# Show deployment summary
show_deployment_summary() {
    echo
    success "Deployment Complete!"
    echo
    echo -e "${BOLD}Active Services:${NC}"
    
    for service in $SELECTED_SERVICES; do
        local port_var="${service^^}_PORT"
        local port="${!port_var}"
        IFS='|' read -r name desc category <<< "${SERVICE_INFO[$service]}"
        
        echo -e "\n${GREEN}$name${NC}"
        echo "  URL: http://${TARGET_HOST:-localhost}:$port"
        
        # Service-specific instructions
        case $service in
            "ollama")
                echo "  CLI: docker exec $service ollama run llama2"
                ;;
            "localai")
                echo "  API: http://${TARGET_HOST:-localhost}:$port/v1/completions"
                ;;
            "comfyui")
                echo "  Manager: http://${TARGET_HOST:-localhost}:$port/manager"
                ;;
        esac
    done
    
    echo
    echo -e "${BOLD}Management Commands:${NC}"
    echo "  View logs: docker logs [service-name]"
    echo "  Restart: docker restart [service-name]"
    echo "  Stop: docker stop [service-name]"
    echo "  Add/Remove services: ./setup.sh"
}

# Signal handling for clean exit
trap 'echo -e "\n${YELLOW}Setup interrupted. Run again to continue.${NC}"; exit 130' INT TERM

# Entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
