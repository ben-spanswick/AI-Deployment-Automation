#!/usr/bin/env python3
"""
AI Box Dashboard Backend v2
Comprehensive service monitoring with system information
"""

from flask import Flask, jsonify, request
from flask_cors import CORS
import docker
import psutil
import subprocess
import json
import time
import threading
from datetime import datetime
import os
import re

app = Flask(__name__)
CORS(app)

# Docker client - fix for docker socket issue
try:
    # Try to connect with explicit unix socket
    client = docker.DockerClient(base_url='unix://var/run/docker.sock')
except:
    # Fallback to from_env
    client = docker.from_env()

# Cache for performance
cache = {
    'services': {'data': None, 'timestamp': 0},
    'system': {'data': None, 'timestamp': 0},
    'gpu': {'data': None, 'timestamp': 0}
}
CACHE_TTL = 2  # seconds

# Service port mappings (for direct access URLs)
SERVICE_PORTS = {
    'localai': 8080,
    'ollama': 11434,
    'forge': 7860,
    'comfyui': 8188,
    'n8n': 5678,
    'chromadb': 8000,
    'whisper': 9000,
    'dashboard': 80,
    'dcgm-exporter': 9400
}

# Service categories
SERVICE_CATEGORIES = {
    'localai': 'LLM Services',
    'ollama': 'LLM Services',
    'forge': 'Image Generation',
    'comfyui': 'Image Generation',
    'n8n': 'Automation',
    'chromadb': 'Database',
    'whisper': 'Audio',
    'dcgm-exporter': 'Monitoring',
    'dashboard': 'Monitoring',
    'dashboard-backend': 'Monitoring'
}

def get_nvidia_info():
    """Get NVIDIA driver and CUDA versions"""
    try:
        # Get nvidia-smi output
        result = subprocess.run(['nvidia-smi', '--query-gpu=driver_version,name,memory.total', '--format=csv,noheader'], 
                              capture_output=True, text=True)
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')
            gpu_info = []
            for line in lines:
                parts = line.split(', ')
                if len(parts) >= 3:
                    gpu_info.append({
                        'driver': parts[0],
                        'name': parts[1],
                        'memory': parts[2]
                    })
            
            # Get CUDA version from nvidia-smi
            cuda_result = subprocess.run(['nvidia-smi'], capture_output=True, text=True)
            cuda_version = None
            if cuda_result.returncode == 0:
                match = re.search(r'CUDA Version:\s*(\d+\.\d+)', cuda_result.stdout)
                if match:
                    cuda_version = match.group(1)
            
            # Get installed CUDA toolkit version
            toolkit_version = None
            if os.path.exists('/usr/local/cuda/version.txt'):
                with open('/usr/local/cuda/version.txt', 'r') as f:
                    content = f.read()
                    match = re.search(r'CUDA Version\s+(\d+\.\d+)', content)
                    if match:
                        toolkit_version = match.group(1)
            elif subprocess.run(['nvcc', '--version'], capture_output=True).returncode == 0:
                nvcc_result = subprocess.run(['nvcc', '--version'], capture_output=True, text=True)
                match = re.search(r'release\s+(\d+\.\d+)', nvcc_result.stdout)
                if match:
                    toolkit_version = match.group(1)
            
            return {
                'gpus': gpu_info,
                'cuda_driver': cuda_version,
                'cuda_toolkit': toolkit_version
            }
    except Exception as e:
        print(f"Error getting NVIDIA info: {e}")
    return None

def get_container_stats(container):
    """Get container resource usage"""
    try:
        stats = container.stats(stream=False)
        
        # CPU usage calculation
        cpu_delta = stats['cpu_stats']['cpu_usage']['total_usage'] - stats['precpu_stats']['cpu_usage']['total_usage']
        system_delta = stats['cpu_stats']['system_cpu_usage'] - stats['precpu_stats']['system_cpu_usage']
        cpu_percent = 0.0
        if system_delta > 0 and cpu_delta > 0:
            cpu_percent = (cpu_delta / system_delta) * len(stats['cpu_stats']['cpu_usage']['percpu_usage']) * 100.0
        
        # Memory usage
        mem_usage = stats['memory_stats']['usage']
        mem_limit = stats['memory_stats']['limit']
        mem_percent = (mem_usage / mem_limit) * 100.0 if mem_limit > 0 else 0
        
        return {
            'cpu': round(cpu_percent, 2),
            'memory': {
                'usage': mem_usage,
                'limit': mem_limit,
                'percent': round(mem_percent, 2)
            }
        }
    except:
        return None

