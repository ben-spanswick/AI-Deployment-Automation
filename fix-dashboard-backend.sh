#!/bin/bash
# Quick fix for dashboard backend

# Stop broken backend
docker stop dashboard-backend 2>/dev/null
docker rm dashboard-backend 2>/dev/null

# Update the backend file directly
cat > /tmp/dashboard-backend-fixed.py << 'EOF'
#!/usr/bin/env python3
from flask import Flask, jsonify
from flask_cors import CORS
import subprocess
import json
import time
import os
import re
from datetime import datetime

app = Flask(__name__)
CORS(app)

# Cache
cache = {'timestamp': 0, 'data': {}}
CACHE_TTL = 2

def run_command(cmd):
    """Run a shell command and return output"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.stdout
    except:
        return ""

def get_docker_services():
    """Get Docker services using docker CLI"""
    services = []
    
    # Get all containers
    output = run_command("docker ps -a --format 'table {{.Names}}|{{.Status}}|{{.Image}}|{{.Ports}}'")
    lines = output.strip().split('\n')[1:]  # Skip header
    
    for line in lines:
        if '|' in line:
            parts = line.split('|')
            if len(parts) >= 3:
                name = parts[0].strip()
                status = parts[1].strip()
                image = parts[2].strip()
                
                # Check if on ai-network
                network_check = run_command(f"docker inspect {name} --format '{{{{.NetworkSettings.Networks}}}}' 2>/dev/null")
                if 'ai-network' in network_check:
                    services.append({
                        'name': name,
                        'status': 'running' if 'Up' in status else 'stopped',
                        'image': image,
                        'category': categorize_service(name)
                    })
    
    return services

def categorize_service(name):
    """Categorize service by name"""
    categories = {
        'localai': 'LLM Services',
        'ollama': 'LLM Services',
        'forge': 'Image Generation',
        'comfyui': 'Image Generation',
        'n8n': 'Automation',
        'chromadb': 'Database',
        'whisper': 'Audio',
        'dcgm': 'Monitoring',
        'dashboard': 'Monitoring'
    }
    
    for key, category in categories.items():
        if key in name.lower():
            return category
    return 'Other'

@app.route('/api/services')
def get_services():
    now = time.time()
    
    if cache['data'] and (now - cache['timestamp']) < CACHE_TTL:
        return jsonify(cache['data'])
    
    services = get_docker_services()
    result = {
        'services': services,
        'count': len(services),
        'timestamp': datetime.now().isoformat()
    }
    
    cache['data'] = result
    cache['timestamp'] = now
    
    return jsonify(result)

@app.route('/api/system')
def get_system_info():
    # Get NVIDIA info
    nvidia_smi = run_command("nvidia-smi --query-gpu=driver_version,name --format=csv,noheader")
    driver_version = "Unknown"
    gpu_names = []
    
    if nvidia_smi:
        for line in nvidia_smi.strip().split('\n'):
            parts = line.split(', ')
            if len(parts) >= 2:
                driver_version = parts[0]
                gpu_names.append(parts[1])
    
    # Get CUDA version
    cuda_version = "Unknown"
    cuda_check = run_command("nvidia-smi | grep 'CUDA Version'")
    match = re.search(r'CUDA Version:\s*(\d+\.\d+)', cuda_check)
    if match:
        cuda_version = match.group(1)
    
    return jsonify({
        'nvidia': {
            'gpus': [{'driver': driver_version, 'name': name} for name in gpu_names],
            'cuda_driver': cuda_version
        },
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/gpu/metrics')
def get_gpu_metrics():
    output = run_command("nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits")
    gpus = []
    
    for line in output.strip().split('\n'):
        parts = line.split(', ')
        if len(parts) >= 6:
            gpus.append({
                'index': int(parts[0]),
                'name': parts[1],
                'temperature': float(parts[2]),
                'gpu_util': float(parts[3]),
                'mem_used': float(parts[4]),
                'mem_total': float(parts[5])
            })
    
    return jsonify({'gpus': gpus})

@app.route('/api/services/<service>/<action>', methods=['POST'])
def control_service(service, action):
    if action in ['start', 'stop', 'restart']:
        run_command(f"docker {action} {service}")
        return jsonify({'status': 'success'})
    return jsonify({'error': 'Invalid action'}), 400

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# Create a simple Dockerfile
cat > /tmp/dashboard-backend-simple.Dockerfile << 'EOF'
FROM python:3.9-slim
WORKDIR /app
RUN pip install flask flask-cors
COPY dashboard-backend-fixed.py /app/dashboard-backend.py
CMD ["python", "-u", "dashboard-backend.py"]
EOF

# Build and run the fixed backend
cd /tmp
docker build -f dashboard-backend-simple.Dockerfile -t dashboard-backend-fixed .
docker run -d \
  --name dashboard-backend \
  --network ai-network \
  -p 5000:5000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --restart unless-stopped \
  dashboard-backend-fixed

echo "Waiting for backend to start..."
sleep 5

# Test the backend
echo "Testing backend..."
if curl -s http://localhost:5000/health | grep -q "healthy"; then
    echo "✓ Backend is working!"
else
    echo "✗ Backend failed to start"
    docker logs dashboard-backend
fi