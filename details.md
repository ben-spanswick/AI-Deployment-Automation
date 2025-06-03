# AI Box - Detailed Technical Documentation

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Service Details](#service-details)
3. [Installation Deep Dive](#installation-deep-dive)
4. [Configuration Reference](#configuration-reference)
5. [Troubleshooting Guide](#troubleshooting-guide)
6. [Performance Tuning](#performance-tuning)
7. [Security Considerations](#security-considerations)
8. [Development Notes](#development-notes)
9. [Known Issues & Workarounds](#known-issues--workarounds)
10. [FAQ](#faq)

## Architecture Overview

### System Design
AI Box uses a containerized microservices architecture with the following layers:

1. **Presentation Layer**: Web dashboard (HTML/JS) + Dashboard backend (Python/Flask)
2. **Service Layer**: Docker containers for each AI service
3. **Infrastructure Layer**: Docker Engine + NVIDIA Container Toolkit
4. **Storage Layer**: Shared volumes for models and data

### Network Architecture
- All services run on a custom Docker bridge network (`ai-network`, 172.20.0.0/16)
- Nginx reverse proxy handles routing and static file serving
- Services communicate internally using Docker DNS

### Directory Structure
```
/opt/ai-box/                  # Main installation directory
├── models/                   # Shared model storage
│   ├── stable-diffusion/     # SD/SDXL models
│   ├── loras/               # LoRA models
│   ├── embeddings/          # Text embeddings
│   └── whisper/             # Speech models
├── data/                    # Service data
│   ├── localai/            
│   ├── ollama/             
│   └── chromadb/           
├── outputs/                 # Generated content
│   ├── forge/              
│   └── comfyui/            
├── logs/                    # Application logs
└── dashboard/               # Dashboard files
```

## Service Details

### LocalAI
- **Purpose**: OpenAI-compatible API for running LLMs locally
- **Default Port**: 8080
- **GPU Support**: CUDA 12 optimized image
- **Models Directory**: `/opt/ai-box/models/localai`
- **API Endpoints**:
  - `/v1/models` - List available models
  - `/v1/completions` - Text completion
  - `/v1/chat/completions` - Chat completion
  - `/v1/embeddings` - Generate embeddings
- **Configuration**: Models configured via YAML files in models directory
- **Performance Notes**: 
  - Uses CUDA for acceleration
  - Thread count affects CPU fallback performance
  - Memory usage scales with model size

### Ollama
- **Purpose**: Simple CLI-based LLM management
- **Default Port**: 11434
- **Features**:
  - Easy model pulling: `ollama pull llama2`
  - Model management API
  - Automatic quantization support
- **Storage**: Models stored in `/opt/ai-box/data/ollama/models`
- **Integration**: Works with Open WebUI, Continue.dev, etc.
- **Tips**:
  - Use `OLLAMA_NUM_GPU_LAYERS` to control GPU offloading
  - Models are automatically downloaded on first use

### Stable Diffusion Forge
- **Purpose**: Optimized Stable Diffusion WebUI
- **Default Port**: 7860
- **Key Features**:
  - SDXL support with optimizations
  - ControlNet integration
  - Advanced samplers (DPM++, UniPC)
  - API for automation
- **Model Locations**:
  - Checkpoints: `/opt/ai-box/models/stable-diffusion/`
  - LoRAs: `/opt/ai-box/models/loras/`
  - VAEs: `/opt/ai-box/models/vae/`
- **Command Line Args**: `--xformers --medvram --api`
- **Memory Management**:
  - `--medvram`: For 8-12GB VRAM
  - `--lowvram`: For 4-8GB VRAM
  - `--highvram`: For 16GB+ VRAM (not set by default)

### ComfyUI
- **Purpose**: Node-based workflow system
- **Default Port**: 8188
- **Advantages**:
  - FLUX model support
  - Complex workflow automation
  - Better memory efficiency
  - Custom node support
- **Custom Nodes Location**: `/workspace/ComfyUI/custom_nodes/`
- **Workflow Storage**: `/workspace/ComfyUI/workflows/`
- **Model Sharing**: Shares models with Forge when possible

### ChromaDB
- **Purpose**: Vector database for embeddings
- **Default Port**: 8000
- **Use Cases**:
  - RAG (Retrieval Augmented Generation)
  - Semantic search
  - Document QA systems
- **Persistence**: Data stored in `/opt/ai-box/data/chromadb`
- **API**: RESTful API for collections and queries
- **Performance**: Optimized for similarity search

### n8n
- **Purpose**: Workflow automation
- **Default Port**: 5678
- **Features**:
  - Visual workflow builder
  - AI service integration nodes
  - Webhook support
  - Scheduled execution
- **Storage**: Workflows saved in `/opt/ai-box/data/n8n`
- **Use Cases**:
  - Chain multiple AI services
  - Automated content generation
  - Data processing pipelines

### Whisper
- **Purpose**: Speech-to-text transcription
- **Default Port**: 9000
- **Models**: base, small, medium, large
- **API**: RESTful API for audio transcription
- **Supported Formats**: WAV, MP3, M4A, FLAC
- **Performance**: GPU acceleration for faster transcription

## Installation Deep Dive

### Prerequisites Check
The installer performs these checks:
1. **OS Detection**: Ubuntu 20.04+ or compatible
2. **GPU Detection**: NVIDIA GPU with `nvidia-smi`
3. **Docker Check**: Docker 20.10+ installed
4. **NVIDIA Runtime**: Container toolkit configured
5. **Disk Space**: Minimum 100GB free

### Installation Process
1. **Directory Creation**
   ```bash
   /opt/ai-box/{models,data,outputs,logs,dashboard}
   ```

2. **Docker Network Setup**
   ```bash
   docker network create --subnet=172.20.0.0/16 ai-network
   ```

3. **Service Deployment**
   - Pull Docker images
   - Create volumes
   - Configure environment variables
   - Start containers with proper GPU allocation

4. **Dashboard Setup**
   - Copy dashboard files
   - Configure Nginx
   - Start dashboard backend

### GPU Allocation
- Automatic detection via `nvidia-smi`
- Multi-GPU support with device mapping
- Per-service GPU assignment possible
- CUDA_VISIBLE_DEVICES environment variable

## Configuration Reference

### Main Configuration (config/aibox.conf)
```bash
# Core Settings
INSTALL_DIR="/opt/ai-box"        # Installation root
MODELS_DIR="/opt/ai-box/models"  # Shared models
DATA_DIR="/opt/ai-box/data"      # Service data

# GPU Settings
GPU_DEVICES="all"                # "all" or "0,1"
DEFAULT_VRAM_LIMIT="24G"         # Per-service limit

# Network Settings
DOCKER_NETWORK="ai-network"
DOCKER_SUBNET="172.20.0.0/16"

# Performance
CPU_THREADS=8                    # CPU thread count
SHM_SIZE="12gb"                  # Shared memory size
```

### Environment Variables (docker/.env)
```bash
# Service Ports
LOCALAI_PORT=8080
OLLAMA_PORT=11434
FORGE_PORT=7860
COMFYUI_PORT=8188

# GPU Assignment
LOCALAI_GPUS=0
FORGE_GPUS=0
COMFYUI_GPUS=1

# Memory Limits
FORGE_MEMORY_LIMIT=24G
COMFYUI_MEMORY_LIMIT=24G
```

### Service-Specific Configurations

#### LocalAI Models
Create YAML configs in `/opt/ai-box/models/localai/`:
```yaml
name: llama2-7b
parameters:
  model: llama2-7b-gguf
backend: llama
context_size: 4096
f16: true
gpu_layers: 35
```

#### Forge Launch Args
Edit in docker-compose.yml:
```yaml
COMMANDLINE_ARGS: --listen --api --xformers --medvram --enable-insecure-extension-access
```

## Troubleshooting Guide

### Common Issues

#### 1. GPU Not Detected
**Symptoms**: Services fail to start, "no CUDA devices" errors

**Solutions**:
```bash
# Check NVIDIA driver
nvidia-smi

# Reinstall NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker

# Test GPU access in container
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

#### 2. Out of Memory Errors
**Symptoms**: CUDA OOM, services crashing

**Solutions**:
```bash
# For Forge - add to launch args:
--medvram  # or --lowvram for severe cases

# For ComfyUI - reduce batch size in workflow

# Monitor GPU memory:
watch -n 1 nvidia-smi

# Clear GPU memory:
sudo nvidia-smi --gpu-reset
```

#### 3. Port Conflicts
**Symptoms**: "address already in use" errors

**Solutions**:
```bash
# Find process using port
sudo lsof -i :8080

# Kill process
sudo kill -9 <PID>

# Or change port in .env file
LOCALAI_PORT=8081
```

#### 4. Model Loading Failures
**Symptoms**: Models not found, wrong format errors

**Solutions**:
- Ensure models are in correct directories
- Check file permissions: `chmod 644 model.safetensors`
- Verify model format (safetensors vs ckpt)
- Check available disk space

#### 5. Dashboard Not Loading
**Symptoms**: 502 errors, blank page

**Solutions**:
```bash
# Check dashboard backend
docker logs dashboard-backend

# Restart services
docker restart dashboard-backend nginx

# Fix permissions
sudo chown -R $USER:$USER /opt/ai-box/dashboard
```

### Advanced Troubleshooting

#### Docker Issues
```bash
# Check Docker daemon
sudo systemctl status docker

# View Docker logs
sudo journalctl -u docker.service

# Clean up Docker
docker system prune -a --volumes

# Reset Docker
sudo systemctl restart docker
```

#### Network Issues
```bash
# Check network
docker network inspect ai-network

# Recreate network
docker network rm ai-network
docker network create --subnet=172.20.0.0/16 ai-network

# Test connectivity
docker run --rm --network ai-network alpine ping localai
```

#### Permission Issues
```bash
# Fix ownership
sudo chown -R $USER:$USER /opt/ai-box

# Fix permissions
find /opt/ai-box -type d -exec chmod 755 {} \;
find /opt/ai-box -type f -exec chmod 644 {} \;
```

## Performance Tuning

### GPU Optimization
1. **Multi-GPU Setup**
   ```bash
   # Assign specific GPUs to services
   FORGE_GPUS=0
   COMFYUI_GPUS=1
   ```

2. **VRAM Management**
   - Use `--medvram` for 8-12GB cards
   - Enable model offloading
   - Reduce batch sizes
   - Use half-precision (fp16)

3. **CUDA Settings**
   ```bash
   export CUDA_LAUNCH_BLOCKING=0
   export CUDA_CACHE_DISABLE=0
   export CUDA_FORCE_PTX_JIT=1
   ```

### CPU Optimization
1. **Thread Allocation**
   ```bash
   # LocalAI
   THREADS=8
   
   # Ollama
   OLLAMA_NUM_THREAD=8
   ```

2. **Memory Settings**
   - Increase shared memory: `--shm-size=16gb`
   - Use tmpfs for temporary files
   - Enable swap for CPU inference

### Storage Optimization
1. **SSD Usage**
   - Models on NVMe SSD
   - Outputs can be on HDD
   - Use symlinks for large models

2. **Model Sharing**
   - Hardlink identical models
   - Use shared model directories
   - Clean unused models regularly

## Security Considerations

### Network Security
1. **Firewall Rules**
   ```bash
   # Allow only local access
   sudo ufw allow from 192.168.0.0/16 to any port 8080
   sudo ufw allow from 127.0.0.1 to any port 8080
   ```

2. **Reverse Proxy**
   - Use Nginx for SSL termination
   - Add authentication headers
   - Rate limiting

### Access Control
1. **Basic Authentication**
   ```nginx
   location / {
       auth_basic "AI Box";
       auth_basic_user_file /etc/nginx/.htpasswd;
   }
   ```

2. **API Keys**
   - Generate for each service
   - Rotate regularly
   - Store securely

### Container Security
1. **User Namespaces**
   ```yaml
   security_opt:
     - no-new-privileges:true
   user: "1000:1000"
   ```

2. **Read-Only Volumes**
   ```yaml
   volumes:
     - /opt/ai-box/models:/models:ro
   ```

## Development Notes

### Adding New Services
1. **Update setup.sh**
   ```bash
   SERVICE_INFO["newservice"]="Name|Description|category"
   SERVICE_PORTS["newservice"]="9999"
   SERVICE_IMAGES["newservice"]="image:tag"
   ```

2. **Create Docker Compose Entry**
   ```yaml
   newservice:
     image: ${SERVICE_IMAGES[newservice]}
     ports:
       - "${NEWSERVICE_PORT:-9999}:9999"
   ```

3. **Update Dashboard**
   - Add service card in HTML
   - Add status check in backend

### Custom Modifications

#### Custom Models Directory
```bash
# In setup.sh
MODELS_DIR="/mnt/large-storage/models"
```

#### Custom Network
```bash
# In docker-compose.yml
networks:
  ai-network:
    external: true
```

### Testing
1. **Service Health Checks**
   ```bash
   curl http://localhost:8080/health
   curl http://localhost:11434/
   ```

2. **GPU Tests**
   ```python
   import torch
   print(torch.cuda.is_available())
   print(torch.cuda.device_count())
   ```

## Known Issues & Workarounds

### Issue 1: ComfyUI Manager Git Clone Failures
**Problem**: Git operations fail inside container
**Workaround**: 
```bash
# Clone outside and copy
git clone https://github.com/ltdrdata/ComfyUI-Manager /tmp/manager
docker cp /tmp/manager comfyui:/workspace/ComfyUI/custom_nodes/
```

### Issue 2: Ollama Model Corruption
**Problem**: Interrupted downloads corrupt models
**Workaround**:
```bash
# Clear model cache
docker exec ollama rm -rf /root/.ollama/models/.download
# Re-pull model
docker exec ollama ollama pull llama2
```

### Issue 3: Forge Extension Conflicts
**Problem**: Some extensions break WebUI
**Workaround**:
- Disable extensions one by one
- Use `--safe` launch argument
- Clear extension cache

### Issue 4: ChromaDB Persistence
**Problem**: Data lost on container restart
**Workaround**: Ensure volume is properly mounted:
```yaml
volumes:
  - chromadb-data:/chroma/chroma
```

## FAQ

### Q: Can I run this without GPU?
**A**: Yes, but with limitations:
- LLMs will use CPU (very slow)
- Image generation not recommended
- Whisper will be slow
- Only suitable for testing

### Q: How do I add FLUX support?
**A**: FLUX works best with ComfyUI:
1. Download FLUX models to `/opt/ai-box/models/unet/`
2. Install ComfyUI-Manager
3. Use FLUX workflows

### Q: Can I expose services to the internet?
**A**: Not recommended, but possible:
1. Use reverse proxy with SSL
2. Implement authentication
3. Use VPN instead if possible
4. Monitor access logs

### Q: How do I backup everything?
**A**: 
```bash
# Backup script
tar -czf ai-box-backup-$(date +%Y%m%d).tar.gz \
  /opt/ai-box/models \
  /opt/ai-box/data \
  /opt/ai-box/outputs \
  /home/mandrake/AI-Deployment
```

### Q: Memory requirements for models?
**A**:
- 7B models: 8GB VRAM minimum
- 13B models: 16GB VRAM minimum  
- SDXL: 8GB VRAM minimum
- FLUX: 12GB VRAM minimum

### Q: How to update services?
**A**:
```bash
# Pull latest images
docker-compose pull

# Restart services
docker-compose up -d
```

### Q: Can I run multiple instances?
**A**: Yes, with different:
- Port mappings
- Directory paths
- Docker compose project names
- GPU assignments

## Support & Contact

- **Repository**: http://192.168.100.54:3000/Mandrake/AI-Deployment
- **Issues**: http://192.168.100.54:3000/Mandrake/AI-Deployment/issues
- **Documentation**: This file and README.md

---

Last Updated: June 2024
Version: 2.0.0