#!/bin/bash
# Quick fix for AI Box services

set -euo pipefail

echo "Stopping all services..."
docker compose -f /home/mandrake/AI-Deployment/docker-compose-fixed.yml down

echo "Creating forge-extensions directory..."
sudo mkdir -p /opt/ai-box/forge-extensions

echo "Starting services..."
sudo docker compose -f /home/mandrake/AI-Deployment/docker-compose-fixed.yml up -d

echo "Waiting for services to start..."
sleep 15

echo "Service status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|forge|comfyui|dashboard|dcgm"

echo ""
echo "Access points:"
echo "- Dashboard: http://localhost"
echo "- SD Forge: http://localhost:1111"
echo "- ComfyUI: http://localhost:8188"
echo ""
echo "Note: SD Forge needs at least one model in /opt/ai-box/models/stable-diffusion/"