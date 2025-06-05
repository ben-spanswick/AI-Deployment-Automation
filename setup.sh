#!/bin/bash
# AI Box - Unified GPU-Accelerated AI Services Platform
# setup.sh - Dynamic service deployment and management
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

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Verbose logging function
vlog() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [VERBOSE] $*" | tee -a "$LOG_FILE"
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [VERBOSE] $*" >> "$LOG_FILE"
    fi
}

# Progress bar function
show_progress() {
    if [[ "$VERBOSE" != "true" ]]; then
        local current=$1
        local total=$2
        local width=50
        local percentage=$((current * 100 / total))
        local completed=$((width * current / total))
        
        printf "\r[%-${width}s] %d%%" \
            "$(printf '#%.0s' $(seq 1 $completed))" \
            "$percentage"
        
        if [[ $current -eq $total ]]; then
            echo
        fi
    fi
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
SERVICE_ENV["n8n"]="N8N_SECURE_COOKIE=false;N8N_HOST=0.0.0.0;N8N_PORT=5678;NODE_ENV=production;WEBHOOK_URL=http://localhost:5678/"
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
# SD Forge recommended image - CUDA 12.1 + PyTorch 2.3.1
SERVICE_IMAGES["forge"]="nykk3/stable-diffusion-webui-forge:latest"
SERVICE_VOLUMES["forge"]="models/stable-diffusion:/app/stable-diffusion-webui/models/Stable-diffusion;models/loras:/app/stable-diffusion-webui/models/Lora;models/vae:/app/stable-diffusion-webui/models/VAE;outputs/forge:/app/stable-diffusion-webui/outputs"
SERVICE_ENV["forge"]="COMMANDLINE_ARGS=--listen --api --xformers --medvram --skip-torch-cuda-test --skip-version-check --no-download-sd-model"

SERVICE_INFO["comfyui"]="ComfyUI|Node-based workflow (FLUX support!)|image"
SERVICE_PORTS["comfyui"]="8188"
SERVICE_IMAGES["comfyui"]="yanwk/comfyui-boot:cu121"
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

# Display Functions (overriding the logging functions for colored output)
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Print banner
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════╗"
    echo "║        AI Box Modular Setup v2.1           ║"
    echo "║     Dynamic Service Management System       ║"
    echo "╚════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Get actual user (works with or without sudo)
get_actual_user() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        echo "$SUDO_USER"
    else
        echo "$USER"
    fi
}

# Run command as actual user
run_as_user() {
    local actual_user=$(get_actual_user)
    if [[ $EUID -eq 0 ]] && [[ "$actual_user" != "root" ]]; then
        sudo -u "$actual_user" "$@"
    else
        "$@"
    fi
}

# Install NVIDIA drivers if needed
install_nvidia_drivers_if_needed() {
    if ! command -v nvidia-smi &> /dev/null; then
        warn "NVIDIA drivers not found. Installing NVIDIA drivers..."
        
        # Update package list
        apt-get update
        
        # Install required packages for driver installation
        apt-get install -y \
            software-properties-common \
            build-essential \
            linux-headers-$(uname -r) \
            ubuntu-drivers-common
        
        # Detect recommended driver
        log "Detecting recommended NVIDIA driver..."
        local recommended_driver=$(ubuntu-drivers devices | grep recommended | awk '{print $3}')
        
        if [[ -n "$recommended_driver" ]]; then
            log "Installing recommended driver: $recommended_driver"
            apt-get install -y "$recommended_driver"
        else
            # Fallback to latest driver
            log "No recommended driver found, installing latest available driver..."
            add-apt-repository -y ppa:graphics-drivers/ppa
            apt-get update
            
            # Get latest driver version
            local latest_driver=$(apt-cache search nvidia-driver | grep -E "^nvidia-driver-[0-9]+" | sort -V | tail -n1 | awk '{print $1}')
            if [[ -n "$latest_driver" ]]; then
                log "Installing $latest_driver"
                apt-get install -y "$latest_driver"
            else
                error "Could not determine NVIDIA driver to install"
                exit 1
            fi
        fi
        
        # Install CUDA support packages
        apt-get install -y nvidia-cuda-toolkit nvidia-cuda-dev
        
        # Enable persistence mode
        nvidia-smi -pm 1 || true
        
        success "NVIDIA drivers installed successfully!"
        
        # Set flag to indicate fresh install
        NVIDIA_FRESH_INSTALL=true
        
        # Prompt for reboot
        warn "NVIDIA drivers have been installed. A system reboot is required."
        read -p "Would you like to reboot now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Rebooting system..."
            reboot
        else
            warn "Please reboot the system manually to complete NVIDIA driver installation."
            echo "After reboot, run this script again: sudo ./setup.sh"
            exit 0
        fi
    else
        log "NVIDIA drivers already installed"
        nvidia-smi --query-gpu=driver_version,name --format=csv,noheader | while IFS=',' read -r version name; do
            log "  GPU: $name, Driver: $version"
        done
        
        # Display CUDA version
        local cuda_version=$(nvidia-smi | grep "CUDA Version" | sed -n 's/.*CUDA Version: \([0-9]*\.[0-9]*\).*/\1/p')
        if [[ -n "$cuda_version" ]]; then
            log "  CUDA Version: $cuda_version"
        fi
        
        # Check for CUDA toolkit installation
        if [[ -d "/usr/local/cuda" ]]; then
            local cuda_toolkit_version=$(cat /usr/local/cuda/version.txt 2>/dev/null | grep "CUDA Version" | awk '{print $3}' || echo "unknown")
            if [[ "$cuda_toolkit_version" != "unknown" ]]; then
                log "  CUDA Toolkit: $cuda_toolkit_version (at $(readlink -f /usr/local/cuda))"
            else
                # Try alternative method
                local cuda_link=$(readlink -f /usr/local/cuda)
                if [[ "$cuda_link" =~ cuda-([0-9]+\.[0-9]+) ]]; then
                    log "  CUDA Toolkit: ${BASH_REMATCH[1]} (at $cuda_link)"
                fi
            fi
        fi
    fi
}

