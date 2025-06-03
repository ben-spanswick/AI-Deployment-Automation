#!/bin/bash
# AI Box Dashboard Management Script
# Consolidated script for dashboard operations

set -euo pipefail

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
DASHBOARD_FILE="/opt/ai-box/dashboard/dashboard.html"
BACKEND_SERVICE="dashboard-backend"
DOCKER_COMPOSE_FILE="docker-compose-dashboard.yml"

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root or with sudo
check_permissions() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    install     Install dashboard and backend service
    update      Update dashboard to latest version
    restart     Restart dashboard backend service
    status      Check dashboard service status
    logs        View dashboard backend logs
    fix         Fix common dashboard issues
    uninstall   Remove dashboard and backend service

Options:
    -h, --help  Display this help message

Examples:
    $0 install
    $0 status
    $0 logs
    
EOF
}

# Install dashboard
install_dashboard() {
    log_info "Installing AI Box Dashboard..."
    
    # Create dashboard directory
    mkdir -p /opt/ai-box/dashboard
    
    # Copy dashboard file
    if [[ -f "dashboard.html" ]]; then
        cp dashboard.html "$DASHBOARD_FILE"
        chmod 644 "$DASHBOARD_FILE"
        log_info "Dashboard HTML installed to $DASHBOARD_FILE"
    else
        log_error "dashboard.html not found in current directory"
        exit 1
    fi
    
    # Install backend service
    if [[ -f "dashboard-backend.py" ]]; then
        cp dashboard-backend.py /opt/ai-box/dashboard/
        chmod +x /opt/ai-box/dashboard/dashboard-backend.py
        log_info "Dashboard backend installed"
    else
        log_error "dashboard-backend.py not found"
        exit 1
    fi
    
    # Deploy with docker-compose
    if [[ -f "$DOCKER_COMPOSE_FILE" ]]; then
        docker-compose -f "$DOCKER_COMPOSE_FILE" up -d
        log_info "Dashboard backend service started"
    else
        log_error "Docker compose file not found: $DOCKER_COMPOSE_FILE"
        exit 1
    fi
    
    log_info "Dashboard installation complete!"
    log_info "Access the dashboard at: http://localhost:8090"
}

# Update dashboard
update_dashboard() {
    log_info "Updating AI Box Dashboard..."
    
    # Backup current dashboard
    if [[ -f "$DASHBOARD_FILE" ]]; then
        cp "$DASHBOARD_FILE" "${DASHBOARD_FILE}.backup"
        log_info "Current dashboard backed up"
    fi
    
    # Copy new dashboard
    if [[ -f "dashboard.html" ]]; then
        cp dashboard.html "$DASHBOARD_FILE"
        chmod 644 "$DASHBOARD_FILE"
        log_info "Dashboard updated successfully"
    else
        log_error "dashboard.html not found in current directory"
        exit 1
    fi
    
    # Restart backend if running
    if docker ps | grep -q "$BACKEND_SERVICE"; then
        docker restart "$BACKEND_SERVICE"
        log_info "Dashboard backend restarted"
    fi
}

# Restart dashboard service
restart_dashboard() {
    log_info "Restarting dashboard backend service..."
    
    if docker ps | grep -q "$BACKEND_SERVICE"; then
        docker restart "$BACKEND_SERVICE"
        log_info "Dashboard backend restarted successfully"
    else
        log_warn "Dashboard backend is not running. Starting it..."
        docker-compose -f "$DOCKER_COMPOSE_FILE" up -d
    fi
}

# Check dashboard status
check_status() {
    log_info "Checking dashboard status..."
    
    # Check if backend is running
    if docker ps | grep -q "$BACKEND_SERVICE"; then
        log_info "Dashboard backend: ${GREEN}Running${NC}"
        
        # Get container details
        docker ps --filter "name=$BACKEND_SERVICE" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        log_warn "Dashboard backend: ${RED}Not running${NC}"
    fi
    
    # Check if dashboard file exists
    if [[ -f "$DASHBOARD_FILE" ]]; then
        log_info "Dashboard HTML: ${GREEN}Installed${NC}"
        log_info "Location: $DASHBOARD_FILE"
        log_info "Last modified: $(stat -c %y "$DASHBOARD_FILE" | cut -d' ' -f1,2)"
    else
        log_warn "Dashboard HTML: ${RED}Not installed${NC}"
    fi
    
    # Check if accessible
    if command -v curl &> /dev/null; then
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:8090 | grep -q "200"; then
            log_info "Dashboard endpoint: ${GREEN}Accessible${NC}"
        else
            log_warn "Dashboard endpoint: ${RED}Not accessible${NC}"
        fi
    fi
}

# View logs
view_logs() {
    log_info "Viewing dashboard backend logs..."
    
    if docker ps | grep -q "$BACKEND_SERVICE"; then
        docker logs -f "$BACKEND_SERVICE"
    else
        log_error "Dashboard backend is not running"
        exit 1
    fi
}

# Fix common issues
fix_dashboard() {
    log_info "Fixing common dashboard issues..."
    
    # Fix permissions
    if [[ -f "$DASHBOARD_FILE" ]]; then
        chmod 644 "$DASHBOARD_FILE"
        log_info "Fixed dashboard file permissions"
    fi
    
    # Ensure directories exist
    mkdir -p /opt/ai-box/dashboard
    log_info "Ensured dashboard directory exists"
    
    # Restart backend
    if docker ps | grep -q "$BACKEND_SERVICE"; then
        docker restart "$BACKEND_SERVICE"
        log_info "Restarted dashboard backend"
    else
        log_warn "Dashboard backend not running, starting it..."
        docker-compose -f "$DOCKER_COMPOSE_FILE" up -d
    fi
    
    # Verify nginx is running
    if ! docker ps | grep -q "nginx"; then
        log_warn "Nginx not running, starting it..."
        cd docker && docker-compose up -d nginx
    fi
    
    log_info "Dashboard fixes applied"
}

# Uninstall dashboard
uninstall_dashboard() {
    log_warn "This will remove the dashboard and backend service."
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Uninstall cancelled"
        exit 0
    fi
    
    log_info "Uninstalling dashboard..."
    
    # Stop and remove backend service
    if docker ps | grep -q "$BACKEND_SERVICE"; then
        docker-compose -f "$DOCKER_COMPOSE_FILE" down
        log_info "Dashboard backend stopped and removed"
    fi
    
    # Remove dashboard files
    rm -f "$DASHBOARD_FILE"
    rm -f /opt/ai-box/dashboard/dashboard-backend.py
    log_info "Dashboard files removed"
    
    log_info "Dashboard uninstalled successfully"
}

# Main script logic
main() {
    # Check if no arguments provided
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi
    
    # Parse command
    case "$1" in
        install)
            check_permissions
            install_dashboard
            ;;
        update)
            check_permissions
            update_dashboard
            ;;
        restart)
            check_permissions
            restart_dashboard
            ;;
        status)
            check_status
            ;;
        logs)
            view_logs
            ;;
        fix)
            check_permissions
            fix_dashboard
            ;;
        uninstall)
            check_permissions
            uninstall_dashboard
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"