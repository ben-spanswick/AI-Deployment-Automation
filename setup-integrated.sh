#!/bin/bash
# AI Box - Unified GPU-Accelerated AI Services Platform
# setup.sh - Dynamic service deployment and management with integrated CUDA fixes
# Version: 2.1.0

set -euo pipefail

# Verbose mode flag
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -v, --verbose    Enable verbose output"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

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
declare -A SERVICE_CUDA_FIX  # New: CUDA fix requirements

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

# n8n - Workflow automation with secure cookie fix
SERVICE_INFO["n8n"]="n8n|Workflow automation for AI chains|automation"
SERVICE_PORTS["n8n"]="5678"
SERVICE_IMAGES["n8n"]="n8nio/n8n:latest"
SERVICE_VOLUMES["n8n"]="n8n:/home/node/.n8n"
SERVICE_ENV["n8n"]="N8N_SECURE_COOKIE=false;N8N_HOST=0.0.0.0;N8N_PORT=5678;NODE_ENV=production"

# Whisper - Speech to text
SERVICE_INFO["whisper"]="Whisper|OpenAI speech-to-text|audio"
SERVICE_PORTS["whisper"]="9000"
SERVICE_IMAGES["whisper"]="onerahmet/openai-whisper-asr-webservice:latest-gpu"
SERVICE_VOLUMES["whisper"]="whisper/models:/app/models"
SERVICE_ENV["whisper"]="ASR_MODEL=base;ASR_ENGINE=openai_whisper"

# Image Generation Services with CUDA fixes
SERVICE_INFO["forge"]="SD Forge|Optimized Stable Diffusion WebUI|image"
SERVICE_PORTS["forge"]="7860"
SERVICE_IMAGES["forge"]="nykk3/stable-diffusion-webui-forge:latest"
SERVICE_VOLUMES["forge"]="models/stable-diffusion:/app/stable-diffusion-webui/models/Stable-diffusion;models/loras:/app/stable-diffusion-webui/models/Lora;models/vae:/app/stable-diffusion-webui/models/VAE;outputs/forge:/app/stable-diffusion-webui/outputs;forge-extensions:/app/stable-diffusion-webui/extensions"
SERVICE_ENV["forge"]="COMMANDLINE_ARGS=--listen --api --xformers --medvram --skip-torch-cuda-test --skip-version-check --no-download-sd-model;LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/compat:\$LD_LIBRARY_PATH;CUDA_HOME=/usr/local/cuda;PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512;TORCH_CUDA_ARCH_LIST=8.6\;8.9;CUDA_MODULE_LOADING=LAZY"
SERVICE_CUDA_FIX["forge"]="12.1"  # Requires CUDA 12.1 libraries

SERVICE_INFO["comfyui"]="ComfyUI|Node-based workflow (FLUX support!)|image"
SERVICE_PORTS["comfyui"]="8188"
SERVICE_IMAGES["comfyui"]="yanwk/comfyui-boot:cu121"  # Use CUDA 12.1 specific image
SERVICE_VOLUMES["comfyui"]="comfyui:/home/runner;models:/home/runner/models;outputs/comfyui:/home/runner/output"
SERVICE_ENV["comfyui"]="CLI_ARGS=--listen"
SERVICE_CUDA_FIX["comfyui"]="image"  # Uses CUDA-specific image

# Support Services
SERVICE_INFO["dcgm"]="DCGM Exporter|NVIDIA GPU metrics|support"
SERVICE_PORTS["dcgm"]="9400"
SERVICE_IMAGES["dcgm"]="nvcr.io/nvidia/k8s/dcgm-exporter:3.1.8-3.1.5-ubuntu20.04"
SERVICE_VOLUMES["dcgm"]=""
SERVICE_ENV["dcgm"]="DCGM_EXPORTER_LISTEN=0.0.0.0:9400;DCGM_EXPORTER_KUBERNETES=false"