# Install Docker if needed
install_docker_if_needed() {
    if ! command -v docker &> /dev/null; then
        warn "Docker is not installed. Installing Docker and NVIDIA Container Toolkit..."
        
        # Install prerequisites
        apt-get update
        apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release \
            software-properties-common
        
        # Add Docker's official GPG key
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        
        # Add Docker repository
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        # Start and enable Docker
        systemctl start docker
        systemctl enable docker
        
        # Add user to docker group
        local actual_user=$(get_actual_user)
        usermod -aG docker "$actual_user"
        
        # Install NVIDIA Container Toolkit
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /etc/apt/keyrings/nvidia-container-toolkit.gpg
        chmod a+r /etc/apt/keyrings/nvidia-container-toolkit.gpg
        
        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
          sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#g' | \
          tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        
        apt-get update
        apt-get install -y nvidia-container-toolkit
        
        # Configure Docker for GPU support
        nvidia-ctk runtime configure --runtime=docker
        systemctl restart docker
        
        success "Docker installed successfully!"
        
        # Set flag to indicate fresh install
        DOCKER_FRESH_INSTALL=true
    fi
}

# Check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check if we need sudo
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run with sudo"
        echo "Usage: sudo ./setup.sh"
        exit 1
    fi
    
    # Get actual user
    ACTUAL_USER=$(get_actual_user)
    if [[ "$ACTUAL_USER" == "root" ]]; then
        error "Please run this script with sudo as a normal user, not as root directly"
        echo "Usage: sudo ./setup.sh"
        exit 1
    fi
    
    log "Running as root, actual user is: $ACTUAL_USER"
    
    # Install Docker if needed
    install_docker_if_needed
    
    # Check if user is in docker group (or just added)
    if ! groups "$ACTUAL_USER" | grep -q docker && [[ -z "${DOCKER_FRESH_INSTALL:-}" ]]; then
        error "User $ACTUAL_USER is not in the docker group"
        echo "Adding user to docker group..."
        usermod -aG docker "$ACTUAL_USER"
    fi
    
    # Install NVIDIA drivers if needed
    install_nvidia_drivers_if_needed
    
    # Check NVIDIA Container Toolkit
    if ! run_as_user docker run --rm --gpus all nvidia/cuda:12.9-base-ubuntu22.04 nvidia-smi &> /dev/null; then
        warn "NVIDIA Container Toolkit test failed - this may be normal on fresh install"
        # Don't exit on fresh install or if NVIDIA drivers were just installed
        if [[ -z "${DOCKER_FRESH_INSTALL:-}" ]] && [[ -z "${NVIDIA_FRESH_INSTALL:-}" ]]; then
            error "NVIDIA Container Toolkit not working properly"
            exit 1
        fi
        warn "GPU support may require a reboot or re-login to work properly"
    fi
    
    # Check disk space (require at least 50GB free)
    local free_space=$(df -k /opt 2>/dev/null | awk 'NR==2 {print $4}' || df -k / | awk 'NR==2 {print $4}')
    local required_space=$((50 * 1024 * 1024))  # 50GB in KB
    
    # Validate that free_space is a number
    if ! [[ "$free_space" =~ ^[0-9]+$ ]]; then
        warn "Could not determine free disk space"
        # Try alternative method
        free_space=$(df -BK /opt 2>/dev/null | awk 'NR==2 {gsub(/K/, "", $4); print $4}' || df -BK / | awk 'NR==2 {gsub(/K/, "", $4); print $4}')
    fi
    
    if [[ "$free_space" =~ ^[0-9]+$ ]] && [[ $free_space -lt $required_space ]]; then
        error "Insufficient disk space. At least 50GB free space required."
        echo "Available: $(($free_space / 1024 / 1024))GB"
        exit 1
    fi
    
    # Create AI Box directory if it doesn't exist
    if [[ ! -d "/opt/ai-box" ]]; then
        mkdir -p /opt/ai-box
        chown "$ACTUAL_USER:$ACTUAL_USER" /opt/ai-box
    fi
    
    success "System requirements check passed"
}

