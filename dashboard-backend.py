#!/usr/bin/env python3
"""
Simple backend service for AI Box Dashboard
Handles Docker container control commands
"""

from flask import Flask, jsonify, request
from flask_cors import CORS
import subprocess
import json
import os

app = Flask(__name__)
CORS(app)  # Enable CORS for dashboard

# Allowed services (security measure)
ALLOWED_SERVICES = ['localai', 'ollama', 'forge', 'comfyui', 'dcgm', 'whisper', 'chromadb', 'n8n']

@app.route('/api/services/<service>/status', methods=['GET'])
def get_service_status(service):
    """Get the status of a specific service"""
    if service not in ALLOWED_SERVICES:
        return jsonify({'error': 'Invalid service'}), 400
    
    try:
        # Check if container exists and is running
        result = subprocess.run(
            ['docker', 'inspect', '-f', '{{.State.Running}}', service],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            running = result.stdout.strip() == 'true'
            return jsonify({'service': service, 'running': running})
        else:
            return jsonify({'service': service, 'running': False, 'exists': False})
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/services/<service>/start', methods=['POST'])
def start_service(service):
    """Start a specific service"""
    if service not in ALLOWED_SERVICES:
        return jsonify({'error': 'Invalid service'}), 400
    
    try:
        result = subprocess.run(
            ['docker', 'start', service],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            return jsonify({'service': service, 'status': 'started'})
        else:
            return jsonify({'error': result.stderr}), 500
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/services/<service>/stop', methods=['POST'])
def stop_service(service):
    """Stop a specific service"""
    if service not in ALLOWED_SERVICES:
        return jsonify({'error': 'Invalid service'}), 400
    
    try:
        result = subprocess.run(
            ['docker', 'stop', service],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            return jsonify({'service': service, 'status': 'stopped'})
        else:
            return jsonify({'error': result.stderr}), 500
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/services', methods=['GET'])
def get_all_services():
    """Get status of all services"""
    statuses = {}
    
    for service in ALLOWED_SERVICES:
        try:
            result = subprocess.run(
                ['docker', 'inspect', '-f', '{{.State.Running}}', service],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                statuses[service] = result.stdout.strip() == 'true'
            else:
                statuses[service] = False
        except:
            statuses[service] = False
    
    return jsonify(statuses)

@app.route('/api/deployed-services', methods=['GET'])
def get_deployed_services():
    """Get list of deployed services from file"""
    services_file = '/home/mandrake/AI-Deployment/.deployed-services.json'
    
    if os.path.exists(services_file):
        with open(services_file, 'r') as f:
            data = json.load(f)
            return jsonify(data)
    else:
        # Return default services
        return jsonify({'services': ['localai', 'ollama', 'forge', 'comfyui', 'dcgm', 'dashboard']})

if __name__ == '__main__':
    # Run on port 5000
    app.run(host='0.0.0.0', port=5000, debug=False)