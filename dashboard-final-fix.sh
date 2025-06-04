#!/bin/bash
# Final dashboard fix with working backend

# Stop all dashboard services
docker stop dashboard dashboard-backend dcgm-exporter 2>/dev/null
docker rm dashboard dashboard-backend dcgm-exporter 2>/dev/null

# Create the working backend
cat > /opt/ai-box/dashboard-backend.py << 'EOF'
#!/usr/bin/env python3
from flask import Flask, jsonify
from flask_cors import CORS
import subprocess
import json
import os
from datetime import datetime

app = Flask(__name__)
CORS(app)

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        return result.stdout.strip()
    except:
        return ""

@app.route('/api/services')
def get_services():
    services = []
    
    # Get container info using docker CLI
    cmd = "docker ps -a --no-trunc --format '{{.Names}}|{{.Status}}|{{.Image}}|{{.Networks}}'"
    output = run_cmd(cmd)
    
    for line in output.split('\n'):
        if '|' in line:
            parts = line.split('|')
            if len(parts) >= 4:
                name = parts[0].strip()
                status_raw = parts[1].strip()
                image = parts[2].strip()
                networks = parts[3].strip()
                
                # Only include containers on ai-network
                if 'ai-network' in networks:
                    # Parse status
                    if 'Up' in status_raw:
                        status = 'running'
                    elif 'Exited' in status_raw:
                        status = 'stopped'
                    elif 'Restarting' in status_raw:
                        status = 'restarting'
                    else:
                        status = 'unknown'
                    
                    # Get port info
                    port_cmd = f"docker port {name} 2>/dev/null"
                    port_output = run_cmd(port_cmd)
                    
                    # Categorize
                    category = 'Other'
                    if name in ['localai', 'ollama']:
                        category = 'LLM Services'
                    elif name in ['forge', 'comfyui']:
                        category = 'Image Generation'
                    elif name == 'n8n':
                        category = 'Automation'
                    elif name == 'chromadb':
                        category = 'Database'
                    elif name == 'whisper':
                        category = 'Audio'
                    elif name in ['dashboard', 'dashboard-backend', 'dcgm-exporter']:
                        category = 'Monitoring'
                    
                    services.append({
                        'name': name,
                        'status': status,
                        'image': image,
                        'category': category,
                        'default_port': get_default_port(name)
                    })
    
    return jsonify({
        'services': services,
        'count': len(services),
        'timestamp': datetime.now().isoformat()
    })

def get_default_port(service):
    ports = {
        'localai': 8080,
        'ollama': 11434,
        'forge': 7860,
        'comfyui': 8188,
        'n8n': 5678,
        'chromadb': 8000,
        'whisper': 9000,
        'dashboard': 80
    }
    return ports.get(service)

@app.route('/api/system')
def get_system():
    # Get GPU info
    gpu_info = run_cmd("nvidia-smi --query-gpu=driver_version,name --format=csv,noheader")
    gpus = []
    driver = "Unknown"
    
    for line in gpu_info.split('\n'):
        if ',' in line:
            parts = line.split(',')
            driver = parts[0].strip()
            gpus.append({'name': parts[1].strip(), 'driver': driver})
    
    # Get CUDA version
    cuda_info = run_cmd("nvidia-smi | grep 'CUDA Version'")
    cuda_version = "Unknown"
    if 'CUDA Version:' in cuda_info:
        cuda_version = cuda_info.split('CUDA Version:')[1].split()[0]
    
    # CPU and memory
    cpu_percent = run_cmd("top -bn1 | grep 'Cpu(s)' | awk '{print $2}'").replace('%us,', '')
    mem_info = run_cmd("free -m | grep Mem | awk '{print $3,$2}'").split()
    
    return jsonify({
        'nvidia': {
            'gpus': gpus,
            'cuda_driver': cuda_version
        },
        'cpu': {
            'usage': float(cpu_percent) if cpu_percent else 0
        },
        'memory': {
            'used': int(mem_info[0]) if len(mem_info) > 0 else 0,
            'total': int(mem_info[1]) if len(mem_info) > 1 else 0,
            'percent': round((int(mem_info[0]) / int(mem_info[1])) * 100, 1) if len(mem_info) > 1 else 0
        }
    })

@app.route('/api/gpu/metrics')
def gpu_metrics():
    cmd = "nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits"
    output = run_cmd(cmd)
    
    gpus = []
    for line in output.split('\n'):
        if ',' in line:
            parts = line.split(',')
            if len(parts) >= 7:
                gpus.append({
                    'index': int(parts[0]),
                    'name': parts[1].strip(),
                    'temperature': float(parts[2]),
                    'gpu_util': float(parts[3]),
                    'mem_used': float(parts[4]),
                    'mem_total': float(parts[5]),
                    'mem_util': round((float(parts[4]) / float(parts[5])) * 100, 1),
                    'power_draw': float(parts[6])
                })
    
    return jsonify({'gpus': gpus})

@app.route('/api/services/<name>/<action>', methods=['POST'])
def control_service(name, action):
    if action in ['start', 'stop', 'restart']:
        run_cmd(f"docker {action} {name}")
        return jsonify({'status': 'success', 'message': f'{name} {action}ed'})
    return jsonify({'error': 'Invalid action'}), 400

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    print("Dashboard Backend starting on port 5000...")
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

# Make it executable
chmod +x /opt/ai-box/dashboard-backend.py

# Create simple docker-compose for dashboard
cat > /opt/ai-box/docker-compose.dashboard-final.yml << 'EOF'
version: '3.8'

services:
  dashboard:
    image: nginx:alpine
    container_name: dashboard
    ports:
      - "80:80"
    volumes:
      - /opt/ai-box/nginx/html:/usr/share/nginx/html:ro
      - /opt/ai-box/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    restart: unless-stopped
    networks:
      - ai-network

  dashboard-backend:
    image: python:3.9-slim
    container_name: dashboard-backend
    ports:
      - "5000:5000"
    volumes:
      - /opt/ai-box/dashboard-backend.py:/app/dashboard-backend.py:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    working_dir: /app
    command: bash -c "pip install flask flask-cors && python dashboard-backend.py"
    restart: unless-stopped
    networks:
      - ai-network

  dcgm-exporter:
    image: nvcr.io/nvidia/k8s/dcgm-exporter:3.1.8-3.1.5-ubuntu20.04
    container_name: dcgm-exporter
    ports:
      - "9400:9400"
    environment:
      - DCGM_EXPORTER_LISTEN=0.0.0.0:9400
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              capabilities: [gpu]
              count: all
    restart: unless-stopped
    cap_add:
      - SYS_ADMIN
    networks:
      - ai-network

networks:
  ai-network:
    external: true
EOF

# Deploy
echo "Deploying fixed dashboard..."
cd /opt/ai-box
docker compose -f docker-compose.dashboard-final.yml up -d

echo "Waiting for services to start..."
sleep 15

# Test
echo -e "\nTesting dashboard..."
if curl -s http://localhost:5000/api/services | grep -q "services"; then
    echo "✓ Backend API working"
    echo -e "\nServices detected:"
    curl -s http://localhost:5000/api/services | python3 -c "import json,sys; d=json.load(sys.stdin); [print(f'  - {s[\"name\"]} ({s[\"status\"]})') for s in d['services']]"
else
    echo "✗ Backend API not responding"
fi

echo -e "\n✅ Dashboard available at: http://localhost"