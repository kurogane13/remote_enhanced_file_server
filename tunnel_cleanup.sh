#!/bin/bash

# Remote Tunnel & Server Cleanup Script
# Enhanced cleanup for the remote file server system
# Version: 2.0

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
SSH_KEY="$HOME/.ssh/aws_rsa"
REMOTE_USER="ubuntu"
REMOTE_HOST="52.89.199.207"
LOCAL_PORT=8081
REMOTE_PORT=8081

# Functions
log_info() {
    echo -e "${BLUE}ℹ${NC} ${WHITE}$1${NC}"
}

log_success() {
    echo -e "${GREEN}✅${NC} ${WHITE}$1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} ${WHITE}$1${NC}"
}

log_error() {
    echo -e "${RED}❌${NC} ${WHITE}$1${NC}"
}

print_banner() {
    echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${WHITE}${BOLD}            🧹 Remote System Cleanup Script 🧹           ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN} ${YELLOW}Enhanced cleanup for SSH tunnels and remote servers${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
    echo
}

cleanup_local_tunnel() {
    log_info "🏠 Cleaning up local SSH tunnels on port $LOCAL_PORT..."
    
    # Kill SSH processes by pattern first
    log_info "Killing SSH tunnel processes by pattern..."
    pkill -f "ssh.*-L.*$LOCAL_PORT:localhost:$REMOTE_PORT" 2>/dev/null
    pkill -f "ssh.*$LOCAL_PORT.*$REMOTE_HOST" 2>/dev/null
    sleep 2
    
    # Find and kill any remaining processes on the port
    local tunnel_pids=$(lsof -t -i:$LOCAL_PORT 2>/dev/null)
    
    if [[ -n "$tunnel_pids" ]]; then
        echo -e "${YELLOW}Found remaining processes on port $LOCAL_PORT:${NC}"
        lsof -i:$LOCAL_PORT 2>/dev/null
        
        echo "$tunnel_pids" | while read pid; do
            if [[ -n "$pid" ]]; then
                local cmd=$(ps -p $pid -o cmd= 2>/dev/null || echo "Unknown process")
                log_info "Terminating process $pid: $cmd"
                kill -9 $pid 2>/dev/null
            fi
        done
        
        # Verify tunnel is closed
        sleep 2
        if ! lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
            log_success "Local SSH tunnel terminated successfully"
        else
            log_warning "Some processes may still be using port $LOCAL_PORT"
            lsof -i:$LOCAL_PORT 2>/dev/null || true
        fi
    else
        log_success "No SSH tunnel found on port $LOCAL_PORT"
    fi
}

cleanup_remote_server() {
    log_info "🌐 Cleaning up remote server processes..."
    
    # Test SSH connection first
    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" "echo 'test'" >/dev/null 2>&1; then
        log_error "Cannot connect to remote host: $REMOTE_USER@$REMOTE_HOST"
        log_info "Remote cleanup skipped - check SSH connectivity"
        return 1
    fi
    
    # Kill remote server processes
    ssh -i "$SSH_KEY" -o ConnectTimeout=10 "$REMOTE_USER@$REMOTE_HOST" '
        echo "🔍 Looking for remote server processes..."
        
        # Kill Python HTTP servers
        pkill -f "python.*enhanced_http_server" 2>/dev/null || true
        pkill -f "start_http_server" 2>/dev/null || true  
        pkill -f "python.*http.server" 2>/dev/null || true
        pkill -f "python.*-m.*http" 2>/dev/null || true
        
        # Kill processes on port 8081
        for pid in $(lsof -t -i:8081 2>/dev/null || true); do
            if [[ -n "$pid" ]]; then
                echo "🛑 Killing process $pid on port 8081"
                kill -TERM $pid 2>/dev/null || true
                sleep 1
                if kill -0 $pid 2>/dev/null; then
                    echo "⚡ Using SIGKILL for process $pid"
                    kill -KILL $pid 2>/dev/null || true
                fi
            fi
        done
        
        # Verify cleanup
        remaining=$(lsof -t -i:8081 2>/dev/null | wc -l)
        if [[ $remaining -gt 0 ]]; then
            echo "⚠️  $remaining processes may still be running on port 8081:"
            lsof -i:8081 2>/dev/null || true
        else
            echo "✅ Port 8081 is now free"
        fi
        
        echo "✅ Remote cleanup completed"
    ' 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_success "Remote server cleanup completed"
    else
        log_error "Remote cleanup failed"
        return 1
    fi
}

