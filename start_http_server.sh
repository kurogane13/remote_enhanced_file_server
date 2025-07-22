#!/bin/bash

# Remote Advanced File Browser Launcher
# Starts the enhanced Python HTTP server

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

print_banner() {
    echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${WHITE}${BOLD}        🌐 Remote Advanced File Browser 🌐           ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN} ${YELLOW}Universal file browsing, filtering, and download system${NC}${CYAN}${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
    echo
}

log_info() {
    echo -e "${BLUE}ℹ${NC} ${WHITE}$1${NC}"
}

log_success() {
    echo -e "${GREEN}✅${NC} ${WHITE}$1${NC}"
}

log_error() {
    echo -e "${RED}❌${NC} ${WHITE}$1${NC}"
}

# Default configuration
DEFAULT_PORT=8081
DEFAULT_DIRECTORY="."

# Get current script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_SCRIPT="$SCRIPT_DIR/enhanced_http_server_new.py"

main() {
    print_banner
    
    log_info "Starting Remote Advanced File Browser..."
    
    # Check if Python server exists
    if [[ ! -f "$SERVER_SCRIPT" ]]; then
        log_error "Server script not found: $SERVER_SCRIPT"
        exit 1
    fi
    
    # Check if Python is available
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is required but not installed"
        exit 1
    fi
    
    log_info "Server script: $SERVER_SCRIPT"
    log_info "Default port: $DEFAULT_PORT"
    log_info "Serving directory: $(pwd)"
    echo
    
    log_success "Launching Remote Advanced File Browser..."
    echo
    
    # Start the server
    python3 "$SERVER_SCRIPT" --port "$DEFAULT_PORT" --directory "$DEFAULT_DIRECTORY"
}

# Handle Ctrl+C gracefully
cleanup() {
    echo
    log_info "Shutting down server..."
    exit 0
}

trap cleanup SIGINT SIGTERM

# Run main function
main "$@"