# Install CUDA 12.1 alongside existing CUDA
install_cuda_12_1() {
    log "Installing CUDA 12.1 toolkit..."
    
    # Clean up any broken installations first
    cleanup_broken_cuda_install() {
        vlog "Checking for broken CUDA installations..."
        
        # Remove broken repository packages
        if dpkg -l | grep -q "cuda-repo-ubuntu.*-12-1-local"; then
            warn "Found broken CUDA repository package, removing..."
            sudo dpkg --purge cuda-repo-ubuntu*-12-1-local 2>/dev/null || true
        fi
        
        # Clean up all CUDA-related apt sources and keys
        sudo rm -f /usr/share/keyrings/cuda-*-keyring.gpg 2>/dev/null || true
        sudo rm -f /etc/apt/sources.list.d/cuda*.list 2>/dev/null || true
        sudo rm -f /etc/apt/preferences.d/cuda*.pin 2>/dev/null || true
        
        # Remove the local repo directory if it exists
        sudo rm -rf /var/cuda-repo-ubuntu*-12-1-local 2>/dev/null || true
        
        # Clean apt cache
        sudo apt-get clean
        sudo apt-get update 2>&1 | grep -v "NO_PUBKEY" || true
    }
    
    cleanup_broken_cuda_install
    
    # Detect Ubuntu version
    local ubuntu_version=$(lsb_release -rs | cut -d. -f1)
    local ubuntu_codename="ubuntu${ubuntu_version}04"
    
    # For Ubuntu 24+, use network installer for better compatibility
    if [[ "$ubuntu_version" -ge 24 ]]; then
        log "Ubuntu $ubuntu_version detected, downloading from NVIDIA network repository..."
        
        # Install compatibility libraries first
        log "Installing compatibility libraries..."
        sudo add-apt-repository universe -y
        sudo apt-get update
        
        # Install libtinfo5 for Ubuntu 24
        if ! dpkg -l | grep -q "libtinfo5"; then
            wget -q http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.4-2_amd64.deb
            sudo dpkg -i libtinfo5_6.4-2_amd64.deb || true
            rm -f libtinfo5_6.4-2_amd64.deb
        fi
        
        # Use network installer for Ubuntu 24+
        log "Setting up CUDA network repository..."
        wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
        sudo dpkg -i cuda-keyring_1.1-1_all.deb
        rm -f cuda-keyring_1.1-1_all.deb
        
        sudo apt-get update
        
        # Install minimal CUDA 12.1 components
        log "Installing CUDA 12.1 toolkit (minimal installation for compatibility)..."
        local cuda_packages=(
            cuda-toolkit-12-1-config-common
            cuda-toolkit-12-config-common
            cuda-cudart-12-1
            cuda-cudart-dev-12-1
            cuda-compiler-12-1
            cuda-nvcc-12-1
            cuda-libraries-12-1
            cuda-libraries-dev-12-1
            libcublas-12-1
            libcublas-dev-12-1
        )
        
        for package in "${cuda_packages[@]}"; do
            vlog "Installing $package..."
            sudo apt-get install -y --no-install-recommends "$package" 2>/dev/null || warn "Package $package failed, continuing..."
        done
        
    else
        # For Ubuntu 20.04/22.04, download and use local installer package
        if [[ "$ubuntu_version" -lt 20 ]]; then
            ubuntu_codename="ubuntu2004"
            warn "Using Ubuntu 20.04 CUDA repository for Ubuntu $ubuntu_version"
        fi
        
        # Add NVIDIA package repositories
        log "Downloading CUDA repository configuration..."
        wget -q https://developer.download.nvidia.com/compute/cuda/repos/${ubuntu_codename}/x86_64/cuda-${ubuntu_codename}.pin
        sudo mv cuda-${ubuntu_codename}.pin /etc/apt/preferences.d/cuda-repository-pin-600
        
        # Download CUDA 12.1 local installer package from NVIDIA
        local cuda_repo_pkg="cuda-repo-${ubuntu_codename}-12-1-local_12.1.0-530.30.02-1_amd64.deb"
        log "Downloading CUDA 12.1 installer package from NVIDIA (this may take a few minutes)..."
        wget -q --show-progress https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/${cuda_repo_pkg}
        
        if [[ ! -f "$cuda_repo_pkg" ]]; then
            error "Failed to download CUDA repository package"
            return 1
        fi
        
        sudo dpkg -i ${cuda_repo_pkg}
        sudo cp /var/cuda-repo-${ubuntu_codename}-12-1-local/cuda-*-keyring.gpg /usr/share/keyrings/
        sudo apt-get update -qq
        
        # Install CUDA 12.1 toolkit
        log "Installing CUDA 12.1 toolkit packages..."
        sudo apt-get install -y --no-install-recommends cuda-toolkit-12-1 || {
            warn "Some packages failed, but continuing..."
        }
        
        # Clean up
        rm -f ${cuda_repo_pkg}
    fi
    
    # Create symlink if installation succeeded
    if [[ -d "/usr/local/cuda-12.1" ]]; then
        sudo rm -f /usr/local/cuda
        sudo ln -s /usr/local/cuda-12.1 /usr/local/cuda
        log "Created /usr/local/cuda symlink"
        
        # Set up alternatives for CUDA version management
        if command -v update-alternatives &> /dev/null; then
            sudo update-alternatives --install /usr/local/cuda cuda /usr/local/cuda-12.1 121 2>/dev/null || true
        fi
    else
        error "CUDA 12.1 directory not found after installation"
        return 1
    fi
    
    # Add CUDA to PATH if not already present
    local actual_user=$(get_actual_user)
    local user_bashrc="/home/$actual_user/.bashrc"
    
    if [[ -f "$user_bashrc" ]] && ! grep -q "/usr/local/cuda/bin" "$user_bashrc"; then
        echo 'export PATH=/usr/local/cuda/bin:$PATH' >> "$user_bashrc"
        echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> "$user_bashrc"
        log "Added CUDA to PATH and LD_LIBRARY_PATH in $user_bashrc"
    fi
    
    # Verify installation
    if [[ -f "/usr/local/cuda-12.1/bin/nvcc" ]]; then
        local nvcc_version=$(/usr/local/cuda-12.1/bin/nvcc --version | grep "release" | awk '{print $5}' | sed 's/,//')
        success "CUDA 12.1 installed successfully (nvcc version: $nvcc_version)"
        log "Please run 'source ~/.bashrc' or restart your terminal to update PATH"
        return 0
    else
        warn "CUDA installation completed but nvcc not found - installation may be incomplete"
        return 1
    fi
}

