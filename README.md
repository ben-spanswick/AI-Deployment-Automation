# AI Box - Unified GPU-Accelerated AI Services Platform

![AI Box Dashboard](dashboard.png)

## Overview

AI Box is a comprehensive, production-ready platform for deploying GPU-accelerated AI services on Linux systems. It provides a unified interface for managing multiple AI services including LLMs, image generation, vector databases, and workflow automation.

This project was developed to simplify the deployment and management of various AI services on local GPU-equipped machines, providing a unified dashboard and consistent management interface for researchers, developers, and AI enthusiasts.

### Key Features

- **🚀 Easy Deployment**: One-command installation with automatic GPU detection
- **🎮 Unified Dashboard**: Web-based control panel for all services
- **🔧 Modular Architecture**: Add or remove services as needed
- **📊 GPU Monitoring**: Real-time GPU metrics and resource usage
- **🐳 Docker-Based**: Consistent deployment across systems
- **🔒 Security First**: Isolated services with configurable access controls

## Quick Start

```bash
# Clone the repository
git clone http://192.168.100.54:3000/Mandrake/AI-Deployment.git
cd AI-Deployment

# Run the installer
sudo ./setup.sh

# Follow the interactive prompts to select services
```

## Supported Services

### Language Models (LLMs)
- **LocalAI**: OpenAI-compatible API for local LLMs
- **Ollama**: Simple model management with extensive model library

### Image Generation
- **Stable Diffusion Forge**: Optimized SD WebUI with advanced features
- **ComfyUI**: Node-based workflow system with FLUX support

### Infrastructure
- **ChromaDB**: Vector database for RAG applications
- **n8n**: Workflow automation and AI chain orchestration
- **Whisper**: Speech-to-text transcription

### Monitoring & Management
- **Dashboard**: Unified web interface
- **DCGM Exporter**: NVIDIA GPU metrics collection

## System Requirements

### Minimum Requirements
- Ubuntu 20.04+ or compatible Linux distribution
- NVIDIA GPU with 8GB+ VRAM
- 16GB system RAM
- 100GB free storage
- Docker 20.10+ with NVIDIA Container Toolkit

### Recommended Requirements
- Ubuntu 22.04 LTS
- NVIDIA RTX 3090/4090 or better
- 32GB+ system RAM
- 500GB+ NVMe SSD
- Stable internet connection

## Installation

### Standard Installation

```bash
# Make script executable
chmod +x setup.sh

# Run with sudo
sudo ./setup.sh
```

### Custom Installation

```bash
# Install specific services
sudo ./setup.sh --services localai,forge,chromadb

# Custom directories
sudo ./setup.sh --data-dir /mnt/ai-data --models-dir /mnt/ai-models

# Custom ports
sudo ./setup.sh --localai-port 8081 --forge-port 7861
```

## Configuration

### Main Configuration File
Edit `config/aibox.conf` to customize:
- Installation directories
- Port assignments
- GPU allocation
- Performance settings

### Service-Specific Configuration
Each service can be configured through:
- Environment variables in `docker/.env`
- Service-specific config files in `config/`
- Docker Compose overrides

## Usage

### Dashboard Access
After installation, access the dashboard at:
```
http://localhost:8090
```

### Service Endpoints
- LocalAI: `http://localhost:8080`
- Ollama: `http://localhost:11434`
- Stable Diffusion Forge: `http://localhost:7860`
- ComfyUI: `http://localhost:8188`
- ChromaDB: `http://localhost:8000`
- n8n: `http://localhost:5678`

### Managing Services

```bash
# Check service status
./scripts/check-status.sh

# Manage dashboard
./scripts/manage-dashboard.sh status

# Control Docker services
./scripts/docker-control.sh [start|stop|restart] [service-name]
```

## Project Structure

```
ai-box/
├── README.md                 # This file
├── setup.sh                  # Main installer
├── dashboard.html            # Web dashboard
├── dashboard-backend.py      # Dashboard API server
├── config/                   # Configuration files
│   ├── aibox.conf           # Main configuration
│   └── *.conf               # Service configs
├── docker/                   # Docker configurations
│   ├── docker-compose.yml   # Main compose file
│   └── nginx/               # Nginx configs
├── scripts/                  # Utility scripts
│   ├── check-status.sh      # Service status checker
│   ├── manage-dashboard.sh  # Dashboard management
│   └── ...                  # Other utilities
└── ansible/                  # Deployment automation
    └── playbook.yml         # Ansible playbook
```

## Advanced Features

### GPU Management
- Automatic GPU detection and allocation
- Multi-GPU support with configurable assignment
- VRAM limits per service
- Real-time GPU monitoring

### Model Management
- Centralized model storage
- Shared models between services
- Automatic model downloading
- Model conversion utilities

### Security Features
- Service isolation
- Optional authentication
- Network segmentation
- API key management

## Troubleshooting

### Common Issues

1. **GPU not detected**
   ```bash
   # Check NVIDIA drivers
   nvidia-smi
   
   # Reinstall NVIDIA Container Toolkit
   ./scripts/fix-gpu.sh
   ```

2. **Service won't start**
   ```bash
   # Check logs
   docker logs [service-name]
   
   # Restart service
   ./scripts/docker-control.sh restart [service-name]
   ```

3. **Dashboard not accessible**
   ```bash
   # Fix dashboard issues
   sudo ./scripts/manage-dashboard.sh fix
   ```

### Getting Help

- Check logs in `/opt/ai-box/logs/`
- Run diagnostic: `./scripts/check-status.sh --diagnose`
- Check the detailed documentation: [details.md](details.md)
- Submit issues: http://192.168.100.54:3000/Mandrake/AI-Deployment/issues

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
# Clone with submodules
git clone --recursive http://192.168.100.54:3000/Mandrake/AI-Deployment.git

# Install development dependencies
./scripts/setup-dev.sh

# Run tests
./scripts/run-tests.sh
```

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- NVIDIA for GPU acceleration tools
- Docker for containerization
- All the amazing open-source AI projects included

---

**Note**: This project integrates multiple open-source AI tools. Please review individual licenses for commercial use.

For more detailed information, see [details.md](details.md) for comprehensive documentation, troubleshooting, and technical notes.