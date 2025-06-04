# CUDA Compatibility Fixes for AI Box

## Overview
AI Box services have specific CUDA version requirements that may conflict with your system's CUDA installation. This document explains the issues and solutions.

## CUDA Version Conflicts

### System Configuration
- **NVIDIA Driver**: 575.51.03 (supports up to CUDA 12.9)
- **System CUDA**: 12.9 (from driver)
- **Installed CUDA Toolkit**: 12.1 (required for SD Forge)
- **nvcc**: 12.0 (compiler version)

### Service Requirements
1. **SD Forge**: Requires CUDA 12.1 with PyTorch 2.3.1
2. **ComfyUI**: Requires cuDNN 9 (needs specific CUDA builds)
3. **LocalAI/Ollama**: Work with CUDA 12.x

## Fixed Docker Configurations

### Shared Memory (shm_size) Requirement
GPU services require additional shared memory for PyTorch/CUDA operations:

```yaml
shm_size: 8gb  # Added to both forge and comfyui services
```

**Why this is needed:**
- Default Docker containers only have 64MB shared memory
- GPU frameworks use shared memory for inter-process communication
- Without it, you'll see errors like "DataLoader worker killed by signal: Bus error"
- The 8GB is allocated from system RAM (not GPU VRAM) and only used when needed

**Real-world impact:**
- Prevents crashes during image generation
- Enables batch processing and larger image sizes
- Required for SDXL and high-resolution outputs

### SD Forge Fix
The fix involves mounting CUDA 12.1 libraries into the container:

```yaml
volumes:
  - /usr/local/cuda-12.1/lib64:/usr/local/cuda/lib64:ro
  - /usr/local/cuda-12.1/compat:/usr/local/cuda/compat:ro
environment:
  - LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/compat:$LD_LIBRARY_PATH
  - CUDA_HOME=/usr/local/cuda
  - PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
  - TORCH_CUDA_ARCH_LIST=8.6;8.9
  - CUDA_MODULE_LOADING=LAZY
  - COMMANDLINE_ARGS=--skip-torch-cuda-test --skip-version-check --no-download-sd-model
```

### ComfyUI Fix
ComfyUI needs the CUDA 12.1 specific image:

```yaml
image: yanwk/comfyui-boot:cu121  # Instead of :latest
```

## Model Requirements

### Can Services Run Without Models?
- **YES** - Both SD Forge and ComfyUI will start without models
- They'll show "No models found" errors when trying to generate
- This is useful for testing the installation before downloading large model files

### Downloading Models (Optional)
```bash
# SD 1.5 Model (~4GB)
wget -c https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors \
  -O /opt/ai-box/models/stable-diffusion/sd-v1-5.safetensors

# SDXL Model (~7GB) 
wget -c https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors \
  -O /opt/ai-box/models/stable-diffusion/sdxl-base-1.0.safetensors
```

## Setup Script Integration

The setup script should:
1. Detect CUDA version mismatch
2. Offer to install CUDA 12.1 alongside existing CUDA
3. Apply the fixes automatically when deploying SD Forge/ComfyUI
4. Skip model downloads by default (add --download-models flag for optional downloads)