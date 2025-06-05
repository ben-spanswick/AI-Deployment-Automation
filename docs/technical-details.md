# AI Box - Comprehensive Technical Documentation

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Dashboard System](#dashboard-system)  
3. [Service Details](#service-details)
4. [GPU Management](#gpu-management)
5. [Installation Deep Dive](#installation-deep-dive)
6. [Configuration Reference](#configuration-reference)
7. [Network Configuration](#network-configuration)
8. [Security Implementation](#security-implementation)
9. [Performance Optimization](#performance-optimization)
10. [Troubleshooting Guide](#troubleshooting-guide)
11. [Development Notes](#development-notes)
12. [Known Issues & Workarounds](#known-issues--workarounds)

---

## Architecture Overview

### System Design Philosophy
AI Box follows a **containerized microservices architecture** with these core principles:
- **Service isolation** - Each AI service runs in its own container
- **Resource efficiency** - Shared GPU access with configurable allocation
- **Network agnostic** - Dynamic IP configuration for any deployment
- **Production ready** - Proper error handling, logging, and monitoring

### Container Architecture
```
┌─────────────────────────────────────────────────────────┐
│                 AI Box Dashboard (Port 8085)           │
│           Python Flask + Embedded HTML/CSS/JS          │
├─────────────────────────────────────────────────────────┤
│  GPU Metrics Server (9999)  │    Service Status API    │
│    NVIDIA Container          │    Backend Endpoints     │
├─────────────────────────────────────────────────────────┤
│  LocalAI  │  Ollama   │ SD Forge │ ComfyUI │ ChromaDB  │
│   :8080   │  :11434   │  :7860   │  :8188  │  :8000    │
├─────────────────────────────────────────────────────────┤
│      n8n Automation      │      Whisper STT           │
│        :5678              │        :9000               │
└─────────────────────────────────────────────────────────┘
                    Docker ai-network Bridge
                 NVIDIA Container Toolkit Runtime
                       CUDA 12.9+ Drivers
                      Host GPU Hardware
```

###  Communication Patterns
- **Frontend ↔ Backend**: HTTP REST API calls to dashboard endpoints
- **Container ↔ Container**: Docker internal DNS resolution via ai-network
- **Dashboard ↔ GPU**: Dedicated GPU metrics server on localhost:9999
- **External Access**: Host port mapping for user-facing services

---

## Dashboard System

###  Modern Web Dashboard
The AI Box Dashboard is a **unified control panel** built with modern web technologies:

**Frontend Components:**
- **Real-time GPU monitoring** - Temperature, utilization, VRAM, power draw
- **Service management** - Start/stop/restart with live status indicators
- **Resource monitoring** - CPU and memory usage per container  
- **API documentation** - Embedded guides for ChromaDB and Ollama
- **Responsive design** - Works on desktop and mobile devices

**Backend API Architecture:**
```python
# Optimized single endpoint for dashboard data
GET /api/dashboard → Combined system + services + GPU data

# Legacy endpoints maintained for compatibility  
GET /api/services → Service list and stats
GET /api/system → System information
GET /api/gpu/metrics → Real-time GPU data

# Service-specific status checks
GET /api/check-service/chromadb → ChromaDB connectivity
GET /api/check-service/ollama → Ollama API status

# Service control endpoints
POST /api/services/{name}/{action} → start/stop/restart
```

###  Technical Implementation
- **Security**: Command injection protection with safe subprocess execution
- **Performance**: Bulk Docker stats collection (single command vs 14 individual calls)
- **Caching**: Smart TTL-based caching (2s for services, 5s for GPU metrics)
- **Error Handling**: Comprehensive logging and graceful degradation
- **Network Agnostic**: Dynamic IP detection using `window.location.hostname`

---

## Service Details

###  Language Models (LLMs)

#### LocalAI (Port 8080)
**Purpose**: OpenAI-compatible API for local LLM inference
**Image**: `quay.io/go-skynet/local-ai:latest-gpu-nvidia-cuda-12`
**GPU Usage**: CUDA acceleration for inference
**API Compatibility**: OpenAI GPT API format
**Model Support**: GGUF, GGML, Safetensors formats
```bash
# Example API call
curl http://your-ip:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "ggml-model", "messages": [{"role": "user", "content": "Hello!"}]}'
```

#### Ollama (Port 11434)  
**Purpose**: Simple model management with extensive model library
**Image**: `ollama/ollama:latest`
**GPU Usage**: Automatic CUDA detection and utilization
**Model Management**: Built-in pull/run/delete commands
**API Format**: Native Ollama API + OpenAI compatibility mode
```bash
# Pull and run a model
docker exec ollama ollama pull llama3.1:8b
docker exec ollama ollama run llama3.1:8b "Tell me about AI"
```

###  Image Generation

#### Stable Diffusion Forge (Port 7860)
**Purpose**: Optimized Stable Diffusion WebUI with advanced features
**Image**: `nykk3/stable-diffusion-webui-forge:latest`
**GPU Requirements**: 8GB+ VRAM for SDXL, 4GB+ for SD 1.5
**CUDA Requirements**: CUDA 12.1 recommended for stability
**Features**: FLUX support, advanced sampling, ControlNet, LoRA training
```bash
# Directory structure for models
/opt/ai-box/models/stable-diffusion/     # Main models
/opt/ai-box/models/stable-diffusion/SDXL/ # SDXL models  
/opt/ai-box/models/loras/                # LoRA adapters
/opt/ai-box/models/vae/                  # VAE models
```

#### ComfyUI (Port 8188)
**Purpose**: Node-based workflow system for advanced image generation
**Image**: `yanwk/comfyui-boot:latest`
**GPU Usage**: Efficient pipeline execution with model loading optimization
**Workflow Features**: Custom nodes, model chaining, batch processing
**Advantages**: Memory efficient, extensible, programmatic workflows

###  Infrastructure Services

#### ChromaDB (Port 8000)
**Purpose**: Vector database for RAG applications and embeddings
**Image**: `chromadb/chroma:latest`
**API Type**: HTTP REST API (no web UI)
**Use Cases**: Document embeddings, similarity search, RAG systems
**Access**: [Built-in API documentation](http://your-ip:8085/chromadb-info)

#### n8n (Port 5678)
**Purpose**: Workflow automation and AI chain orchestration  
**Image**: `n8nio/n8n:latest`
**Features**: Visual workflow builder, AI service integration, scheduling
**Configuration**: Secure cookie disabled for local access
**Use Cases**: AI pipeline automation, data processing, webhook handling

#### Whisper (Port 9000)
**Purpose**: OpenAI Whisper speech-to-text transcription
**Image**: `onerahmet/openai-whisper-asr-webservice:latest-gpu`
**GPU Usage**: CUDA acceleration for faster transcription
**Supported Formats**: WAV, MP3, M4A, FLAC
**Languages**: 100+ languages supported

---

## GPU Management

###  GPU Architecture
AI Box implements a **sophisticated GPU monitoring and allocation system**:

**GPU Metrics Server** (Port 9999):
- **Real-time telemetry**: Temperature, utilization, VRAM usage, power draw
- **Container deployment**: Runs in dedicated NVIDIA CUDA container
- **API endpoint**: `http://localhost:9999/gpu-metrics` 
- **Update frequency**: 5-second intervals for optimal performance
- **Hardware support**: All NVIDIA GPUs with driver 450.80.02+

**GPU Allocation Strategy**:
```bash
# Environment variables for GPU assignment
LOCALAI_GPUS="0,1"      # Use both GPUs for LLM inference
FORGE_GPUS="0,1"        # Use both GPUs for image generation  
OLLAMA_GPUS="0,1"       # Use both GPUs for model serving
COMFYUI_GPUS="0"        # Use first GPU only for workflows

# Docker Compose GPU allocation
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          device_ids: ['0','1']  # Specific GPU assignment
          capabilities: [gpu]
```

###  GPU Monitoring Implementation
```python
# GPU server provides real-time metrics
{
  "gpus": [
    {
      "index": 0,
      "name": "NVIDIA GeForce RTX 3090",
      "temperature": 45.0,
      "gpu_util": 85.0,
      "mem_used": 12288.0,
      "mem_total": 24576.0, 
      "mem_util": 50.0,
      "power_draw": 220.5
    }
  ]
}
```

###  CUDA Version Management
**System Strategy**: 
- **Primary CUDA**: Latest stable (12.9+) for new services
- **Legacy Support**: CUDA 12.1 compatibility for Stable Diffusion Forge
- **Driver Requirements**: NVIDIA Driver 550+ with CUDA 12.9 support
- **Container Images**: Service-specific CUDA versions as needed

---

## Installation Deep Dive

###  Automated Installation Flow
The `setup.sh` script implements a **comprehensive deployment pipeline**:

```bash
#!/bin/bash
# AI Box Installation Pipeline

1. **System Prerequisites**
   - Ubuntu 20.04+ compatibility check
   - Root privileges validation  
   - Hardware requirements verification

2. **NVIDIA Driver Installation**
   - Automatic driver detection (nvidia-smi check)
   - Latest stable driver installation via ubuntu-drivers
   - CUDA toolkit installation (nvidia-cuda-toolkit)
   - GPU persistence mode enable

3. **Docker Setup**
   - Docker Engine installation (if not present)
   - NVIDIA Container Toolkit setup
   - User permissions configuration (docker group)
   - GPU container runtime test

4. **Service Deployment** 
   - Docker network creation (ai-network)
   - Service selection and configuration
   - Container image pulling and startup
   - Health check validation

5. **Dashboard Deployment**
   - Dashboard container build and deploy
   - GPU metrics server startup
   - Port mapping and network configuration
   - Final system validation
```

###  Configuration Management
**Deployment Configuration** (`config/deployment.conf`):
```bash
# Core settings
AI_BOX_HOME="/opt/ai-box"
MODELS_DIR="/opt/ai-box/models"
DATA_DIR="/opt/ai-box/data"

# Network configuration  
DOCKER_NETWORK="ai-network"
SUBNET="172.20.0.0/16"

# Service ports
DASHBOARD_PORT=8085
LOCALAI_PORT=8080
OLLAMA_PORT=11434
FORGE_PORT=7860

# GPU allocation
DEFAULT_GPU_COUNT=2
SHARED_GPU_ACCESS=true
```

---

## Network Configuration

###  Network-Agnostic Design
AI Box is designed to work on **any network configuration** without hardcoded IP addresses:

**Dynamic IP Resolution**:
```javascript
// Frontend uses dynamic hostname detection
const baseUrl = `http://${window.location.hostname}:8000`;

// Backend uses container DNS resolution  
const chromadb_url = 'http://chromadb:8000';
const ollama_url = 'http://ollama:11434';
```

**Docker Network Architecture**:
```yaml
networks:
  ai-network:
    driver: bridge
    name: ai-network
    ipam:
      config:
        - subnet: 172.20.0.0/16  # Internal container network
```

**Port Mapping Strategy**:
- **Dashboard**: Host port 8085 → Container port 8085
- **Services**: Host port X → Container port X (direct mapping)
- **Internal**: Service-to-service communication via Docker DNS

###  Security Network Design
- **Service Isolation**: Each service runs in isolated container namespace
- **Internal Communication**: Services communicate via ai-network bridge
- **External Access**: Only necessary ports exposed to host network
- **Firewall Compatibility**: Standard port mappings work with UFW/iptables

---

## Security Implementation

###  Defense-in-Depth Strategy

**1. Command Injection Protection**:
```python
def run_cmd(cmd, timeout=5):
    """Secure command execution with input validation"""
    if isinstance(cmd, str):
        # Whitelist allowed command patterns
        if cmd.startswith('docker ps'):
            cmd_parts = cmd.split()
        elif cmd.startswith('docker stats'):
            cmd_parts = cmd.split()
        else:
            print(f"Rejected unsafe command: {cmd}")
            return ""
    
    # Use argument list instead of shell=True
    result = subprocess.run(cmd_parts, capture_output=True, text=True, timeout=timeout)
```

**2. Container Security**:
- **User namespaces**: Non-root execution where possible
- **Resource limits**: Memory and CPU constraints per service
- **Network isolation**: Service communication via dedicated bridge network
- **Read-only filesystems**: Where applicable for immutable services

**3. API Security**:
- **Input validation**: All user inputs sanitized and validated
- **Error handling**: Specific exceptions instead of broad catching
- **Rate limiting**: Built-in Flask rate limiting for API endpoints
- **Authentication**: Configurable API key support per service

**4. Data Protection**:
- **Volume permissions**: Proper file system permissions on mounted volumes
- **Secret management**: Environment variable based configuration
- **Log security**: Sensitive information excluded from logs

---

## Performance Optimization

###  System Performance Strategy

**1. Dashboard Optimization**:
```python
# Single API call instead of 3 separate calls
@app.route('/api/dashboard')
def api_dashboard():
    """Combined endpoint reduces client requests by 66%"""
    return jsonify({
        'services': get_docker_services(),    # 2s cache TTL
        'system': get_system_info(),          # 30s cache TTL  
        'gpu': get_gpu_metrics()              # 5s cache TTL
    })
```

**2. GPU Monitoring Optimization**:
- **Bulk statistics collection**: Single `docker stats` command for all containers
- **Efficient caching**: Different TTL values based on data volatility
- **Reduced nvidia-smi calls**: From 120/minute to 12/minute (90% reduction)

**3. Container Resource Optimization**:
```yaml
# Resource limits and reservations
deploy:
  resources:
    limits:
      memory: 24G          # Prevent memory leaks
      cpus: '8.0'          # CPU allocation limits
    reservations:
      memory: 4G           # Guaranteed minimum memory
      devices:             # GPU allocation
        - driver: nvidia
          capabilities: [gpu]
```

**4. Storage Performance**:
- **Shared model storage**: Prevents duplicate model files
- **SSD optimization**: Models and data on fast storage
- **Volume mounting**: Efficient bind mounts for performance
- **Cleanup automation**: Automatic temporary file cleanup

### 📈 Performance Monitoring
```bash
# Resource usage monitoring
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

# GPU utilization tracking  
watch nvidia-smi

# Service health monitoring
curl http://localhost:8085/api/dashboard | jq '.services[].stats'
```

---

## Troubleshooting Guide

###  Diagnostic Commands

**System Health Check**:
```bash
# Complete system status
./scripts/check-status.sh

# GPU diagnostics
nvidia-smi
docker run --rm --gpus all nvidia/cuda:12.9-base-ubuntu22.04 nvidia-smi

# Container status
docker ps -a
docker system df
```

**Service-Specific Debugging**:
```bash
# Dashboard issues
docker logs dashboard --tail 50
curl -I http://localhost:8085

# GPU metrics server
docker logs gpu-server --tail 20  
curl http://localhost:9999/gpu-metrics

# Individual service debugging
docker logs localai --tail 30
docker exec localai nvidia-smi  # Check GPU access inside container
```

### 🚫 Common Issues and Solutions

**Issue: Dashboard shows "Service Offline"**
```bash
# Check backend connectivity
docker exec dashboard curl http://chromadb:8000/
docker exec dashboard curl http://ollama:11434/api/tags

# Verify network connectivity
docker network inspect ai-network
```

**Issue: GPU not detected in containers**
```bash
# Check NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update && sudo apt-get install -y nvidia-docker2
sudo systemctl restart docker
```

**Issue: Port conflicts**
```bash
# Find process using port
sudo netstat -tlnp | grep :8085
sudo lsof -i :8085

# Change dashboard port if needed
docker stop dashboard
docker run -d --name dashboard -p 8086:8085 ai-dashboard
```

**Issue: Out of VRAM errors**
```bash
# Check GPU memory usage
nvidia-smi
docker exec forge nvidia-smi

# Reduce model size or adjust GPU allocation
export FORGE_GPUS="0"  # Use single GPU
docker restart forge
```

---

## Development Notes

###  Development Environment Setup

**Local Development**:
```bash
# Clone with development branch
git clone -b development https://github.com/ben-spanswick/AI-Deployment-Automation.git

# Set up development environment
python3 -m venv ai-box-dev
source ai-box-dev/bin/activate
pip install flask docker-py requests

# Run dashboard locally for development
cd AI-Deployment
python3 dashboard-unified.py
```

**Code Quality Standards**:
- **Security**: All subprocess calls use argument lists, not shell=True
- **Error Handling**: Specific exception types, comprehensive logging  
- **Performance**: Caching, bulk operations, efficient algorithms
- **Maintainability**: Clear separation of concerns, documentation

**Testing Strategy**:
```bash
# Unit tests for dashboard functions
python3 -m pytest tests/test_dashboard.py

# Integration tests for service communication
python3 -m pytest tests/test_integration.py

# Load testing for API endpoints
ab -n 1000 -c 10 http://localhost:8085/api/dashboard
```

###  Continuous Integration
**Automated Testing Pipeline**:
1. **Code Quality**: Linting with flake8, security scanning with bandit
2. **Unit Testing**: Individual function testing with pytest
3. **Integration Testing**: Service-to-service communication verification
4. **Performance Testing**: API response time and resource usage validation
5. **Security Testing**: Vulnerability scanning and penetration testing

---

## Known Issues & Workarounds

###  Current Limitations

**1. CUDA Version Compatibility**
- **Issue**: Some services require specific CUDA versions (SD Forge prefers 12.1)
- **Workaround**: Services use containerized CUDA runtimes, isolated from host
- **Status**: Working as designed, no action needed

**2. GPU Memory Allocation**
- **Issue**: Multiple services may compete for GPU memory
- **Workaround**: Configure `CUDA_VISIBLE_DEVICES` per service for isolation
- **Monitoring**: Use nvidia-smi and dashboard GPU monitoring

**3. Network Port Conflicts**
- **Issue**: Port conflicts with existing services
- **Workaround**: Modify port assignments in config/deployment.conf
- **Prevention**: Port availability check in setup.sh

**4. Container Startup Dependencies**
- **Issue**: Some services may start before dependencies are ready
- **Workaround**: Docker Compose health checks and restart policies
- **Monitoring**: Dashboard service status indicators

###  Planned Improvements

**Short Term (v2.1)**:
- [ ] Frontend/backend separation for better maintainability
- [ ] Advanced GPU allocation and scheduling
- [ ] Service dependency management
- [ ] Automated backup and restore system

**Medium Term (v2.2)**:
- [ ] Multi-node deployment support
- [ ] Advanced monitoring and alerting
- [ ] User authentication and authorization
- [ ] API versioning and compatibility layers

**Long Term (v3.0)**:
- [ ] Kubernetes deployment option
- [ ] Advanced workflow orchestration
- [ ] Machine learning model optimization
- [ ] Integration with cloud services

---

## FAQ

**Q: What GPU memory is required for each service?**
A: LocalAI (4-8GB), Ollama (2-16GB depending on model), SD Forge (6-12GB), ComfyUI (4-8GB), Others (<1GB)

**Q: Can I run AI Box on a single GPU system?**
A: Yes, all services can share a single GPU. Adjust GPU allocation in config files.

**Q: How do I add custom models?**
A: Copy models to appropriate directories in `/opt/ai-box/models/`. Each service has specific subdirectories.

**Q: Is internet connection required after installation?**
A: Only for downloading new models. All services run offline once installed.

**Q: Can I access services from remote machines?**
A: Yes, configure firewall to allow access to service ports. Dashboard works on any IP address.

**Q: How do I update AI Box to newer versions?**
A: Pull latest git changes and run `sudo ./setup.sh --update` (update mechanism in development)

**Q: What happens if I reboot the system?**
A: All services are configured with `restart: unless-stopped` and will automatically start after reboot.

---

*This documentation reflects AI Box v2.0.0. For the latest updates, see the [project repository](https://github.com/ben-spanswick/AI-Deployment-Automation).*