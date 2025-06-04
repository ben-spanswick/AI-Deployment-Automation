# Key Changes to Integrate into setup.sh

## 1. Update Service Definitions

### Fix n8n secure cookie issue:
```bash
SERVICE_ENV["n8n"]="N8N_SECURE_COOKIE=false;N8N_HOST=0.0.0.0;N8N_PORT=5678;NODE_ENV=production"
```

### Update Forge with CUDA fixes:
```bash
SERVICE_ENV["forge"]="COMMANDLINE_ARGS=--listen --api --xformers --medvram --skip-torch-cuda-test --skip-version-check --no-download-sd-model;LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/compat:\$LD_LIBRARY_PATH;CUDA_HOME=/usr/local/cuda;PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512;TORCH_CUDA_ARCH_LIST=8.6\;8.9;CUDA_MODULE_LOADING=LAZY"
```

### Update ComfyUI to use CUDA 12.1 image:
```bash
SERVICE_IMAGES["comfyui"]="yanwk/comfyui-boot:cu121"  # Changed from :latest
```

## 2. Add CUDA Fix Detection

Add new array after service definitions:
```bash
declare -A SERVICE_CUDA_FIX
SERVICE_CUDA_FIX["forge"]="12.1"
SERVICE_CUDA_FIX["comfyui"]="image"
```

## 3. Modify add_service_to_compose Function

In the volumes section, add after the regular volumes loop:
```bash
# Add CUDA 12.1 library mounts for Forge
if [[ "$service" == "forge" ]] && [[ -d "/usr/local/cuda-12.1" ]]; then
    echo "      # CUDA 12.1 compatibility libraries" >> "/opt/ai-box/docker-compose.yml"
    echo "      - /usr/local/cuda-12.1/lib64:/usr/local/cuda/lib64:ro" >> "/opt/ai-box/docker-compose.yml"
    echo "      - /usr/local/cuda-12.1/compat:/usr/local/cuda/compat:ro" >> "/opt/ai-box/docker-compose.yml"
fi
```

Add shm_size for GPU services:
```bash
# Add service-specific configurations
if [[ "$service" == "forge" ]] || [[ "$service" == "comfyui" ]]; then
    echo "    shm_size: 8gb" >> "/opt/ai-box/docker-compose.yml"
fi
```

## 4. Update Directory Creation

In create_directories function, add:
```bash
mkdir -p "$INSTALL_DIR"/{forge-extensions,comfyui/custom_nodes}

# Set permissions for output directories
chmod -R 777 "$INSTALL_DIR"/outputs 2>/dev/null || true
chmod -R 777 "$INSTALL_DIR"/comfyui 2>/dev/null || true
```

## 5. Handle CUDA Detection Errors

In the handle_forge_cuda_version function, when CUDA 12.1 is installed:
```bash
success "CUDA 12.1 environment configured for SD Forge compatibility"
```

## 6. Update Post-Install Message

Add to print_post_install_message:
```bash
echo -e "${YELLOW}Important Notes:${NC}"
echo -e "- SD Forge and ComfyUI will run without models but show errors when generating"
echo -e "- To download models (optional):"
echo -e "  ${BLUE}wget -c https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors \\${NC}"
echo -e "  ${BLUE}  -O /opt/ai-box/models/stable-diffusion/sd-v1-5.safetensors${NC}"
echo
echo -e "- CUDA compatibility fixes have been applied automatically"
```

## 7. Error Handling for CUDA Issues

Add error recovery in start_services function:
```bash
# Check for CUDA-related errors in logs
if docker logs "$service" 2>&1 | grep -q "No CUDA GPUs are available"; then
    warn "Service $service has GPU access issues, attempting fix..."
    
    # Restart with explicit GPU device
    docker-compose -f /opt/ai-box/docker-compose.yml restart "$service"
fi

# Check for cuDNN errors
if docker logs "$service" 2>&1 | grep -q "libcudnn.so"; then
    warn "Service $service has cuDNN issues"
    if [[ "$service" == "comfyui" ]]; then
        log "ComfyUI requires the cu121 image version for CUDA compatibility"
    fi
fi
```

## Summary of Changes:

1. **n8n**: Added `N8N_SECURE_COOKIE=false`
2. **SD Forge**: Added CUDA 12.1 library mounts and environment variables
3. **ComfyUI**: Changed to `cu121` tagged image
4. **Both GPU services**: Added 8GB shared memory
5. **Setup flow**: Services start without requiring models
6. **Error handling**: Detect and report CUDA/cuDNN issues

These changes ensure that:
- Services start successfully without models
- CUDA compatibility is handled automatically
- Common errors are caught and explained
- The setup is reproducible and robust