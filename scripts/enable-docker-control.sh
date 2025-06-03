#!/bin/bash
# Enable Docker control from dashboard
# This creates a simple API endpoint using socat

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Setting up Docker Control for Dashboard${NC}"
echo

# Method 1: Using systemd socket activation (most secure)
echo "Choose setup method:"
echo "1) Systemd socket (recommended - survives reboots)"
echo "2) Simple socat server (manual start)"
echo "3) Skip setup"

read -p "Choice [1-3]: " choice

case $choice in
    1)
        echo -e "${GREEN}Setting up systemd socket...${NC}"
        
        # Create socket unit
        sudo tee /etc/systemd/system/docker-control.socket > /dev/null << 'EOF'
[Unit]
Description=Docker Control Socket

[Socket]
ListenStream=127.0.0.1:8090
Accept=yes

[Install]
WantedBy=sockets.target
EOF

        # Create service unit
        sudo tee /etc/systemd/system/docker-control@.service > /dev/null << 'EOF'
[Unit]
Description=Docker Control Service

[Service]
ExecStart=/bin/bash -c 'read line; cmd=$(echo "$line" | grep -oP "GET /docker/\K[^/ ]+"); svc=$(echo "$line" | grep -oP "GET /docker/[^/]+/\K[^/ ]+"); if [[ "$cmd" == "start" || "$cmd" == "stop" ]] && [[ "$svc" =~ ^(localai|ollama|forge|comfyui|dcgm)$ ]]; then docker $cmd $svc 2>&1 && echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nOK" || echo -e "HTTP/1.1 500 Error\r\n\r\nFailed"; else echo -e "HTTP/1.1 400 Bad Request\r\n\r\n"; fi'
StandardInput=socket
StandardOutput=socket
Type=simple
EOF

        # Enable and start
        sudo systemctl daemon-reload
        sudo systemctl enable docker-control.socket
        sudo systemctl start docker-control.socket
        
        echo -e "${GREEN}✓ Systemd socket activated on port 8090${NC}"
        ;;
        
    2)
        echo -e "${YELLOW}Starting simple socat server...${NC}"
        echo "Run this command to start the control server:"
        echo
        echo 'while true; do'
        echo '  echo -e "HTTP/1.1 200 OK\r\n\r\n$(docker ps --format "{{.Names}}")" | socat -t 1 TCP-LISTEN:8090,reuseaddr,fork -'
        echo 'done'
        echo
        echo "Note: This needs to be running for dashboard control to work"
        ;;
        
    3)
        echo "Skipping setup. Dashboard will use copy-to-clipboard mode."
        ;;
esac

# Update nginx config to proxy to our service
echo
echo -e "${GREEN}Updating nginx configuration...${NC}"

cat > /tmp/nginx-docker-proxy.conf << 'EOF'
    location /docker/ {
        proxy_pass http://host.docker.internal:8090/docker/;
        proxy_set_header Host $host;
        proxy_read_timeout 5s;
        proxy_connect_timeout 5s;
    }
EOF

echo
echo "Add this to your nginx.conf server block:"
cat /tmp/nginx-docker-proxy.conf
echo
echo -e "${GREEN}Done! Restart the dashboard container to apply changes.${NC}"