SERVICE_INFO["dashboard"]="Web Dashboard|Unified control panel|support"
SERVICE_PORTS["dashboard"]="80"
SERVICE_IMAGES["dashboard"]="nginx:alpine"
SERVICE_VOLUMES["dashboard"]="nginx/html:/usr/share/nginx/html:ro;nginx/nginx.conf:/etc/nginx/nginx.conf:ro"
SERVICE_ENV["dashboard"]=""

# Functions
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check CUDA version and compatibility
check_cuda_compatibility() {
    local cuda_driver_version=""
    local cuda_toolkit_version=""
    local has_cuda_12_1=false
    
    # Get CUDA driver version from nvidia-smi
    if command -v nvidia-smi &> /dev/null; then
        cuda_driver_version=$(nvidia-smi | grep "CUDA Version" | awk '{print $9}')
        log "CUDA driver version: $cuda_driver_version"
    fi
    
    # Check for nvcc version
    if command -v nvcc &> /dev/null; then
        cuda_toolkit_version=$(nvcc --version | grep "release" | awk '{print $5}' | cut -d',' -f1)
        log "CUDA toolkit version: $cuda_toolkit_version"
    fi
    
    # Check if CUDA 12.1 is installed
    if [[ -d "/usr/local/cuda-12.1" ]]; then
        has_cuda_12_1=true
        log "CUDA 12.1 toolkit found at /usr/local/cuda-12.1"
    fi
    
    # Handle CUDA version requirements for services
    for service in $SELECTED_SERVICES; do
        local cuda_req="${SERVICE_CUDA_FIX[$service]:-}"
        
        if [[ "$cuda_req" == "12.1" ]] && [[ "$has_cuda_12_1" != "true" ]]; then
            warn "Service $service requires CUDA 12.1 but it's not installed"
            warn "The service will use compatibility mode with mounted CUDA libraries"
        fi
    done
    
    echo "$has_cuda_12_1"
}

# Create directories with proper permissions
create_directories() {
    log "Creating directory structure..."
    
    # Create all necessary directories
    mkdir -p "$INSTALL_DIR"/{models,outputs,comfyui,nginx/html,data}
    mkdir -p "$INSTALL_DIR"/models/{stable-diffusion,loras,vae,embeddings}
    mkdir -p "$INSTALL_DIR"/outputs/{forge,comfyui}
    mkdir -p "$INSTALL_DIR"/{forge-extensions,comfyui/custom_nodes}
    
    # Set permissions for output directories (allows containers to write)
    chmod -R 777 "$INSTALL_DIR"/outputs 2>/dev/null || true
    chmod -R 777 "$INSTALL_DIR"/comfyui 2>/dev/null || true
    
    success "Directory structure created"
}

