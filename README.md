# 🤖 AI Box - Dynamic Multi-GPU Deployment

> Flexible, automated deployment of a headless AI workstation with support for any number of NVIDIA GPUs. Features LLM chat, image generation, and inference APIs with intelligent GPU assignment.

[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%20%7C%2022.04-orange)](https://ubuntu.com/)
[![NVIDIA](https://img.shields.io/badge/NVIDIA-RTX%203090%20%7C%204090%20%7C%20A100-76B900)](https://www.nvidia.com/)
[![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED)](https://www.docker.com/)
[![Ansible](https://img.shields.io/badge/Ansible-2.15+-EE0000)](https://www.ansible.com/)

## 🎯 Features

- **Dynamic GPU Detection**: Automatically detects and configures any number of NVIDIA GPUs
- **Flexible GPU Assignment**: Choose automatic distribution or manual GPU assignment per service
- **Multiple Deployment Methods**: Ansible, Docker Compose, or hybrid deployment
- **Interactive Setup**: User-friendly setup script with smart defaults
- **Service Options**:
  - Text Generation WebUI (Oobabooga) - LLM chat interface
  - Stable Diffusion WebUI - AI image generation
  - FastAPI - REST API for programmatic access
  - GPU Monitoring (optional) - NVIDIA DCGM metrics
  - Web Dashboard (optional) - Unified access portal
  - Auto Updates (optional) - Watchtower container updates

## 📋 Requirements

- **OS**: Ubuntu 20.04 or 22.04 (headless or desktop)
- **GPU**: One or more NVIDIA GPUs (RTX 3090, 4090, A100, etc.)
- **RAM**: 32GB+ recommended (16GB minimum)
- **Storage**: 500GB+ for models and outputs
- **Network**: SSH access and sudo privileges

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone http://192.168.100.54:3000/Mandrake/AI-Deployment.git
cd AI-Deployment
```

### 2. Run the Setup Script

```bash
chmod +x setup.sh
./setup.sh
```

The script will:
- Detect your GPU configuration
- Ask for deployment preferences
- Configure services based on your hardware
- Deploy the AI Box automatically

### 3. Access Your Services

After deployment, access your services at:
- **LLM Chat**: `http://your-server:8080`
- **Image Generation**: `http://your-server:8081`
- **API Docs**: `http://your-server:8000/docs`
- **GPU Metrics**: `http://your-server:9400/metrics` (if enabled)
- **Dashboard**: `http://your-server` (if enabled)

## 🔧 Deployment Options

### Interactive Setup (Recommended)

The `setup.sh` script provides an interactive experience:

```bash
./setup.sh
```

You'll be prompted for:
- Deployment method (Ansible/Docker/Hybrid)
- Target machine (local/remote)
- GPU assignment strategy
- Service ports
- Optional features

### Manual Deployment

#### Option 1: Ansible (Full System Setup)

```bash
cd ansible
# Edit inventory.yml with your configuration
ansible-playbook -i inventory.yml playbook.yml
```

#### Option 2: Docker Compose Only

```bash
cd docker
# Edit .env file with your configuration
docker compose up -d
```

#### Option 3: Custom Configuration

1. Run GPU detection:
```bash
./scripts/gpu-detect.sh
```

2. Create configuration:
```bash
cp docker/.env.example docker/.env
# Edit docker/.env with your settings
```

3. Deploy:
```bash
cd docker && docker compose up -d
```

## 🎮 GPU Assignment Strategies

### Automatic Assignment

The setup script can automatically distribute GPUs based on your hardware:

- **1 GPU**: All services share the same GPU
- **2 GPUs**: 
  - Text Generation: GPU 0
  - Stable Diffusion: GPU 1
  - FastAPI: Access to both
- **3+ GPUs**: Distributed across services with extras for scaling

### Manual Assignment

Specify exactly which GPUs each service should use:

```bash
Text Generation GPU(s): 0
Stable Diffusion GPU(s): 1
FastAPI GPU(s): 0,1,2,3
```

### Single GPU Mode

Run all services on a single powerful GPU:

```bash
Which GPU to use: 0
```

## 📊 Service Management

### View Service Status

```bash
docker ps
docker compose -f /opt/ai-box/docker-compose.yml ps
```

### View Logs

```bash
# All services
cd /opt/ai-box && docker compose logs -f

# Specific service
docker compose logs -f textgen-webui
```

### Restart Services

```bash
cd /opt/ai-box
docker compose restart
docker compose restart textgen-webui  # Single service
```

### Update Services

```bash
cd /opt/ai-box
docker compose pull
docker compose up -d
```

## 🔍 Monitoring & Troubleshooting

### Check GPU Status

```bash
# System GPUs
nvidia-smi

# GPUs in Docker
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi
```

### Health Checks

```bash
./scripts/health-check.sh
```

### Common Issues

**GPU Not Detected:**
```bash
# Check driver
nvidia-smi
# Reinstall driver
sudo apt install nvidia-driver-535
```

**Service Not Starting:**
```bash
# Check logs
docker compose logs textgen-webui
# Check GPU assignment
docker compose exec textgen-webui nvidia-smi
```

**Port Conflicts:**
```bash
# Check ports
sudo netstat -tulpn | grep -E "(8080|8081|8000)"
# Change in .env file
```

## 🎨 Customization

### Adding Models

```bash
# Text Generation models
cd /opt/ai-box/models
git lfs clone https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF

# Stable Diffusion models
wget https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned.safetensors
```

### Modifying GPU Memory Allocation

Edit the Docker Compose file:
```yaml
environment:
  - EXTRA_LAUNCH_ARGS=--listen --api --gpu-memory 20  # GB per GPU
```

### Custom Port Configuration

During setup, specify custom ports:
```
Text Generation WebUI port: 8888
Stable Diffusion WebUI port: 9999
FastAPI port: 7777
```

## 📈 Performance Optimization

### For Multiple GPUs

- Use model parallelism for large models
- Distribute different models across GPUs
- Enable GPU-to-GPU communication

### Memory Optimization

- Use FP16 precision for inference
- Enable gradient checkpointing
- Consider model quantization

### System Tuning

```bash
# Enable persistence mode
sudo nvidia-smi -pm 1

# Set power limit (watts)
sudo nvidia-smi -pl 350
```

## 🔐 Security

### Firewall Configuration

The deployment automatically configures UFW:
```bash
# Check status
sudo ufw status

# Restrict to local network
sudo ufw allow from 192.168.1.0/24 to any port 8080
```

### SSL/HTTPS

For production, add SSL termination:
```nginx
server {
    listen 443 ssl;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    # ... proxy configuration
}
```

## 📚 API Usage

### FastAPI Endpoints

```python
import requests

# Load model
response = requests.post("http://localhost:8000/load_model", json={
    "model_name": "microsoft/DialoGPT-medium",
    "precision": "fp16"
})

# Generate text
response = requests.post("http://localhost:8000/generate", json={
    "prompt": "Hello, how are you?",
    "max_length": 100,
    "temperature": 0.7
})
```

### Stable Diffusion API

```python
# Generate image
response = requests.post("http://localhost:8081/sdapi/v1/txt2img", json={
    "prompt": "a beautiful sunset over mountains",
    "steps": 20,
    "width": 512,
    "height": 512
})
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

- Check the [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- Review [GPU Assignment Guide](docs/GPU-ASSIGNMENT.md)
- See [API Usage Examples](docs/API-USAGE.md)

## 🙏 Acknowledgments

- [Oobabooga Text Generation WebUI](https://github.com/oobabooga/text-generation-webui)
- [AUTOMATIC1111 Stable Diffusion WebUI](https://github.com/AUTOMATIC1111/stable-diffusion-webui)
- [NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-container-toolkit)

---

**Happy AI Boxing!** 🚀🤖