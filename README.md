# 🤖 AI Box - Modern Multi-GPU AI Stack

> Flexible deployment of LocalAI, Ollama, and Stable Diffusion Forge with dynamic GPU configuration. Run OpenAI-compatible APIs locally with any number of NVIDIA GPUs.

[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%20%7C%2022.04-orange)](https://ubuntu.com/)
[![NVIDIA](https://img.shields.io/badge/NVIDIA-RTX%203090%20%7C%204090%20%7C%20A100-76B900)](https://www.nvidia.com/)
[![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED)](https://www.docker.com/)
[![LocalAI](https://img.shields.io/badge/LocalAI-Latest-blue)](https://github.com/go-skynet/LocalAI)
[![Ollama](https://img.shields.io/badge/Ollama-Latest-black)](https://ollama.ai/)

## 🎯 Features

- **Modern AI Stack**:
  - **LocalAI**: OpenAI-compatible API for local LLM inference
  - **Ollama**: Easy model management with simple CLI/API
  - **Stable Diffusion Forge**: Next-gen WebUI with optimized performance
  - **NVIDIA DCGM**: GPU monitoring and metrics

- **Dynamic GPU Configuration**:
  - Automatically detects all NVIDIA GPUs
  - Flexible GPU assignment strategies
  - Support for 1 to unlimited GPUs
  - Per-service GPU allocation

- **Deployment Options**:
  - Interactive setup script
  - Ansible automation for full system configuration
  - Docker Compose for container-only deployment
  - Hybrid deployment modes

## 📋 Requirements

- **OS**: Ubuntu 20.04 or 22.04 (headless or desktop)
- **GPU**: NVIDIA GPU(s) - RTX 3090, 4090, A100, etc.
- **RAM**: 32GB+ recommended (16GB minimum)
- **Storage**: 500GB+ for models
- **Docker**: Version 24.0+
- **NVIDIA Driver**: 535+ (automatically installed)

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone http://192.168.100.54:3000/Mandrake/AI-Deployment.git
cd AI-Deployment
```

### 2. Run Interactive Setup

```bash
chmod +x setup.sh
./setup.sh
```

The setup will:
- Detect your GPU configuration
- Let you choose deployment method
- Configure GPU assignment
- Set service ports
- Deploy everything automatically

### 3. Access Your Services

After deployment:
- **LocalAI API**: `http://your-server:8080`
- **Ollama API**: `http://your-server:11434`
- **Stable Diffusion Forge**: `http://your-server:7860`
- **GPU Metrics**: `http://your-server:9400/metrics`
- **Dashboard**: `http://your-server` (if enabled)

## 🎮 GPU Assignment Options

### 1. All GPUs Mode (Recommended for LLMs)
All services use all available GPUs - best for large language models:
```
LocalAI: GPU 0,1,2,3
Ollama: GPU 0,1,2,3
Forge: GPU 0,1,2,3
```

### 2. Automatic Distribution
Intelligently distributes GPUs based on your hardware:
```
2 GPUs:
  LocalAI: GPU 0
  Ollama: GPU 1
  Forge: GPU 0,1
```

### 3. Manual Assignment
Specify exactly which GPUs each service uses:
```
LocalAI: GPU 0,1
Ollama: GPU 2,3
Forge: GPU 0,1,2,3
```

### 4. Single GPU Mode
All services share one GPU (for testing or limited hardware).

## 🔧 Service Overview

### LocalAI
- **Purpose**: OpenAI-compatible API for local inference
- **Models**: Supports GGUF, GGML, and various formats
- **API**: Drop-in replacement for OpenAI API
- **Usage**:
  ```python
  import openai
  openai.api_base = "http://localhost:8080/v1"
  openai.api_key = "sk-xxx"  # Any value works
  
  response = openai.Completion.create(
      model="gpt-3.5-turbo",
      prompt="Hello, how are you?"
  )
  ```

### Ollama
- **Purpose**: Simple model management and serving
- **Models**: Llama 2, Mistral, Mixtral, etc.
- **CLI**: Easy model pulling and running
- **Usage**:
  ```bash
  # Pull a model
  docker exec ollama ollama pull llama2
  
  # Run inference
  curl http://localhost:11434/api/generate -d '{
    "model": "llama2",
    "prompt": "Why is the sky blue?"
  }'
  ```

### Stable Diffusion Forge
- **Purpose**: Advanced image generation
- **Features**: Optimized performance, ControlNet, LoRA support
- **API**: Compatible with A1111 API
- **Usage**:
  ```python
  import requests
  
  response = requests.post('http://localhost:7860/sdapi/v1/txt2img', json={
      "prompt": "a beautiful sunset over mountains",
      "steps": 20,
      "width": 512,
      "height": 512
  })
  ```

## 📊 Management Commands

### Docker Compose
```bash
cd /opt/ai-box

# View all services
docker compose ps

# View logs
docker compose logs -f [service-name]

# Restart services
docker compose restart

# Update images
docker compose pull
docker compose up -d
```

### Model Management

**LocalAI Models**:
```bash
# Place models in /opt/ai-box/models/
# Supports: GGUF, GGML, GPTQ, etc.
```

**Ollama Models**:
```bash
# List models
docker exec ollama ollama list

# Pull model
docker exec ollama ollama pull mistral

# Remove model
docker exec ollama ollama rm mistral
```

**Stable Diffusion Models**:
```bash
# Place in respective directories:
/opt/ai-box/models/stable-diffusion/
/opt/ai-box/models/loras/
/opt/ai-box/models/vae/
```

## 🔍 Monitoring

### GPU Status
```bash
# System GPUs
nvidia-smi

# Container GPU access
docker exec localai nvidia-smi
```

### Service Health
```bash
# Check service endpoints
curl http://localhost:8080/readyz      # LocalAI
curl http://localhost:11434/           # Ollama
curl http://localhost:7860/            # Forge
curl http://localhost:9400/metrics     # DCGM
```

### Dashboard
If enabled, access the web dashboard at `http://your-server/` for:
- Service status monitoring
- GPU utilization graphs
- Quick access to all UIs
- Real-time metrics

## 🎯 Common Use Cases

### Running LLMs
```bash
# With Ollama
docker exec ollama ollama run llama2:13b

# With LocalAI (OpenAI compatible)
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama2-13b",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Generating Images
```python
# Using Forge API
import requests
import base64

response = requests.post('http://localhost:7860/sdapi/v1/txt2img', json={
    "prompt": "cyberpunk city at night",
    "negative_prompt": "blurry, low quality",
    "steps": 30,
    "sampler_name": "DPM++ 2M Karras",
    "cfg_scale": 7,
    "width": 1024,
    "height": 1024
})

# Save image
image_data = response.json()['images'][0]
with open('output.png', 'wb') as f:
    f.write(base64.b64decode(image_data))
```

## 🔧 Troubleshooting

### Services Not Starting
```bash
# Check logs
docker compose logs [service-name]

# Verify GPU access
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

### GPU Memory Issues
```bash
# Check GPU memory usage
nvidia-smi

# Restart service to free memory
docker compose restart forge
```

### Port Conflicts
```bash
# Check what's using a port
sudo lsof -i:8080

# Change ports in .env file
LOCALAI_PORT=8090
OLLAMA_PORT=11435
FORGE_PORT=7861
```

## 📈 Performance Tips

### For LLMs
- Use quantized models (GGUF format) for better memory efficiency
- Enable GPU layers in LocalAI for acceleration
- Consider using multiple GPUs for larger models

### For Image Generation
- Enable xformers in Forge for memory optimization
- Use appropriate batch sizes based on GPU memory
- Consider SDXL models for quality, SD 1.5 for speed

### System Optimization
```bash
# Set GPU persistence mode
sudo nvidia-smi -pm 1

# Monitor GPU usage
watch -n 1 nvidia-smi
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing`)
3. Commit changes (`git commit -m 'Add feature'`)
4. Push to branch (`git push origin feature/amazing`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License.

## 🔗 Resources

- [LocalAI Documentation](https://localai.io/)
- [Ollama Documentation](https://github.com/jmorganca/ollama)
- [Stable Diffusion Forge](https://github.com/lllyasviel/stable-diffusion-webui-forge)
- [NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-container-toolkit)

---

**Built with ❤️ for the AI community**