show_status() {
    echo
    log_info "📊 Current System Status"
    echo
    
    # Check local port
    echo -e "${BOLD}Local Port Status ($LOCAL_PORT):${NC}"
    if lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        log_warning "Port $LOCAL_PORT is in use:"
        lsof -Pi :$LOCAL_PORT -sTCP:LISTEN 2>/dev/null | head -5
    else
        log_success "Port $LOCAL_PORT is free"
    fi
    echo
    
    # Check SSH processes
    echo -e "${BOLD}SSH Tunnel Processes:${NC}"
    local ssh_procs=$(ps aux | grep -E "ssh.*-L.*$LOCAL_PORT" | grep -v grep || true)
    if [[ -n "$ssh_procs" ]]; then
        echo "$ssh_procs"
    else
        echo "No SSH tunnel processes found"
    fi
    echo
    
    # Check remote port (if accessible)
    echo -e "${BOLD}Remote Port Status ($REMOTE_PORT):${NC}"
    if ssh -i "$SSH_KEY" -o ConnectTimeout=3 "$REMOTE_USER@$REMOTE_HOST" '
        if lsof -i :8081 >/dev/null 2>&1; then
            echo "⚠️  Remote port 8081 is in use"
            lsof -i:8081 2>/dev/null | head -3
        else
            echo "✅ Remote port 8081 is free"
        fi
    ' 2>/dev/null; then
        echo "Remote status check completed"
    else
        echo "Cannot check remote status (connection failed)"
    fi
}

show_manual_commands() {
    echo
    echo -e "${BOLD}🔧 Manual Cleanup Commands:${NC}"
    echo
    echo -e "${CYAN}Local Tunnel Cleanup:${NC}"
    echo -e "  pkill -f 'ssh.*-L.*$LOCAL_PORT:localhost:$REMOTE_PORT'"
    echo -e "  kill \$(lsof -t -i:$LOCAL_PORT)"
    echo -e "  lsof -i :$LOCAL_PORT    # Check what's using the port"
    echo
    echo -e "${CYAN}Remote Server Cleanup:${NC}"
    echo -e "  ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST 'pkill -f enhanced_http_server'"
    echo -e "  ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST 'kill \$(lsof -t -i:$REMOTE_PORT)'"
    echo
    echo -e "${CYAN}Connection Testing:${NC}"
    echo -e "  curl http://localhost:$LOCAL_PORT/"
    echo -e "  ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST 'echo test'"
    echo
}

main() {
    print_banner
    
    # Parse command line arguments
    case "${1:-cleanup}" in
        "status"|"-s"|"--status")
            show_status
            ;;
        "manual"|"-m"|"--manual")
            show_manual_commands
            ;;
        "cleanup"|"clean"|"-c"|"--clean"|"")
            # Step 1: Cleanup local tunnel
            cleanup_local_tunnel
            echo
            
            # Step 2: Cleanup remote server
            cleanup_remote_server
            echo
            
            # Step 3: Show final status
            show_status
            
            echo -e "${GREEN}🎉 Comprehensive cleanup completed!${NC}"
            ;;
        "help"|"-h"|"--help")
            echo -e "${BOLD}Usage:${NC} $0 [OPTION]"
            echo
            echo -e "${BOLD}Options:${NC}"
            echo -e "  cleanup, clean     Complete cleanup (default)"
            echo -e "  status, -s         Show current status"
            echo -e "  manual, -m         Show manual cleanup commands"
            echo -e "  help, -h           Show this help"
            echo
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Handle Ctrl+C gracefully
cleanup_script() {
    echo
    log_info "Cleanup script interrupted"
    exit 0
}

trap cleanup_script SIGINT SIGTERM

# Run main function
main "$@"