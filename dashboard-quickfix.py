#!/usr/bin/env python3
"""Quick fix for dashboard - test service detection"""

import subprocess
import json

def run_cmd(cmd):
    try:
        # Remove the < /dev/null part if present
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        output = result.stdout.strip()
        # Clean up any shell artifacts
        output = output.replace(' < /dev/null', '')
        return output
    except Exception as e:
        print(f"Error running command: {e}")
        return ""

# Test service detection
print("Testing docker command...")
cmd = "docker ps -a --format '{{.Names}}|{{.Status}}|{{.Image}}|{{.Networks}}'"
output = run_cmd(cmd)

print(f"Raw output:\n{output[:500]}\n")

services = []
for line in output.split('\n'):
    if not line or not '|' in line:
        continue
    
    # Clean the line
    line = line.replace(' < /dev/null', '').strip()
    parts = line.split('|')
    
    if len(parts) >= 4:
        name = parts[0].strip()
        status_raw = parts[1].strip()
        image = parts[2].strip()
        networks = parts[3].strip()
        
        if 'ai-network' in networks:
            status = 'unknown'
            if 'Up' in status_raw:
                status = 'running'
            elif 'Exited' in status_raw:
                status = 'stopped'
            elif 'Restarting' in status_raw:
                status = 'restarting'
            
            services.append({
                'name': name,
                'status': status,
                'image': image
            })

print(f"\nDetected {len(services)} services:")
for s in services:
    print(f"  - {s['name']} ({s['status']})")

# Test inside docker
print("\n\nTesting inside docker container...")
docker_test = """
import subprocess
output = subprocess.run("docker ps --format '{{.Names}}'", shell=True, capture_output=True, text=True)
print('Docker test:', output.stdout[:100] if output.stdout else 'No output')
print('Error:', output.stderr[:100] if output.stderr else 'No error')
"""

result = run_cmd(f'docker exec dashboard python -c "{docker_test}"')
print(result)