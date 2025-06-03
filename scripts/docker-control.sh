#!/bin/bash
# Docker control script for nginx CGI
# Place in /opt/ai-box/nginx/cgi-bin/

# Parse query string
if [[ "$QUERY_STRING" =~ action=([^&]+)&service=([^&]+) ]]; then
    ACTION="${BASH_REMATCH[1]}"
    SERVICE="${BASH_REMATCH[2]}"
else
    echo "Status: 400 Bad Request"
    echo "Content-Type: application/json"
    echo ""
    echo '{"error": "Missing parameters"}'
    exit 1
fi

# Whitelist services
ALLOWED_SERVICES="localai ollama forge comfyui dcgm"
if [[ ! " $ALLOWED_SERVICES " =~ " $SERVICE " ]]; then
    echo "Status: 403 Forbidden"
    echo "Content-Type: application/json"
    echo ""
    echo '{"error": "Service not allowed"}'
    exit 1
fi

# Execute docker command
echo "Content-Type: application/json"
echo ""

case "$ACTION" in
    start)
        if docker start "$SERVICE" 2>/dev/null; then
            echo '{"status": "success", "action": "start", "service": "'$SERVICE'"}'
        else
            echo '{"status": "error", "message": "Failed to start service"}'
        fi
        ;;
    stop)
        if docker stop "$SERVICE" 2>/dev/null; then
            echo '{"status": "success", "action": "stop", "service": "'$SERVICE'"}'
        else
            echo '{"status": "error", "message": "Failed to stop service"}'
        fi
        ;;
    status)
        if docker ps --format "{{.Names}}" | grep -q "^${SERVICE}$"; then
            echo '{"status": "running", "service": "'$SERVICE'"}'
        else
            echo '{"status": "stopped", "service": "'$SERVICE'"}'
        fi
        ;;
    *)
        echo '{"error": "Invalid action"}'
        ;;
esac