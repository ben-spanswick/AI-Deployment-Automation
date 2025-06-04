#!/usr/bin/env python3
"""
gpu-server.py - Simple HTTP server to provide GPU metrics to dashboard
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import subprocess
import json
import threading
import time

class GPUHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/gpu-metrics':
            try:
                # Get GPU metrics
                result = subprocess.run([
                    'nvidia-smi', '--query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw',
                    '--format=csv,noheader,nounits'
                ], capture_output=True, text=True, timeout=5)
                
                gpus = []
                for line in result.stdout.strip().split('\n'):
                    if ',' in line:
                        parts = [p.strip() for p in line.split(',')]
                        if len(parts) >= 7:
                            try:
                                mem_used = float(parts[4])
                                mem_total = float(parts[5])
                                mem_util = round((mem_used / mem_total) * 100, 1) if mem_total > 0 else 0
                                
                                gpus.append({
                                    'index': int(parts[0]),
                                    'name': parts[1],
                                    'temperature': float(parts[2]),
                                    'gpu_util': float(parts[3]),
                                    'mem_used': mem_used,
                                    'mem_total': mem_total,
                                    'mem_util': mem_util,
                                    'power_draw': float(parts[6])
                                })
                            except:
                                continue
                
                response = json.dumps({'gpus': gpus})
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(response.encode())
                
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                error_response = json.dumps({'error': str(e)})
                self.wfile.write(error_response.encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress logging
        pass

def run_server():
    server = HTTPServer(('0.0.0.0', 9999), GPUHandler)
    print("GPU metrics server running on http://0.0.0.0:9999/gpu-metrics")
    server.serve_forever()

if __name__ == '__main__':
    run_server()