# Manage CUDA version switching
manage_cuda_version() {
    echo
    echo -e "${BOLD}CUDA Version Management${NC}"
    
    # Check current driver CUDA support
    local driver_cuda=$(nvidia-smi | grep "CUDA Version" | sed -n 's/.*CUDA Version: \([0-9]*\.[0-9]*\).*/\1/p')
    if [[ -n "$driver_cuda" ]]; then
        log "NVIDIA Driver supports CUDA: $driver_cuda"
    fi
    
    # List available CUDA versions
    local cuda_versions=$(ls -d /usr/local/cuda-* 2>/dev/null | sort -V)
    if [[ -z "$cuda_versions" ]]; then
        warn "No CUDA Toolkit installations found"
        echo
        echo "Your NVIDIA driver supports CUDA $driver_cuda, but no CUDA Toolkit is installed."
        echo "The CUDA Toolkit includes development tools, libraries, and compilers needed by applications."
        echo
        echo "SD Forge requires CUDA Toolkit 12.1 for optimal performance."
        echo
        echo "Options:"
        echo "1) Install CUDA 12.1 Toolkit (recommended for SD Forge)"
        echo "2) Install latest CUDA Toolkit"
        echo "3) Fix broken CUDA installation and retry"
        echo "4) Cancel"
        echo
        read -p "Select option [1-4]: " install_choice
        
        case $install_choice in
            1)
                log "Installing CUDA 12.1 Toolkit..."
                if ! install_cuda_12_1; then
                    warn "CUDA installation failed!"
                    echo
                    echo "This might be due to broken packages or repository issues."
                    read -p "Would you like to clean up and retry? [Y/n]: " cleanup_retry
                    
                    if [[ ! "$cleanup_retry" =~ ^[Nn]$ ]]; then
                        log "Cleaning up broken CUDA installations..."
                        # Remove broken packages
                        if dpkg -l | grep -q "cuda-repo-ubuntu.*-12-1-local"; then
                            warn "Removing broken CUDA repository packages..."
                            sudo dpkg --purge cuda-repo-ubuntu*-12-1-local 2>/dev/null || true
                        fi
                        # Clean up keyrings and sources
                        sudo rm -f /usr/share/keyrings/cuda-*-keyring.gpg 2>/dev/null || true
                        sudo rm -f /etc/apt/sources.list.d/cuda*.list 2>/dev/null || true
                        sudo rm -f /etc/apt/preferences.d/cuda*.pin 2>/dev/null || true
                        sudo rm -rf /var/cuda-repo-ubuntu*-12-1-local 2>/dev/null || true
                        
                        sudo apt-get clean
                        sudo apt-get update
                        
                        success "Cleanup completed"
                        log "Returning to CUDA installation menu..."
                        sleep 2
                        # Recursively call manage_cuda_version to show the menu again
                        manage_cuda_version
                        return
                    fi
                else
                    # Create symlink if not already created
                    if [[ -d "/usr/local/cuda-12.1" ]] && [[ ! -L "/usr/local/cuda" ]]; then
                        sudo ln -s /usr/local/cuda-12.1 /usr/local/cuda
                    fi
                fi
                ;;
            2)
                log "Installing latest CUDA Toolkit..."
                # Install latest CUDA from NVIDIA repos
                apt-get update
                apt-get install -y cuda
                success "Latest CUDA Toolkit installed"
                ;;
            3)
                log "Cleaning up broken CUDA installations..."
                # Remove broken packages
                if dpkg -l | grep -q "cuda-repo-ubuntu.*-12-1-local"; then
                    warn "Removing broken CUDA repository packages..."
                    sudo dpkg --purge cuda-repo-ubuntu*-12-1-local 2>/dev/null || true
                fi
                # Clean up keyrings and sources
                sudo rm -f /usr/share/keyrings/cuda-*-keyring.gpg 2>/dev/null || true
                sudo rm -f /etc/apt/sources.list.d/cuda*.list 2>/dev/null || true
                sudo rm -f /etc/apt/preferences.d/cuda*.pin 2>/dev/null || true
                
                sudo apt-get clean
                sudo apt-get update
                
                success "Cleanup completed"
                log "Returning to CUDA installation menu..."
                sleep 2
                # Recursively call to show menu again after cleanup
                manage_cuda_version
                return
                ;;
            4)
                log "CUDA installation cancelled"
                ;;
        esac
        return
    fi
    
    echo "Available CUDA Toolkit installations:"
    echo "$cuda_versions"
    echo
    
    if [[ -L "/usr/local/cuda" ]]; then
        echo "Current CUDA symlink points to: $(readlink /usr/local/cuda)"
    else
        warn "No /usr/local/cuda symlink found"
    fi
    
    echo
    echo "Options:"
    echo "1) Switch to CUDA 12.1 (recommended for SD Forge)"
    echo "2) Switch to latest CUDA version"
    echo "3) Install CUDA 12.1 (if not present)"
    echo "4) Fix broken CUDA installation"
    echo "5) Show current configuration"
    echo "6) Cancel"
    echo
    read -p "Select option [1-6]: " cuda_mgmt_choice
    
    case $cuda_mgmt_choice in
        1)
            if [[ -d "/usr/local/cuda-12.1" ]]; then
                sudo rm -f /usr/local/cuda
                sudo ln -s /usr/local/cuda-12.1 /usr/local/cuda
                success "Switched to CUDA 12.1"
                echo "You may need to update your PATH and LD_LIBRARY_PATH"
            else
                warn "CUDA 12.1 not found. Would you like to install it?"
                read -p "Install CUDA 12.1? [y/N]: " install_cuda
                if [[ "$install_cuda" =~ ^[Yy]$ ]]; then
                    install_cuda_12_1
                    sudo ln -s /usr/local/cuda-12.1 /usr/local/cuda
                    success "CUDA 12.1 installed and activated"
                fi
            fi
            ;;
        2)
            local latest_cuda=$(ls -d /usr/local/cuda-* 2>/dev/null | sort -V | tail -n1)
            if [[ -n "$latest_cuda" ]]; then
                sudo rm -f /usr/local/cuda
                sudo ln -s "$latest_cuda" /usr/local/cuda
                success "Switched to $latest_cuda"
            else
                error "No CUDA installations found"
            fi
            ;;
        3)
            if [[ -d "/usr/local/cuda-12.1" ]]; then
                log "CUDA 12.1 is already installed at /usr/local/cuda-12.1"
            else
                install_cuda_12_1
                success "CUDA 12.1 installed successfully"
            fi
            ;;
        4)
            log "Cleaning up broken CUDA installations..."
            # Remove broken packages
            if dpkg -l | grep -q "cuda-repo-ubuntu.*-12-1-local"; then
                warn "Removing broken CUDA repository packages..."
                sudo dpkg --purge cuda-repo-ubuntu*-12-1-local 2>/dev/null || true
            fi
            # Clean up keyrings
            sudo rm -f /usr/share/keyrings/cuda-*-keyring.gpg 2>/dev/null || true
            sudo rm -f /etc/apt/sources.list.d/cuda*.list 2>/dev/null || true
            sudo rm -f /etc/apt/preferences.d/cuda*.pin 2>/dev/null || true
            
            # Update package lists
            sudo apt-get clean
            sudo apt-get update
            
            success "Cleanup completed"
            echo
            read -p "Would you like to install CUDA 12.1 now? [y/N]: " install_now
            if [[ "$install_now" =~ ^[Yy]$ ]]; then
                install_cuda_12_1
            fi
            ;;
        5)
            echo "CUDA configuration:"
            echo "==================="
            ls -la /usr/local/ | grep cuda || echo "No CUDA installations in /usr/local/"
            echo
            echo "Environment variables:"
            echo "PATH includes CUDA: $(echo $PATH | grep -q cuda && echo "Yes" || echo "No")"
            echo "LD_LIBRARY_PATH: ${LD_LIBRARY_PATH:-Not set}"
            ;;
        6)
            log "CUDA version management cancelled"
            ;;
    esac
}