@app.route('/api/system')
def get_system_info():
    """Get system information including GPU details"""
    now = time.time()
    
    # Check cache
    if cache['system']['data'] and (now - cache['system']['timestamp']) < CACHE_TTL:
        return jsonify(cache['system']['data'])
    
    # Get system info
    nvidia_info = get_nvidia_info()
    
    system_data = {
        'hostname': os.uname().nodename,
        'os': f"{os.uname().sysname} {os.uname().release}",
        'cpu': {
            'count': psutil.cpu_count(),
            'usage': psutil.cpu_percent(interval=0.1)
        },
        'memory': {
            'total': psutil.virtual_memory().total,
            'used': psutil.virtual_memory().used,
            'percent': psutil.virtual_memory().percent
        },
        'disk': {
            'total': psutil.disk_usage('/').total,
            'used': psutil.disk_usage('/').used,
            'percent': psutil.disk_usage('/').percent
        },
        'nvidia': nvidia_info,
        'timestamp': datetime.now().isoformat()
    }
    
    # Cache the result
    cache['system']['data'] = system_data
    cache['system']['timestamp'] = now
    
    return jsonify(system_data)

@app.route('/api/services')
def get_services():
    """Get all services with their status and resource usage"""
    now = time.time()
    
    # Check cache
    if cache['services']['data'] and (now - cache['services']['timestamp']) < CACHE_TTL:
        return jsonify(cache['services']['data'])
    
    try:
        containers = client.containers.list(all=True)
        services = []
        
        for container in containers:
            # Check if container is on ai-network
            networks = container.attrs.get('NetworkSettings', {}).get('Networks', {})
            if 'ai-network' not in networks:
                continue
            
            # Get container info
            name = container.name
            status = container.status
            image = container.image.tags[0] if container.image.tags else 'unknown'
            
            # Get ports
            ports = container.ports
            port_mappings = []
            for internal, external in ports.items():
                if external:
                    for mapping in external:
                        port_mappings.append({
                            'internal': internal,
                            'external': mapping.get('HostPort')
                        })
            
            # Get resource stats if running
            stats = None
            if status == 'running':
                stats = get_container_stats(container)
            
            # Get category
            category = SERVICE_CATEGORIES.get(name, 'Other')
            
            # Get default port for URL
            default_port = SERVICE_PORTS.get(name)
            
            service_info = {
                'name': name,
                'status': status,
                'image': image,
                'category': category,
                'ports': port_mappings,
                'default_port': default_port,
                'created': container.attrs['Created'],
                'stats': stats
            }
            
            services.append(service_info)
        
        # Sort by category and name
        services.sort(key=lambda x: (x['category'], x['name']))
        
        result = {
            'services': services,
            'count': len(services),
            'timestamp': datetime.now().isoformat()
        }
        
        # Cache the result
        cache['services']['data'] = result
        cache['services']['timestamp'] = now
        
        return jsonify(result)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/services/<service_name>/<action>', methods=['POST'])
def control_service(service_name, action):
    """Control a service (start/stop/restart)"""
    try:
        container = client.containers.get(service_name)
        
        if action == 'start':
            container.start()
            message = f"{service_name} started"
        elif action == 'stop':
            container.stop()
            message = f"{service_name} stopped"
        elif action == 'restart':
            container.restart()
            message = f"{service_name} restarted"
        else:
            return jsonify({'error': 'Invalid action'}), 400
        
        # Clear cache
        cache['services']['data'] = None
        
        return jsonify({'status': 'success', 'message': message})
        
    except docker.errors.NotFound:
        return jsonify({'error': f'Service {service_name} not found'}), 404
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/services/<service_name>/logs')
def get_service_logs(service_name):
    """Get recent logs for a service"""
    try:
        container = client.containers.get(service_name)
        logs = container.logs(tail=100, timestamps=True).decode('utf-8')
        
        return jsonify({
            'service': service_name,
            'logs': logs.split('\n')
        })
        
    except docker.errors.NotFound:
        return jsonify({'error': f'Service {service_name} not found'}), 404
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/gpu/metrics')
def get_gpu_metrics():
    """Get detailed GPU metrics"""
    try:
        result = subprocess.run([
            'nvidia-smi', 
            '--query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,power.limit',
            '--format=csv,noheader,nounits'
        ], capture_output=True, text=True)
        
        if result.returncode != 0:
            return jsonify({'error': 'Failed to get GPU metrics'}), 500
        
        gpus = []
        for line in result.stdout.strip().split('\n'):
            parts = line.split(', ')
            if len(parts) >= 9:
                gpus.append({
                    'index': int(parts[0]),
                    'name': parts[1],
                    'temperature': float(parts[2]),
                    'gpu_util': float(parts[3]),
                    'mem_util': float(parts[4]),
                    'mem_used': float(parts[5]),
                    'mem_total': float(parts[6]),
                    'power_draw': float(parts[7]),
                    'power_limit': float(parts[8])
                })
        
        return jsonify({
            'gpus': gpus,
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/health')
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

if __name__ == '__main__':
    print("AI Box Dashboard Backend v2 starting...")
    app.run(host='0.0.0.0', port=5000, debug=False)