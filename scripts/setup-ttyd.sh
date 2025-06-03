#!/bin/bash
# Setup ttyd (web terminal) for Docker control

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Setting up Web Terminal for Docker Control${NC}"
echo

# Install ttyd
if ! command -v ttyd &> /dev/null; then
    echo "Installing ttyd..."
    wget -qO /tmp/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.4/ttyd.x86_64
    sudo mv /tmp/ttyd /usr/local/bin/ttyd
    sudo chmod +x /usr/local/bin/ttyd
fi

# Create a restricted shell script for Docker commands only
cat > /tmp/docker-shell.sh << 'EOF'
#!/bin/bash
echo "Docker Control Shell - Commands: docker start/stop/ps/logs"
echo "Type 'exit' to close"
echo

# Restricted shell - only allow specific docker commands
while true; do
    read -p "docker> " cmd args
    case "$cmd" in
        start|stop|restart|ps|logs)
            docker $cmd $args
            ;;
        exit|quit)
            break
            ;;
        *)
            echo "Allowed commands: start, stop, restart, ps, logs"
            ;;
    esac
done
EOF

chmod +x /tmp/docker-shell.sh

echo -e "${YELLOW}To run the web terminal:${NC}"
echo "ttyd -p 7681 -t fontSize=16 /tmp/docker-shell.sh"
echo
echo "Then access it at: http://localhost:7681"
echo
echo "Or embed in dashboard with iframe:"
echo '<iframe src="http://localhost:7681" width="100%" height="400"></iframe>'