# Detect GPUs
detect_gpus() {
    log "Detecting GPUs..."
    
    # Get GPU count
    GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
    
    # Extract CUDA version for SD Forge selection
    CUDA_VERSION_FULL=$(nvidia-smi | grep "CUDA Version" | sed -n 's/.*CUDA Version: \([0-9]*\.[0-9]*\).*/\1/p')
    CUDA_VERSION_MAJOR=$(echo $CUDA_VERSION_FULL | cut -d. -f1)
    CUDA_VERSION_MINOR=$(echo $CUDA_VERSION_FULL | cut -d. -f2)
    
    if [[ $GPU_COUNT -eq 0 ]]; then
        error "No GPUs detected"
        exit 1
    fi
    
    # Get GPU model (first GPU)
    GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
    
    success "Detected $GPU_COUNT GPU(s): $GPU_MODEL"
    log "CUDA Version: $CUDA_VERSION_FULL"
    
    # Save to config
    echo "GPU_COUNT=$GPU_COUNT" >> "$CONFIG_FILE"
    echo "GPU_MODEL=\"$GPU_MODEL\"" >> "$CONFIG_FILE"
    echo "CUDA_VERSION=\"$CUDA_VERSION_FULL\"" >> "$CONFIG_FILE"
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
                if [[ "$VERBOSE" == "true" ]]; then
                    log "Starting update for $service..."
                    run_as_user docker pull "$image" &
                else
                    echo -n "Updating $service... "
                    run_as_user docker pull "$image" > /dev/null 2>&1 &
                fi
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
                # Stop ALL containers on ai-network first
                echo "Stopping all AI Box services..."
                docker ps -q --filter "network=ai-network" | xargs -r docker stop
                docker ps -aq --filter "network=ai-network" | xargs -r docker rm
                
                # Also try docker-compose down if compose file exists
                if [[ -f "/opt/ai-box/docker-compose.yml" ]]; then
                    cd /opt/ai-box
                    run_as_user docker compose down || true
                fi
                run_as_user docker compose up -d
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
                # Stop ALL containers on ai-network first
                echo "Stopping all AI Box services..."
                docker ps -q --filter "network=ai-network" | xargs -r docker stop
                docker ps -aq --filter "network=ai-network" | xargs -r docker rm
                
                # Also try docker-compose down if compose file exists
                if [[ -f "/opt/ai-box/docker-compose.yml" ]]; then
                    cd /opt/ai-box
                    run_as_user docker compose down || true
                fi
                
                # Wait for containers to fully stop
                log "Waiting for services to stop..."
                sleep 3
                
                # Clear port assignments to force reconfiguration
                for service in $DEPLOYED_SERVICES; do
                    local port_var="${service^^}_PORT"
                    unset $port_var
                done
                
                # Set flag to indicate we're reconfiguring
                RECONFIGURE_MODE=true
                SELECTED_SERVICES="$DEPLOYED_SERVICES"
                
                success "Services stopped. Returning to configuration..."
                # Return to main flow instead of regenerating here
                return 0
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
    if run_as_user docker ps -a --format "{{.Names}}" | grep -q "^${service}$"; then
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
                run_as_user docker stop "$service" 2>/dev/null || true
                run_as_user docker rm "$service" 2>/dev/null || true
                return 0  # Continue with setup
                ;;
            3)
                log "Removing $service completely"
                run_as_user docker stop "$service" 2>/dev/null || true
                run_as_user docker rm "$service" 2>/dev/null || true
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
                        mkdir -p "$parent_dir"
                        chown -R "$ACTUAL_USER:$ACTUAL_USER" "$parent_dir"
                        log "Created parent directory: $parent_dir"
                    fi
                else
                    # It's a directory
                    mkdir -p "$host_path"
                    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$host_path"
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
                    rm -rf "$host_path"
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
    echo "6) Manage CUDA versions"
    
    read -p "Enter choice [1-6]: " choice
    
    case $choice in
        1) SELECTED_SERVICES="localai ollama forge dashboard dcgm" ;;
        2) select_services_to_add ;;
        3) select_services_to_remove ;;
        4) update_existing_services
           # If reconfigure mode is set, we already have SELECTED_SERVICES
           if [[ "$RECONFIGURE_MODE" == "true" ]]; then
               return
           fi
           ;;
        5) custom_service_selection ;;
        6) manage_cuda_version
           # Exit after CUDA management
           exit 0
           ;;
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
        if run_as_user docker ps -q -f name="^${service}$" | grep -q .; then
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
        run_as_user docker stop "$service" 2>/dev/null || true
        run_as_user docker rm "$service" 2>/dev/null || true
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
        
        # Add CUDA 12.1 library mounts for Forge
        if [[ "$service" == "forge" ]] && [[ -d "/usr/local/cuda-12.1" ]]; then
            echo "      # CUDA 12.1 compatibility fix" >> "/opt/ai-box/docker-compose.yml"
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
    
    # Add shm_size for GPU services
    if [[ "$service" == "forge" ]] || [[ "$service" == "comfyui" ]]; then
        echo "    shm_size: 8gb" >> "/opt/ai-box/docker-compose.yml"
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
        if run_as_user docker ps -q -f name="^${service}$" | grep -q .; then
            local gpu_devices=$(run_as_user docker inspect "$service" 2>/dev/null | jq -r '.[0].HostConfig.DeviceRequests[0].DeviceIDs[]' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
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
        
        # Suggest GPUs (show 1-based to user)
        local suggested_gpus=""
        local suggested_gpus_display=""
        if [[ $gpu_per_service -gt 0 ]]; then
            for ((i=0; i<$gpu_per_service; i++)); do
                if [[ $gpu_index -lt $GPU_COUNT ]]; then
                    suggested_gpus+="$gpu_index,"
                    suggested_gpus_display+="$((gpu_index+1)),"
                    ((gpu_index++))
                fi
            done
            suggested_gpus=${suggested_gpus%,}  # Remove trailing comma
            suggested_gpus_display=${suggested_gpus_display%,}  # Remove trailing comma
        else
            suggested_gpus="0"  # Default to first GPU
            suggested_gpus_display="1"  # Show as GPU 1 to user
        fi
        
        read -p "GPUs for $service (default: $suggested_gpus_display): " gpus
        gpus=${gpus:-$suggested_gpus_display}
        
        # Validate GPU assignment and convert from 1-based to 0-based
        IFS=',' read -ra GPU_ARRAY <<< "$gpus"
        local valid_assignment=true
        local converted_gpus=""
        
        for gpu_id in "${GPU_ARRAY[@]}"; do
            if ! [[ "$gpu_id" =~ ^[0-9]+$ ]] || [[ $gpu_id -lt 1 ]] || [[ $gpu_id -gt $GPU_COUNT ]]; then
                error "Invalid GPU ID: $gpu_id (must be 1-$GPU_COUNT)"
                valid_assignment=false
                break
            fi
            # Convert from 1-based to 0-based
            converted_gpus+="$((gpu_id-1)),"
        done
        
        converted_gpus=${converted_gpus%,}  # Remove trailing comma
        
        if [[ "$valid_assignment" == "false" ]]; then
            warn "Using default GPU assignment: $suggested_gpus_display"
            eval "$gpu_var=$suggested_gpus"
        else
            eval "$gpu_var=$converted_gpus"
        fi
    done
}

