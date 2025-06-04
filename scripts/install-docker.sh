#!/bin/bash
# install-docker.sh - Install Docker and NVIDIA Container Toolkit

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check if running with sudo
if [[ $EUID -ne 0 ]]; then
    error "This script must be run with sudo"
    echo "Usage: sudo $0"
    exit 1
fi

# Get the actual user (not root)
ACTUAL_USER=${SUDO_USER:-$USER}

log "Installing Docker for user: $ACTUAL_USER"

# Update package index
log "Updating package index..."
apt-get update

# Install prerequisites
log "Installing prerequisites..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common

# Add Docker's official GPG key
log "Adding Docker GPG key..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
log "Adding Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index again
log "Updating package index with Docker repository..."
apt-get update

# Install Docker
log "Installing Docker..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
log "Starting Docker service..."
systemctl start docker
systemctl enable docker

# Add user to docker group
log "Adding $ACTUAL_USER to docker group..."
usermod -aG docker $ACTUAL_USER

# Install NVIDIA Container Toolkit
log "Installing NVIDIA Container Toolkit..."

# Add NVIDIA GPG key
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /etc/apt/keyrings/nvidia-container-toolkit.gpg
chmod a+r /etc/apt/keyrings/nvidia-container-toolkit.gpg

# Add NVIDIA repository
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Update and install
apt-get update
apt-get install -y nvidia-container-toolkit

# Configure Docker daemon for GPU support
log "Configuring Docker for GPU support..."
nvidia-ctk runtime configure --runtime=docker

# Create daemon.json if it doesn't exist
if [ ! -f /etc/docker/daemon.json ]; then
    echo '{}' > /etc/docker/daemon.json
fi

# Restart Docker
log "Restarting Docker..."
systemctl restart docker

# Verify installation
log "Verifying Docker installation..."
if docker --version; then
    success "Docker installed successfully!"
else
    error "Docker installation failed"
    exit 1
fi

# Test GPU support (if NVIDIA GPU is available)
if command -v nvidia-smi &> /dev/null; then
    log "Testing GPU support..."
    if docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi &> /dev/null; then
        success "GPU support is working!"
    else
        warn "GPU test failed - this might be normal if drivers are not fully configured"
    fi
else
    warn "NVIDIA drivers not detected - GPU support will not be available"
fi

echo
success "Docker installation complete!"
echo
echo "IMPORTANT: To use Docker without sudo, you need to log out and back in"
echo "or run: newgrp docker"
echo
echo "You can now run the AI Box setup script without sudo:"
echo "  ./setup.sh"