#!/bin/bash
# Patch for setup.sh to include CUDA fixes
# This shows the changes needed to integrate the CUDA fixes

cat << 'EOF'
## Changes needed in setup.sh:

### 1. Add CUDA fix environment variables to the docker-compose generation

In the generate_docker_compose() function, modify the forge service:

```bash
  forge:
    image: nykk3/stable-diffusion-webui-forge:latest
    container_name: forge
    ports:
      - "\${FORGE_PORT:-7860}:7860"
    volumes:
      - \${MODELS_DIR:-/opt/ai-box/models}/stable-diffusion:/app/stable-diffusion-webui/models/Stable-diffusion
      - \${MODELS_DIR:-/opt/ai-box/models}/loras:/app/stable-diffusion-webui/models/Lora
      - \${MODELS_DIR:-/opt/ai-box/models}/vae:/app/stable-diffusion-webui/models/VAE
      - \${OUTPUTS_DIR:-/opt/ai-box/outputs}/forge:/app/stable-diffusion-webui/outputs
      # CUDA 12.1 fix for compatibility
      - /usr/local/cuda-12.1/lib64:/usr/local/cuda/lib64:ro
      - /usr/local/cuda-12.1/compat:/usr/local/cuda/compat:ro
    environment:
      - COMMANDLINE_ARGS=--listen --api --xformers --medvram --skip-torch-cuda-test --skip-version-check --no-download-sd-model
      - CUDA_VISIBLE_DEVICES=\${FORGE_GPU_DEVICES}
      # CUDA 12.1 environment fixes
      - LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/compat:\$LD_LIBRARY_PATH
      - CUDA_HOME=/usr/local/cuda
      - PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
      - TORCH_CUDA_ARCH_LIST=8.6;8.9
      - CUDA_MODULE_LOADING=LAZY
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: \${FORGE_GPU_IDS}
              capabilities: [gpu]
    restart: unless-stopped
    networks:
      - ai-network
    shm_size: 8gb
```

### 2. Modify ComfyUI service to use CUDA 12.1 image:

```bash
  comfyui:
    image: yanwk/comfyui-boot:cu121  # Use CUDA 12.1 specific image
    container_name: comfyui
    ports:
      - "\${COMFYUI_PORT:-8188}:8188"
    volumes:
      - \${COMFYUI_DIR:-/opt/ai-box/comfyui}:/home/runner
      - \${MODELS_DIR:-/opt/ai-box/models}:/home/runner/models
      - \${OUTPUTS_DIR:-/opt/ai-box/outputs}/comfyui:/home/runner/output
    environment:
      - CLI_ARGS=--listen
      - CUDA_VISIBLE_DEVICES=\${COMFYUI_GPU_DEVICES}
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: \${COMFYUI_GPU_IDS}
              capabilities: [gpu]
    restart: unless-stopped
    networks:
      - ai-network
    shm_size: 8gb
```

### 3. Add warning about models in the post-installation message:

```bash
print_post_install_message() {
    echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        Installation Complete!              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}Service URLs:${NC}"
    # ... existing URLs ...
    
    echo
    echo -e "${YELLOW}Note about Image Generation Services:${NC}"
    echo -e "- SD Forge and ComfyUI are running but need models to generate images"
    echo -e "- They will show 'No models found' errors until you download models"
    echo -e "- To download models, see: ${BLUE}/opt/ai-box/cuda-fixes.md${NC}"
    echo
}
```

### 4. Add CUDA detection improvements:

```bash
check_cuda_compatibility() {
    local cuda_driver_version=$(nvidia-smi | grep "CUDA Version" | awk '{print $9}')
    local cuda_toolkit_version=""
    
    if command -v nvcc &> /dev/null; then
        cuda_toolkit_version=$(nvcc --version | grep "release" | awk '{print $5}' | cut -d',' -f1)
    fi
    
    if [[ -d "/usr/local/cuda-12.1" ]]; then
        echo -e "${GREEN}[INFO]${NC} CUDA 12.1 toolkit detected (required for SD Forge)"
    fi
    
    # Check for version mismatches
    if [[ "$cuda_driver_version" != "12.1" ]] && [[ "$ENABLE_FORGE" == "true" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} CUDA version mismatch detected"
        echo -e "  Driver CUDA: $cuda_driver_version"
        echo -e "  SD Forge requires: CUDA 12.1"
        echo -e "  The setup has applied compatibility fixes"
    fi
}
```

### 5. Create output directories with proper permissions:

```bash
create_directories() {
    echo -e "${BLUE}[INFO]${NC} Creating directory structure..."
    
    # Create all necessary directories
    mkdir -p "$INSTALL_DIR"/{models,outputs,comfyui,nginx/html,data}
    mkdir -p "$INSTALL_DIR"/models/{stable-diffusion,loras,vae,embeddings}
    mkdir -p "$INSTALL_DIR"/outputs/{forge,comfyui}
    
    # Set permissions for output directories
    chmod -R 777 "$INSTALL_DIR"/outputs
    
    echo -e "${GREEN}[SUCCESS]${NC} Directory structure created"
}
```
EOF

echo "This patch file shows the necessary changes to integrate CUDA fixes into setup.sh"