# Prompt for SD Forge CUDA version
prompt_forge_cuda_version() {
    echo
    echo -e "${BOLD}SD Forge CUDA Version Warning${NC}"
    echo "Your system has CUDA $CUDA_VERSION_MAJOR.$CUDA_VERSION_MINOR"
    echo
    echo -e "${YELLOW}IMPORTANT:${NC} SD Forge requires specific CUDA versions for stability."
    echo -e "${GREEN}Recommended:${NC} CUDA 12.1 with PyTorch 2.3.1 (last known stable configuration)"
    echo
    
    if [[ "$CUDA_VERSION_MAJOR" -gt 12 ]] || ([[ "$CUDA_VERSION_MAJOR" -eq 12 ]] && [[ "$CUDA_VERSION_MINOR" -gt 1 ]]); then
        warn "Your CUDA version ($CUDA_VERSION_MAJOR.$CUDA_VERSION_MINOR) is newer than the recommended 12.1"
        echo "SD Forge may experience compatibility issues with newer CUDA versions."
        echo
        echo "Options:"
        echo "1) Continue with current CUDA $CUDA_VERSION_MAJOR.$CUDA_VERSION_MINOR (risk of SD Forge breaking)"
        echo "2) Install CUDA 12.1 alongside current version (recommended)"
        echo "3) Skip SD Forge installation"
        echo
        read -p "Select option [1-3] (default: 2): " cuda_choice
        
        case ${cuda_choice:-2} in
            1)
                warn "Proceeding with CUDA $CUDA_VERSION_MAJOR.$CUDA_VERSION_MINOR - SD Forge may not work properly"
                ;;
            2)
                log "Will install CUDA 12.1 for SD Forge compatibility"
                INSTALL_CUDA_12_1=true
                ;;
            3)
                log "Skipping SD Forge installation"
                # Remove forge from selected services
                SELECTED_SERVICES=$(echo "$SELECTED_SERVICES" | sed 's/forge//g' | sed 's/  / /g' | sed 's/^ //g' | sed 's/ $//g')
                return
                ;;
        esac
    elif [[ "$CUDA_VERSION_MAJOR" -eq 12 ]] && [[ "$CUDA_VERSION_MINOR" -eq 1 ]]; then
        success "Your CUDA 12.1 is the recommended version for SD Forge!"
    else
        warn "Your CUDA version ($CUDA_VERSION_MAJOR.$CUDA_VERSION_MINOR) is older than recommended"
        echo "SD Forge works best with CUDA 12.1"
        echo
        echo "Options:"
        echo "1) Continue with current CUDA $CUDA_VERSION_MAJOR.$CUDA_VERSION_MINOR"
        echo "2) Upgrade to CUDA 12.1 (recommended)"
        echo
        read -p "Select option [1-2] (default: 2): " cuda_choice
        
        case ${cuda_choice:-2} in
            1)
                warn "Proceeding with CUDA $CUDA_VERSION_MAJOR.$CUDA_VERSION_MINOR"
                ;;
            2)
                log "Will upgrade to CUDA 12.1"
                UPGRADE_CUDA_12_1=true
                ;;
        esac
    fi
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
            if run_as_user docker ps -q -f name="^${service}$" | grep -q .; then
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
    
    # Check if forge is selected and prompt for CUDA version
    if [[ " $SELECTED_SERVICES " =~ " forge " ]]; then
        prompt_forge_cuda_version
        
        # Handle CUDA 12.1 installation if requested
        if [[ "${INSTALL_CUDA_12_1:-false}" == "true" ]]; then
            # Check if CUDA 12.1 is already installed
            if [[ -d "/usr/local/cuda-12.1" ]]; then
                log "CUDA 12.1 is already installed, switching to it..."
                sudo rm -f /usr/local/cuda
                sudo ln -s /usr/local/cuda-12.1 /usr/local/cuda
                success "Switched to CUDA 12.1"
            else
                install_cuda_12_1
                # Switch to CUDA 12.1 if installation succeeded
                if [[ -d "/usr/local/cuda-12.1" ]]; then
                    sudo rm -f /usr/local/cuda
                    sudo ln -s /usr/local/cuda-12.1 /usr/local/cuda
                    log "CUDA 12.1 is now the active CUDA version"
                fi
            fi
        elif [[ "${UPGRADE_CUDA_12_1:-false}" == "true" ]]; then
            install_cuda_12_1
            # Switch to CUDA 12.1
            if [[ -d "/usr/local/cuda-12.1" ]]; then
                sudo rm -f /usr/local/cuda
                sudo ln -s /usr/local/cuda-12.1 /usr/local/cuda
                log "Upgraded to CUDA 12.1"
            fi
        fi
    fi
    
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
    
    if [[ "$VERBOSE" == "true" ]]; then
        if ! run_as_user docker compose up -d 2>&1 | tee /tmp/docker-compose.log; then
            error "Failed to start services!"
            echo "Check the log at /tmp/docker-compose.log for details"
            echo
            echo "Common issues:"
            echo "- Port conflicts: Check if ports are already in use"
            echo "- GPU conflicts: Verify GPU assignments"
            echo "- Out of memory: Check available system memory"
            exit 1
        fi
    else
        echo -n "Starting services... "
        if ! run_as_user docker compose up -d > /tmp/docker-compose.log 2>&1; then
            echo "[FAILED]"
            error "Failed to start services!"
            echo "Check the log at /tmp/docker-compose.log for details"
            echo
            echo "Common issues:"
            echo "- Port conflicts: Check if ports are already in use"
            echo "- GPU conflicts: Verify GPU assignments"
            echo "- Out of memory: Check available system memory"
            exit 1
        fi
        echo "[OK]"
    fi
    
    # Verify services are starting
    log "Verifying services..."
    sleep 5
    local failed_services=""
    for service in $SELECTED_SERVICES; do
        if ! run_as_user docker ps | grep -q "$service"; then
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