# Generate dynamic docker-compose with CUDA fixes
generate_dynamic_docker_compose() {
    log "Generating docker-compose.yml with CUDA fixes..."
    
    local has_cuda_12_1=$(check_cuda_compatibility)
    
    cat > "/opt/ai-box/docker-compose.yml" << 'EOF'
# AI Box Dynamic Docker Compose with CUDA Fixes
# Generated by setup.sh v2.1.0

services:
EOF

    # Add each selected service
    for service in $SELECTED_SERVICES; do
        add_service_to_compose "$service" "$has_cuda_12_1"
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

    # Add named volumes
    local unique_volumes=()
    for service in $SELECTED_SERVICES; do
        local volumes="${SERVICE_VOLUMES[$service]}"
        if [[ -n "$volumes" ]]; then
            IFS=';' read -ra VOLUME_ARRAY <<< "$volumes"
            for volume in "${VOLUME_ARRAY[@]}"; do
                local vol_name="${volume%%:*}"
                if [[ "$vol_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    local vol_key="${vol_name}-data"
                    if [[ ! " ${unique_volumes[@]} " =~ " ${vol_key} " ]]; then
                        unique_volumes+=("$vol_key")
                    fi
                fi
            done
        fi
    done
    
    for vol in "${unique_volumes[@]}"; do
        echo "  $vol:" >> "/opt/ai-box/docker-compose.yml"
        echo "    driver: local" >> "/opt/ai-box/docker-compose.yml"
    done
}

# Add service to docker-compose with CUDA fixes
add_service_to_compose() {
    local service=$1
    local has_cuda_12_1=$2
    local image="${SERVICE_IMAGES[$service]}"
    local port="${SERVICE_PORTS[$service]}"
    local volumes="${SERVICE_VOLUMES[$service]}"
    local env="${SERVICE_ENV[$service]}"
    local gpus="${service^^}_GPUS"
    local port_var="${service^^}_PORT"
    local cuda_fix="${SERVICE_CUDA_FIX[$service]:-}"
    
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
            
            if [[ ! "$host_path" =~ ^/ ]]; then
                host_path="/opt/ai-box/$host_path"
            fi
            
            echo "      - $host_path:$container_path" >> "/opt/ai-box/docker-compose.yml"
        done
        
        # Add CUDA 12.1 library mounts for Forge
        if [[ "$service" == "forge" ]] && [[ "$has_cuda_12_1" == "true" ]]; then
            echo "      # CUDA 12.1 compatibility libraries" >> "/opt/ai-box/docker-compose.yml"
            echo "      - /usr/local/cuda-12.1/lib64:/usr/local/cuda/lib64:ro" >> "/opt/ai-box/docker-compose.yml"
            echo "      - /usr/local/cuda-12.1/compat:/usr/local/cuda/compat:ro" >> "/opt/ai-box/docker-compose.yml"
        fi
    fi
    
    # Add environment
    if [[ -n "$env" ]]; then
        echo "    environment:" >> "/opt/ai-box/docker-compose.yml"
        IFS=';' read -ra ENV_ARRAY <<< "$env"
        for env_var in "${ENV_ARRAY[@]}"; do
            echo "      - $env_var" >> "/opt/ai-box/docker-compose.yml"
        done
        
        # Add GPU environment if assigned
        if [[ -n "${!gpus:-}" ]]; then
            echo "      - CUDA_VISIBLE_DEVICES=${!gpus}" >> "/opt/ai-box/docker-compose.yml"
        fi
    fi
    
    # Add GPU deployment
    if [[ -n "${!gpus:-}" ]]; then
        cat >> "/opt/ai-box/docker-compose.yml" << EOF
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: [${!gpus//,/\',\'} ]
              capabilities: [gpu]
EOF
    fi
    
    # Add service-specific configurations
    if [[ "$service" == "forge" ]] || [[ "$service" == "comfyui" ]]; then
        echo "    shm_size: 8gb" >> "/opt/ai-box/docker-compose.yml"
    fi
    
    cat >> "/opt/ai-box/docker-compose.yml" << EOF
    restart: unless-stopped
    networks:
      - ai-network

EOF
}

# Post-installation message with CUDA notes
print_post_install_message() {
    echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        Installation Complete!              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}Service URLs:${NC}"
    
    for service in $SELECTED_SERVICES; do
        local port_var="${service^^}_PORT"
        local port="${!port_var:-${SERVICE_PORTS[$service]}}"
        local info="${SERVICE_INFO[$service]}"
        local name="${info%%|*}"
        echo -e "  $name: ${CYAN}http://localhost:$port${NC}"
    done
    
    echo
    echo -e "${YELLOW}Important Notes:${NC}"
    echo -e "- SD Forge and ComfyUI will run without models but show errors when generating"
    echo -e "- To download models (optional):"
    echo -e "  ${BLUE}wget -c https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors \\${NC}"
    echo -e "  ${BLUE}  -O /opt/ai-box/models/stable-diffusion/sd-v1-5.safetensors${NC}"
    echo
    echo -e "- CUDA compatibility fixes have been applied automatically"
    echo -e "- For troubleshooting, check: ${BLUE}docker logs <service-name>${NC}"
    echo
}

# Main execution flow would continue here...
# This is a partial example showing the key integration points