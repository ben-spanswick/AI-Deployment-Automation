#!/usr/bin/env python3
"""
AI Box Dashboard - Grid layout with proper GPU display
"""

from flask import Flask, jsonify, send_from_directory, Response
import subprocess
import json
import os
import time
from datetime import datetime
import threading

app = Flask(__name__)

# HTML content embedded in Python to avoid file dependencies
DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Box Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0f0f0f;
            color: #e0e0e0;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
        }
        
        header {
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            padding: 1.5rem 2rem;
            box-shadow: 0 4px 20px rgba(0,0,0,0.5);
        }
        
        .header-content {
            max-width: 1800px;
            margin: 0 auto;
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 2rem;
            flex-wrap: wrap;
        }
        
        .header-left {
            display: flex;
            align-items: center;
            gap: 3rem;
        }
        
        h1 {
            font-size: 2.5rem;
            background: linear-gradient(135deg, #00ff88 0%, #00b4d8 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            display: inline-block;
            margin: 0;
        }
        
        .subtitle { 
            color: #888; 
            font-size: 1rem;
            margin-top: 0.25rem;
        }
        
        .system-stats {
            display: flex;
            gap: 2rem;
            align-items: center;
        }
        
        .stat-item {
            text-align: center;
        }
        
        .stat-item .value {
            font-size: 1.8rem;
            font-weight: bold;
            color: #00ff88;
        }
        
        .stat-item .label {
            color: #666;
            font-size: 0.8rem;
            text-transform: uppercase;
            margin-top: 0.25rem;
        }
        
        .gpu-section {
            background: rgba(0,0,0,0.3);
            padding: 1rem;
            border-radius: 8px;
            min-width: 320px;
            max-width: 400px;
        }
        
        .gpu-header {
            font-size: 0.9rem;
            color: #00ff88;
            margin-bottom: 0.5rem;
            font-weight: 600;
            text-align: center;
        }
        
        .gpu-system-info {
            display: flex;
            justify-content: space-between;
            margin-bottom: 0.75rem;
            padding-bottom: 0.5rem;
            border-bottom: 1px solid rgba(255,255,255,0.1);
            font-size: 0.8rem;
        }
        
        .gpu-system-item {
            text-align: center;
        }
        
        .gpu-system-label {
            color: #666;
            font-size: 0.7rem;
            text-transform: uppercase;
        }
        
        .gpu-system-value {
            color: #00b4d8;
            font-weight: 500;
            margin-top: 0.2rem;
        }
        
        .gpu-metrics {
            display: flex;
            flex-direction: column;
            gap: 0.5rem;
        }
        
        .gpu-card {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0.5rem;
            background: rgba(255,255,255,0.05);
            border-radius: 4px;
            font-size: 0.8rem;
        }
        
        .gpu-name {
            color: #fff;
            font-weight: 500;
            flex: 1;
            text-align: left;
        }
        
        .gpu-stats {
            display: flex;
            gap: 1rem;
        }
        
        .gpu-stat-item {
            text-align: center;
        }
        
        .gpu-stat-value {
            font-weight: bold;
            color: #00ff88;
            font-size: 0.9rem;
        }
        
        .gpu-stat-label {
            color: #888;
            font-size: 0.6rem;
            text-transform: uppercase;
        }
        
        main {
            flex: 1;
            padding: 2rem;
            max-width: 1800px;
            margin: 0 auto;
            width: 100%;
        }
        
        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }
        
        .service-card {
            background: #1a1a2e;
            border-radius: 12px;
            padding: 1.5rem;
            border: 1px solid #2a2a3e;
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
        }
        
        .service-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 4px;
            background: linear-gradient(90deg, #00ff88, #00b4d8);
            transform: scaleX(0);
            transition: transform 0.3s ease;
        }
        
        .service-card:hover {
            transform: translateY(-3px);
            box-shadow: 0 10px 30px rgba(0,0,0,0.4);
            border-color: #00ff88;
        }
        
        .service-card:hover::before { transform: scaleX(1); }
        
        .service-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 1rem;
        }
        
        .service-name {
            font-size: 1.3rem;
            font-weight: 600;
            color: #fff;
            text-transform: capitalize;
        }
        
        .status-badge {
            padding: 0.35rem 0.8rem;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: 500;
            text-transform: uppercase;
        }
        
        .status-running {
            background: rgba(0, 255, 136, 0.2);
            color: #00ff88;
            border: 1px solid #00ff88;
        }
        
        .status-stopped, .status-exited {
            background: rgba(255, 107, 107, 0.2);
            color: #ff6b6b;
            border: 1px solid #ff6b6b;
        }
        
        .status-restarting {
            background: rgba(255, 193, 7, 0.2);
            color: #ffc107;
            border: 1px solid #ffc107;
        }
        
        .service-info {
            margin-bottom: 1rem;
        }
        
        .service-detail {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            margin-bottom: 0.5rem;
            font-size: 0.9rem;
            color: #aaa;
        }
        
        .service-detail-label {
            color: #666;
            font-weight: 500;
        }
        
        .service-stats {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 1rem;
            margin: 1rem 0;
            padding: 1rem;
            background: rgba(0,0,0,0.3);
            border-radius: 8px;
        }
        
        .stat {
            text-align: center;
        }
        
        .stat-label {
            color: #666;
            font-size: 0.8rem;
            text-transform: uppercase;
        }
        
        .stat-value {
            color: #00b4d8;
            font-size: 1.2rem;
            font-weight: bold;
            margin-top: 0.25rem;
        }
        
        .service-actions {
            display: flex;
            gap: 0.5rem;
            margin-top: 1rem;
        }
        
        .btn {
            flex: 1;
            padding: 0.6rem 1rem;
            border: none;
            border-radius: 6px;
            font-size: 0.85rem;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s ease;
            text-decoration: none;
            text-align: center;
            color: white;
        }
        
        .btn:hover { transform: translateY(-2px); }
        
        .btn-primary {
            background: linear-gradient(135deg, #00ff88, #00b4d8);
        }
        
        .btn-secondary {
            background: #2a2a3e;
            border: 1px solid #3a3a4e;
        }
        
        .btn-danger { 
            background: #dc3545; 
        }
        
        .btn-start {
            background: #28a745;
        }
        
        .btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        
        .loading {
            text-align: center;
            padding: 4rem;
            color: #666;
        }
        
        .error {
            background: rgba(255, 107, 107, 0.1);
            border: 1px solid #ff6b6b;
            padding: 1rem;
            border-radius: 8px;
            color: #ff6b6b;
            margin: 1rem 0;
        }
        
        footer {
            background: #1a1a2e;
            padding: 1.5rem;
            text-align: center;
            color: #666;
        }
        
        footer a {
            color: #00ff88;
            text-decoration: none;
        }
        
        footer a:hover { text-decoration: underline; }

        @media (max-width: 1400px) {
            .services-grid {
                grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            }
        }
        
        @media (max-width: 768px) {
            .header-content {
                flex-direction: column;
                gap: 1rem;
            }
            .services-grid { 
                grid-template-columns: 1fr; 
            }
            h1 { font-size: 2rem; }
        }
    </style>
</head>
<body>
    <header>
        <div class="header-content">
            <div class="header-left">
                <div>
                    <h1>AI Box Dashboard</h1>
                    <p class="subtitle">GPU-Accelerated AI Services Platform</p>
                </div>
                <div class="system-stats">
                    <div class="stat-item">
                        <div class="value" id="totalServices">-</div>
                        <div class="label">Services</div>
                    </div>
                    <div class="stat-item">
                        <div class="value" id="runningServices">-</div>
                        <div class="label">Running</div>
                    </div>
                    <div class="stat-item">
                        <div class="value" id="cpuUsage">-</div>
                        <div class="label">CPU</div>
                    </div>
                    <div class="stat-item">
                        <div class="value" id="memUsage">-</div>
                        <div class="label">Memory</div>
                    </div>
                </div>
            </div>
            <div class="gpu-section" id="gpuSection">
                <div class="loading">Loading GPU info...</div>
            </div>
        </div>
    </header>
    
    <main>
        <div class="services-grid" id="servicesGrid">
            <div class="loading">Loading services...</div>
        </div>
    </main>
    
    <footer>
        <p>AI Box Dashboard | <a href="/metrics" target="_blank">Raw Metrics</a> | <a href="https://github.com/anthropics/claude-ai-deployment" target="_blank">Documentation</a></p>
    </footer>

    <script>
        const API = {
            system: '/api/system',
            services: '/api/services',
            gpu: '/api/gpu/metrics',
            control: (service, action) => `/api/services/${service}/${action}`
        };

        let services = [];
        let systemInfo = null;
        let gpuMetrics = null;

        async function fetchSystemInfo() {
            try {
                const response = await fetch(API.system);
                systemInfo = await response.json();
                updateSystemInfo();
                updateGPUSection();
            } catch (error) {
                console.error('Failed to fetch system info:', error);
            }
        }

        function updateSystemInfo() {
            if (!systemInfo) return;
            
            document.getElementById('cpuUsage').textContent = `${systemInfo.cpu.usage.toFixed(1)}%`;
            document.getElementById('memUsage').textContent = `${systemInfo.memory.percent.toFixed(1)}%`;
        }

        function updateGPUSection() {
            const container = document.getElementById('gpuSection');
            
            if (!systemInfo || !systemInfo.nvidia || !systemInfo.nvidia.gpus || systemInfo.nvidia.gpus.length === 0) {
                container.innerHTML = '<div class="gpu-header">No GPU Detected</div>';
                return;
            }
            
            const gpus = systemInfo.nvidia.gpus;
            const driver = gpus[0].driver || 'Unknown';
            const cuda = systemInfo.nvidia.cuda_driver || 'Unknown';
            
            let html = `
                <div class="gpu-header">GPU Status</div>
                <div class="gpu-system-info">
                    <div class="gpu-system-item">
                        <div class="gpu-system-label">Driver</div>
                        <div class="gpu-system-value">${driver}</div>
                    </div>
                    <div class="gpu-system-item">
                        <div class="gpu-system-label">CUDA</div>
                        <div class="gpu-system-value">${cuda}</div>
                    </div>
                    <div class="gpu-system-item">
                        <div class="gpu-system-label">Count</div>
                        <div class="gpu-system-value">${gpus.length}</div>
                    </div>
                </div>
            `;
            
            if (gpuMetrics && gpuMetrics.length > 0) {
                html += '<div class="gpu-metrics">';
                gpuMetrics.forEach((gpu, index) => {
                    const gpuName = gpu.name.replace('NVIDIA GeForce ', '').trim();
                    html += `
                        <div class="gpu-card">
                            <div class="gpu-name">${gpuName}</div>
                            <div class="gpu-stats">
                                <div class="gpu-stat-item">
                                    <div class="gpu-stat-value">${gpu.temperature}°</div>
                                    <div class="gpu-stat-label">Temp</div>
                                </div>
                                <div class="gpu-stat-item">
                                    <div class="gpu-stat-value">${gpu.gpu_util}%</div>
                                    <div class="gpu-stat-label">GPU</div>
                                </div>
                                <div class="gpu-stat-item">
                                    <div class="gpu-stat-value">${gpu.mem_util}%</div>
                                    <div class="gpu-stat-label">VRAM</div>
                                </div>
                                <div class="gpu-stat-item">
                                    <div class="gpu-stat-value">${gpu.power_draw}W</div>
                                    <div class="gpu-stat-label">Power</div>
                                </div>
                            </div>
                        </div>
                    `;
                });
                html += '</div>';
            }
            
            container.innerHTML = html;
        }

        async function fetchServices() {
            try {
                const response = await fetch(API.services);
                const data = await response.json();
                services = data.services;
                updateServices();
                updateStats();
            } catch (error) {
                console.error('Failed to fetch services:', error);
                document.getElementById('servicesGrid').innerHTML = 
                    '<div class="error">Failed to load services. Please check the backend connection.</div>';
            }
        }

        function updateServices() {
            const container = document.getElementById('servicesGrid');
            
            if (!services || services.length === 0) {
                container.innerHTML = '<div class="error">No services found</div>';
                return;
            }
            
            let html = '';
            services.forEach(service => {
                const statusClass = `status-${service.status}`;
                const url = service.port ? `http://${window.location.hostname}:${service.port}` : '#';
                const category = getCategoryIcon(service.category) + ' ' + service.category;
                
                html += `
                    <div class="service-card">
                        <div class="service-header">
                            <h3 class="service-name">${formatServiceName(service.name)}</h3>
                            <span class="status-badge ${statusClass}">${service.status}</span>
                        </div>
                        <div class="service-info">
                            <div class="service-detail">
                                <span class="service-detail-label">Category:</span>
                                <span>${category}</span>
                            </div>
                            <div class="service-detail">
                                <span class="service-detail-label">Image:</span>
                                <span style="font-size: 0.8rem;">${service.image.split(':')[0]}</span>
                            </div>
                `;
                
                if (service.port) {
                    html += `
                            <div class="service-detail">
                                <span class="service-detail-label">Address:</span>
                                <span>${window.location.hostname}:${service.port}</span>
                            </div>
                    `;
                }
                
                html += '</div>';
                
                if (service.stats && service.status === 'running') {
                    html += `
                        <div class="service-stats">
                            <div class="stat">
                                <div class="stat-label">CPU</div>
                                <div class="stat-value">${service.stats.cpu.toFixed(1)}%</div>
                            </div>
                            <div class="stat">
                                <div class="stat-label">Memory</div>
                                <div class="stat-value">${service.stats.memory.toFixed(1)}%</div>
                            </div>
                        </div>
                    `;
                }
                
                html += '<div class="service-actions">';
                
                if (service.status === 'running') {
                    if (service.port) {
                        // Special handling for API-only services
                        if (service.name.toLowerCase() === 'chromadb') {
                            html += `<a href="/chromadb-info" target="_blank" class="btn btn-primary">API Info</a>`;
                        } else if (service.name.toLowerCase() === 'ollama') {
                            html += `<a href="/ollama-info" target="_blank" class="btn btn-primary">API Info</a>`;
                        } else {
                            html += `<a href="${url}" target="_blank" class="btn btn-primary">Open UI</a>`;
                        }
                    }
                    html += `
                        <button class="btn btn-secondary" onclick="controlService('${service.name}', 'restart')">Restart</button>
                        <button class="btn btn-danger" onclick="controlService('${service.name}', 'stop')">Stop</button>
                    `;
                } else if (service.status === 'stopped' || service.status === 'exited') {
                    html += `
                        <button class="btn btn-start" onclick="controlService('${service.name}', 'start')">Start Service</button>
                    `;
                } else if (service.status === 'restarting') {
                    html += `
                        <button class="btn btn-secondary" disabled>Restarting...</button>
                    `;
                }
                
                html += `
                        </div>
                    </div>
                `;
            });
            
            container.innerHTML = html;
        }

        function formatServiceName(name) {
            const nameMap = {
                'localai': 'LocalAI',
                'ollama': 'Ollama',
                'forge': 'SD Forge',
                'comfyui': 'ComfyUI',
                'n8n': 'n8n Automation',
                'chromadb': 'ChromaDB',
                'whisper': 'Whisper'
            };
            return nameMap[name.toLowerCase()] || name;
        }

        function updateStats() {
            const total = services.length;
            const running = services.filter(s => s.status === 'running').length;
            
            document.getElementById('totalServices').textContent = total;
            document.getElementById('runningServices').textContent = running;
        }

        function getCategoryIcon(category) {
            const icons = {
                'LLM Services': '🤖',
                'Image Generation': '🎨',
                'Automation': '⚡',
                'Database': '💾',
                'Audio': '🎵',
                'Monitoring': '📊',
                'Other': '📦'
            };
            return icons[category] || '📦';
        }

        async function controlService(serviceName, action) {
            try {
                const response = await fetch(API.control(serviceName, action), {
                    method: 'POST'
                });
                
                if (response.ok) {
                    setTimeout(fetchServices, 1000);
                } else {
                    const error = await response.json();
                    alert(`Failed to ${action} ${serviceName}: ${error.error}`);
                }
            } catch (error) {
                console.error(`Failed to ${action} ${serviceName}:`, error);
                alert(`Failed to ${action} ${serviceName}`);
            }
        }

        async function fetchGPUMetrics() {
            try {
                const response = await fetch(API.gpu);
                const data = await response.json();
                gpuMetrics = data.gpus;
                updateGPUSection();
            } catch (error) {
                console.error('Failed to fetch GPU metrics:', error);
            }
        }

        async function initialize() {
            await fetchSystemInfo();
            await fetchServices();
            await fetchGPUMetrics();
            
            setInterval(async () => {
                await fetchSystemInfo();
                await fetchServices();
                await fetchGPUMetrics();
            }, 5000);
        }

        initialize();
    </script>
</body>
</html>"""

# Cache for performance
cache = {
    'services': {'data': [], 'timestamp': 0},
    'gpu': {'data': [], 'timestamp': 0}
}
CACHE_TTL = 2  # seconds
GPU_CACHE_TTL = 5  # seconds - refresh GPU metrics every 5 seconds

def run_cmd(cmd, timeout=5):
    """Run shell command and return output - SECURE VERSION"""
    try:
        # Convert string commands to list for security
        if isinstance(cmd, str):
            # Parse common Docker commands safely
            if cmd.startswith('docker ps'):
                cmd_parts = cmd.split()
            elif cmd.startswith('docker stats'):
                cmd_parts = cmd.split()
            elif cmd.startswith('top '):
                cmd_parts = ['sh', '-c', cmd]  # Only allow specific shell commands
            elif cmd.startswith('free '):
                cmd_parts = ['sh', '-c', cmd]
            elif cmd.startswith('hostname'):
                cmd_parts = ['hostname']
            else:
                # Log and reject unknown commands
                print(f"Rejected unsafe command: {cmd}")
                return ""
        else:
            cmd_parts = cmd
            
        result = subprocess.run(cmd_parts, capture_output=True, text=True, timeout=timeout)
        output = result.stdout.strip()
        # Clean up any Docker tty artifacts
        output = output.replace(' < /dev/null', '')
        return output
    except Exception as e:
        print(f"Error running command '{cmd}': {e}")
        return ""

def get_docker_services():
    """Get all Docker services on ai-network"""
    now = time.time()
    
    # Check cache
    if cache['services']['data'] and (now - cache['services']['timestamp']) < CACHE_TTL:
        return cache['services']['data']
    
    services = []
    
    # Get all containers with detailed info
    cmd = "docker ps -a --format '{{.ID}}|{{.Names}}|{{.Status}}|{{.Image}}|{{.Ports}}|{{.Networks}}'"
    output = run_cmd(cmd)
    
    # Services to exclude from dashboard
    exclude_services = ['dashboard', 'dcgm-exporter', 'dashboard-backend', 'dcgm', 'gpu-server']
    
    # Get all running container IDs first for bulk stats
    running_containers = []
    container_map = {}
    
    for line in output.split('\n'):
        if not line or not '|' in line:
            continue
            
        parts = line.split('|')
        if len(parts) >= 6:
            container_id = parts[0]
            name = parts[1]
            status_raw = parts[2]
            image = parts[3]
            ports_raw = parts[4]
            networks = parts[5]
            
            # Skip excluded services
            if name.lower() in exclude_services:
                continue
            
            # Only include containers on ai-network
            if 'ai-network' not in networks:
                continue
            
            # Parse status
            status = 'unknown'
            if 'Up' in status_raw:
                status = 'running'
                running_containers.append(container_id)
            elif 'Exited' in status_raw:
                status = 'stopped'
            elif 'Restarting' in status_raw:
                status = 'restarting'
            elif 'Created' in status_raw:
                status = 'created'
            
            # Parse port from the ports string
            port = None
            if ports_raw and '->' in ports_raw:
                # Extract host port from format like "0.0.0.0:8080->8080/tcp"
                try:
                    port_parts = ports_raw.split(',')[0].split('->')
                    if len(port_parts) >= 2:
                        host_part = port_parts[0].strip()
                        if ':' in host_part:
                            port = int(host_part.split(':')[-1])
                except (ValueError, IndexError) as e:
                    print(f"Error parsing port from {ports_raw}: {e}")
                    pass
            
            # Get default port if not found
            if not port:
                port = get_default_port(name)
            
            # Categorize service
            category = categorize_service(name)
            
            container_map[container_id] = {
                'id': container_id,
                'name': name,
                'status': status,
                'image': image,
                'category': category,
                'port': port,
                'stats': None
            }
    
    # Get stats for all running containers in one command
    if running_containers:
        try:
            # Get all stats at once
            stats_cmd = f"docker stats {' '.join(running_containers)} --no-stream --format '{{{{.Container}}}}|{{{{.CPUPerc}}}}|{{{{.MemPerc}}}}'"
            stats_output = run_cmd(stats_cmd, timeout=15)
            
            for line in stats_output.split('\n'):
                if '|' in line:
                    parts = line.split('|')
                    if len(parts) >= 3:
                        container_id = parts[0][:12]  # Docker truncates to 12 chars
                        cpu_str = parts[1].replace('%', '')
                        mem_str = parts[2].replace('%', '')
                        
                        # Find matching container
                        for cid, container in container_map.items():
                            if cid.startswith(container_id):
                                try:
                                    container['stats'] = {
                                        'cpu': float(cpu_str) if cpu_str else 0,
                                        'memory': float(mem_str) if mem_str else 0
                                    }
                                except:
                                    container['stats'] = {'cpu': 0, 'memory': 0}
                                break
        except Exception as e:
            print(f"Error getting bulk stats: {e}")
            # Fallback to individual stats for running containers
            for container_id in running_containers:
                if container_id in container_map:
                    try:
                        cpu_cmd = f"docker stats {container_id} --no-stream --format '{{{{.CPUPerc}}}}' | sed 's/%//'"
                        mem_cmd = f"docker stats {container_id} --no-stream --format '{{{{.MemPerc}}}}' | sed 's/%//'"
                        cpu = run_cmd(cpu_cmd, timeout=5)
                        mem = run_cmd(mem_cmd, timeout=5)
                        
                        container_map[container_id]['stats'] = {
                            'cpu': float(cpu) if cpu else 0,
                            'memory': float(mem) if mem else 0
                        }
                    except:
                        container_map[container_id]['stats'] = {'cpu': 0, 'memory': 0}
    
    # Convert to list
    services = list(container_map.values())
    
    # Cache the result
    cache['services']['data'] = services
    cache['services']['timestamp'] = now
    
    return services

def categorize_service(name):
    """Categorize service by name"""
    name_lower = name.lower()
    
    if name_lower in ['localai', 'ollama']:
        return 'LLM Services'
    elif name_lower in ['forge', 'comfyui', 'stable-diffusion']:
        return 'Image Generation'
    elif name_lower == 'n8n':
        return 'Automation'
    elif name_lower == 'chromadb':
        return 'Database'
    elif name_lower == 'whisper':
        return 'Audio'
    else:
        return 'Other'

def get_default_port(service):
    """Get default port for service"""
    ports = {
        'localai': 8080,
        'ollama': 11434,
        'forge': 7860,
        'comfyui': 8188,
        'n8n': 5678,
        'chromadb': 8000,
        'whisper': 9000
    }
    return ports.get(service.lower())

@app.route('/')
def index():
    """Serve the dashboard HTML"""
    return DASHBOARD_HTML

@app.route('/chromadb-info')
def chromadb_info():
    """Serve the ChromaDB info page"""
    try:
        with open('/app/chromadb-info.html', 'r') as f:
            return f.read()
    except:
        return "ChromaDB Info page not found", 404

@app.route('/ollama-info')
def ollama_info():
    """Serve the Ollama info page"""
    try:
        with open('/app/ollama-info.html', 'r') as f:
            return f.read()
    except:
        return "Ollama Info page not found", 404

@app.route('/api/check-service/<service_name>')
def check_service_status(service_name):
    """Check if a specific service is accessible"""
    try:
        if service_name.lower() == 'chromadb':
            # Check ChromaDB by looking for the chroma-trace-id header
            import urllib.request
            import urllib.error
            try:
                req = urllib.request.Request('http://chromadb:8000/', method='HEAD')
                with urllib.request.urlopen(req, timeout=5) as response:
                    if 'chroma-trace-id' in response.headers:
                        return jsonify({'status': 'online'})
                    else:
                        return jsonify({'status': 'offline'})
            except urllib.error.HTTPError as e:
                # ChromaDB returns 404 but with chroma-trace-id header when running
                if e.status == 404 and 'chroma-trace-id' in e.headers:
                    return jsonify({'status': 'online'})
                else:
                    return jsonify({'status': 'offline'})
        elif service_name.lower() == 'ollama':
            # Check Ollama by calling the tags endpoint
            import urllib.request
            with urllib.request.urlopen('http://ollama:11434/api/tags', timeout=5) as response:
                if response.status == 200:
                    return jsonify({'status': 'online'})
                else:
                    return jsonify({'status': 'offline'})
        else:
            return jsonify({'status': 'unknown'})
    except Exception as e:
        print(f"Error checking {service_name} status: {e}")
        return jsonify({'status': 'offline'})

@app.route('/api/dashboard')
def api_dashboard():
    """Get all dashboard data in one call - OPTIMIZED"""
    services = get_docker_services()
    system_info = api_system().get_json()
    gpu_metrics = api_gpu_metrics().get_json()
    
    return jsonify({
        'services': {
            'data': services,
            'count': len(services)
        },
        'system': system_info,
        'gpu': gpu_metrics,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/services')
def api_services():
    """Get all services - LEGACY ENDPOINT"""
    services = get_docker_services()
    return jsonify({
        'services': services,
        'count': len(services),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/system')
def api_system():
    """Get system information"""
    gpus = []
    driver = "Unknown"
    cuda_version = "Unknown"
    
    # Try to get GPU info from environment variable first
    gpu_info_env = os.environ.get('GPU_INFO')
    if gpu_info_env:
        try:
            import json
            gpu_data = json.loads(gpu_info_env)
            if 'error' not in gpu_data:
                driver = gpu_data.get('driver', 'Unknown')
                cuda_version = gpu_data.get('cuda', 'Unknown')
                names = gpu_data.get('names', '').split(',')
                
                for name in names:
                    if name.strip():
                        gpus.append({'name': name.strip(), 'driver': driver})
        except:
            pass
    
    # If environment variable didn't work, try other methods
    if not gpus:
        try:
            # Try host script
            gpu_info_raw = run_cmd("/host-scripts/gpu-info.sh system")
            import json
            gpu_data = json.loads(gpu_info_raw)
            if 'error' not in gpu_data:
                driver = gpu_data.get('driver', 'Unknown')
                cuda_version = gpu_data.get('cuda', 'Unknown')
                names = gpu_data.get('names', '').split(',')
                
                for name in names:
                    if name.strip():
                        gpus.append({'name': name.strip(), 'driver': driver})
        except:
            # Fallback to direct commands if script fails
            gpu_info = run_cmd("nvidia-smi --query-gpu=driver_version,name --format=csv,noheader")
            for line in gpu_info.split('\n'):
                if ',' in line:
                    parts = line.split(',')
                    if len(parts) >= 2:
                        driver = parts[0].strip()
                        gpus.append({'name': parts[1].strip(), 'driver': driver})
            
            # Get CUDA version
            cuda_info = run_cmd("nvidia-smi | grep 'CUDA Version'")
            if 'CUDA Version:' in cuda_info:
                try:
                    cuda_version = cuda_info.split('CUDA Version:')[1].split()[0]
                except:
                    pass
    
    # Get hostname
    hostname = run_cmd("hostname") or "localhost"
    
    # CPU usage - using top for simplicity
    cpu_cmd = "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1"
    cpu_usage = run_cmd(cpu_cmd)
    try:
        cpu_percent = float(cpu_usage)
    except:
        cpu_percent = 0
    
    # Memory info
    mem_cmd = "free -m | grep Mem | awk '{print $3,$2}'"
    mem_info = run_cmd(mem_cmd).split()
    
    try:
        mem_used = int(mem_info[0]) if len(mem_info) > 0 else 0
        mem_total = int(mem_info[1]) if len(mem_info) > 1 else 1
        mem_percent = round((mem_used / mem_total) * 100, 1)
    except:
        mem_percent = 0
    
    return jsonify({
        'hostname': hostname,
        'nvidia': {
            'gpus': gpus,
            'cuda_driver': cuda_version
        },
        'cpu': {
            'usage': cpu_percent
        },
        'memory': {
            'percent': mem_percent
        }
    })

@app.route('/api/gpu/metrics')
def api_gpu_metrics():
    """Get GPU metrics"""
    now = time.time()
    
    # Check cache with faster TTL for GPU metrics
    if cache['gpu']['data'] and (now - cache['gpu']['timestamp']) < GPU_CACHE_TTL:
        return jsonify({'gpus': cache['gpu']['data']})
    
    gpus = []
    
    # Call local GPU server for metrics
    try:
        import urllib.request
        import json
        
        # Use gpu-server container name since we're on ai-network
        with urllib.request.urlopen('http://gpu-server:9999/gpu-metrics', timeout=5) as response:
            gpu_data = json.loads(response.read().decode())
            gpus = gpu_data.get('gpus', [])
    except Exception as e:
        print(f"Error getting GPU metrics from server: {e}")
        # Fallback: try direct host script call
        try:
            gpu_json = run_cmd("/host-scripts/gpu-simple.sh")
            import json
            gpus_data = json.loads(gpu_json)
            
            for gpu in gpus_data:
                try:
                    mem_used = float(gpu['mem_used'])
                    mem_total = float(gpu['mem_total'])
                    mem_util = round((mem_used / mem_total) * 100, 1) if mem_total > 0 else 0
                    
                    gpus.append({
                        'index': int(gpu['index']),
                        'name': gpu['name'].strip(),
                        'temperature': float(gpu['temperature']),
                        'gpu_util': float(gpu['gpu_util']),
                        'mem_used': mem_used,
                        'mem_total': mem_total,
                        'mem_util': mem_util,
                        'power_draw': float(gpu['power_draw'])
                    })
                except Exception as e:
                    print(f"Error parsing GPU data: {e}")
                    continue
        except Exception as e:
            print(f"Error with fallback GPU script: {e}")
            pass
    
    # Cache the result
    cache['gpu']['data'] = gpus
    cache['gpu']['timestamp'] = now
    
    return jsonify({'gpus': gpus})

@app.route('/api/services/<name>/<action>', methods=['POST'])
def api_control_service(name, action):
    """Control a service"""
    if action in ['start', 'stop', 'restart']:
        result = run_cmd(f"docker {action} {name}")
        
        # Clear cache
        cache['services']['data'] = []
        
        return jsonify({
            'status': 'success',
            'message': f'{name} {action} command sent',
            'output': result
        })
    
    return jsonify({'error': 'Invalid action'}), 400

@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint (placeholder)"""
    # Simple placeholder for GPU metrics in Prometheus format
    output = "# HELP gpu_utilization GPU utilization percentage\n"
    output += "# TYPE gpu_utilization gauge\n"
    
    gpu_data = cache['gpu']['data']
    if gpu_data:
        for gpu in gpu_data:
            output += f"gpu_utilization{{gpu=\"{gpu['index']}\",name=\"{gpu['name']}\"}} {gpu['gpu_util']}\n"
    
    return Response(output, mimetype='text/plain')

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

if __name__ == '__main__':
    print("AI Box Dashboard starting on port 8085...")
    # Run on port 8085 to test external access
    app.run(host='0.0.0.0', port=8085, debug=False)