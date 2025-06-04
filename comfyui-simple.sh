#!/bin/bash
# Simple ComfyUI setup with standard image

echo "Setting up ComfyUI with standard image..."

# Stop any existing ComfyUI
docker stop comfyui 2>/dev/null && docker rm comfyui 2>/dev/null

# Use the standard ComfyUI image without specific CUDA version
docker run -d \
  --name comfyui \
  --gpus '"device=0"' \
  -p 8188:8188 \
  -v /opt/ai-box/comfyui:/home/runner \
  -v /opt/ai-box/models:/home/runner/models \
  -e CLI_ARGS="--listen" \
  --restart unless-stopped \
  --network ai-network \
  yanwk/comfyui-boot:latest

echo "ComfyUI starting..."
echo "Check logs with: docker logs comfyui -f"
echo "Access at: http://localhost:8188"