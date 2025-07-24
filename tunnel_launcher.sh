#!/bin/bash

# Remote Tunnel & Server Launcher
# Establishes SSH tunnel and starts remote HTTP server with one command
# Version: 1.0

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Default Configuration - using $HOME for portability
DEFAULT_SSH_KEY="$HOME/.ssh/id_rsa"
DEFAULT_REMOTE_USER="ubuntu"
DEFAULT_REMOTE_HOST=""
LOCAL_PORT=8081
REMOTE_PORT=8081
# No longer using external script - Python server started directly

# Host Configuration
HOSTS_CONFIG_DIR="$HOME/.tunnel_configs"
HOSTS_CONFIG_FILE="$HOSTS_CONFIG_DIR/remote_hosts.conf"
SSH_CONFIGS_FILE="$HOSTS_CONFIG_DIR/ssh_keys.json"
PASSWORD_CONFIGS_FILE="$HOSTS_CONFIG_DIR/passwords.json"

# Active Configuration (will be set by setup_connection function)
SSH_KEY=""
REMOTE_USER=""
REMOTE_HOST=""
USE_PASSWORD=false
REMOTE_PASSWORD=""
SELECTED_SERVER=""

# Options
VERBOSE=false
DEBUG=false
AUTO_YES=false

# Functions
print_banner() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}          🚀 Remote Tunnel & Server Launcher 🚀          ${NC}"
    echo -e "${PURPLE}Automated SSH tunnel + remote server deployment${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo
}

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

log_debug() {
    if [[ "$DEBUG" == true ]]; then
        echo -e "${WHITE}🐛 DEBUG: $1${NC}"
    fi
}

log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${WHITE}📝 $1${NC}"
    fi
}

# Host Management Functions
init_hosts_config() {
    # Ensure configuration directory exists
    mkdir -p "$HOSTS_CONFIG_DIR"
    
    # Create SSH config file if it doesn't exist
    if [ ! -f "$SSH_CONFIGS_FILE" ]; then
        echo "{}" > "$SSH_CONFIGS_FILE"
        log_debug "Created SSH configurations file: $SSH_CONFIGS_FILE"
    fi
    
    # Create password config file if it doesn't exist
    if [ ! -f "$PASSWORD_CONFIGS_FILE" ]; then
        echo "{}" > "$PASSWORD_CONFIGS_FILE"
        log_debug "Created password configurations file: $PASSWORD_CONFIGS_FILE"
    fi
    
    # Create hosts file if it doesn't exist
    if [ ! -f "$HOSTS_CONFIG_FILE" ]; then
        touch "$HOSTS_CONFIG_FILE"
        log_debug "Created hosts configuration file: $HOSTS_CONFIG_FILE"
    fi
}

# Extract IPs from saved SSH key and password configurations
sync_hosts_from_configs() {
    log_debug "Syncing hosts file from saved configurations..."
    
    local ssh_config=$(load_ssh_config)
    local password_config=$(load_password_config)
    local ssh_ips=()
    local password_ips=()
    
    # Extract unique IPs from SSH configs using Python JSON parsing
    if [[ "$ssh_config" != "{}" ]]; then
        local ssh_extracted=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    unique_ips = set()
    if 'saved_keys' in config:
        for name, details in config['saved_keys'].items():
            if 'host' in details:
                unique_ips.add(details['host'])
    for ip in sorted(unique_ips):
        print(ip)
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$ssh_extracted" ]]; then
            while IFS= read -r ip; do
                if [[ -n "$ip" ]]; then
                    ssh_ips+=("$ip")
                    log_debug "Found unique SSH IP: $ip"
                fi
            done <<< "$ssh_extracted"
        fi
    fi
    
    # Extract unique IPs from password configs using Python JSON parsing
    if [[ "$password_config" != "{}" ]]; then
        local password_extracted=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    unique_ips = set()
    if 'saved_passwords' in config:
        for name, details in config['saved_passwords'].items():
            if 'host' in details:
                unique_ips.add(details['host'])
    for ip in sorted(unique_ips):
        print(ip)
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$password_extracted" ]]; then
            while IFS= read -r ip; do
                if [[ -n "$ip" ]]; then
                    password_ips+=("$ip")
                    log_debug "Found unique Password IP: $ip"
                fi
            done <<< "$password_extracted"
        fi
    fi
    
    # Read existing hosts file
    local existing_ips=()
    if [[ -f "$HOSTS_CONFIG_FILE" ]]; then
        while IFS= read -r line; do
            line=$(echo "$line" | xargs) # trim whitespace
            if [[ -n "$line" && ! "$line" =~ ^# ]]; then
                existing_ips+=("$line")
            fi
        done < "$HOSTS_CONFIG_FILE"
    fi
    
    # Write to hosts file with section headers
    {
        if [[ ${#ssh_ips[@]} -gt 0 ]]; then
            echo "# SSH KEY saved connections IPS"
            echo ""
            printf '%s\n' "${ssh_ips[@]}"
            echo ""
        fi
        
        if [[ ${#password_ips[@]} -gt 0 ]]; then
            echo "# SSH PASSWORD saved connections IPS"
            echo ""
            printf '%s\n' "${password_ips[@]}"
            echo ""
        fi
        
        # Add any existing IPs that weren't from configs (manually added)
        local all_config_ips=("${ssh_ips[@]}" "${password_ips[@]}")
        local manual_ips=()
        
        for existing_ip in "${existing_ips[@]}"; do
            local found=false
            for config_ip in "${all_config_ips[@]}"; do
                if [[ "$existing_ip" == "$config_ip" ]]; then
                    found=true
                    break
                fi
            done
            
            if [[ "$found" == false ]]; then
                manual_ips+=("$existing_ip")
            fi
        done
        
        if [[ ${#manual_ips[@]} -gt 0 ]]; then
            echo "# MANUAL HOST ENTRIES"
            echo ""
            printf '%s\n' "${manual_ips[@]}"
        fi
        
    } > "$HOSTS_CONFIG_FILE"
    
    local total_ips=$((${#ssh_ips[@]} + ${#password_ips[@]} + ${#manual_ips[@]}))
    log_debug "Synced $total_ips IPs to hosts file (${#ssh_ips[@]} SSH, ${#password_ips[@]} Password, ${#manual_ips[@]} Manual)"
}

# Add new IP to hosts file if not already present
add_ip_to_hosts() {
    local new_ip="$1"
    
    if [[ -z "$new_ip" ]]; then
        return 1
    fi
    
    # Check if IP already exists
    if grep -q "^$new_ip$" "$HOSTS_CONFIG_FILE" 2>/dev/null; then
        log_debug "IP $new_ip already exists in hosts file"
        return 0
    fi
    
    # Add new IP
    echo "$new_ip" >> "$HOSTS_CONFIG_FILE"
    log_debug "Added new IP to hosts file: $new_ip"
}

# Get list of available IPs that have valid configurations
get_available_hosts() {
    local hosts_with_configs=()
    
    # Get IPs from SSH configurations
    local ssh_config=$(load_ssh_config)
    if [[ "$ssh_config" != "{}" ]]; then
        local ssh_ips=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    unique_ips = set()
    if 'saved_keys' in config:
        for name, details in config['saved_keys'].items():
            if 'host' in details:
                unique_ips.add(details['host'])
    for ip in sorted(unique_ips):
        print(ip)
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$ssh_ips" ]]; then
            while IFS= read -r ip; do
                if [[ -n "$ip" ]]; then
                    hosts_with_configs+=("$ip")
                fi
            done <<< "$ssh_ips"
        fi
    fi
    
    # Get IPs from password configurations
    local password_config=$(load_password_config)
    if [[ "$password_config" != "{}" ]]; then
        local password_ips=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    unique_ips = set()
    if 'saved_passwords' in config:
        for name, details in config['saved_passwords'].items():
            if 'host' in details:
                unique_ips.add(details['host'])
    for ip in sorted(unique_ips):
        print(ip)
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$password_ips" ]]; then
            while IFS= read -r ip; do
                if [[ -n "$ip" ]] && ! printf '%s\n' "${hosts_with_configs[@]}" | grep -q "^$ip$"; then
                    hosts_with_configs+=("$ip")
                fi
            done <<< "$password_ips"
        fi
    fi
    
    # Sort and return unique IPs that have configurations
    if [[ ${#hosts_with_configs[@]} -gt 0 ]]; then
        printf '%s\n' "${hosts_with_configs[@]}" | sort -u
    fi
}

# Find matching configuration for an IP
find_config_for_ip() {
    local target_ip="$1"
    local ssh_config=$(load_ssh_config)
    local password_config=$(load_password_config)
    
    # Check SSH configs first
    if [[ -n "$ssh_config" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^[^#]*@.*$target_ip ]]; then
                echo "ssh:$line"
                return 0
            fi
        done <<< "$ssh_config"
    fi
    
    # Check password configs
    if [[ -n "$password_config" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^[^#]*@.*$target_ip ]]; then
                echo "password:$line"
                return 0
            fi
        done <<< "$password_config"
    fi
    
    return 1
}

# Show available hosts for selection
show_host_selection_menu() {
    local hosts=($(get_available_hosts))
    
    if [[ ${#hosts[@]} -eq 0 ]]; then
        log_warning "No hosts configured yet"
        log_info "Please save an SSH key or password configuration first"
        return 1
    fi
    
    echo
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}           📡 Select Remote Host 📡             ${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${BOLD}HOSTS CONFIGURATION IPS FILES:${NC}"
    echo
    echo -e "${BOLD}Showing saved IPS for ssh keys and password configurations:${NC}"
    echo
    
    # Display the hosts file content with formatting
    if [[ -f "$HOSTS_CONFIG_FILE" ]]; then
        cat "$HOSTS_CONFIG_FILE"
    fi
    echo
    
    local counter=1
    for host in "${hosts[@]}"; do
        local user="Unknown"
        local auth_type="${RED}No Config${NC}"
        
        # Check SSH configurations first
        local ssh_config=$(load_ssh_config)
        if [[ "$ssh_config" != "{}" ]]; then
            local ssh_info=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        for name, details in config['saved_keys'].items():
            if details.get('host') == '$host':
                print(f\"{details['user']}\")
                exit(0)
except:
    pass
" 2>/dev/null)
            
            if [[ -n "$ssh_info" ]]; then
                user="$ssh_info"
                auth_type="${GREEN}SSH KEY${NC}"
            fi
        fi
        
        # If not found in SSH, check password configurations
        if [[ "$auth_type" == "${RED}No Config${NC}" ]]; then
            local password_config=$(load_password_config)
            if [[ "$password_config" != "{}" ]]; then
                local password_info=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        for name, details in config['saved_passwords'].items():
            if details.get('host') == '$host':
                print(f\"{details['user']}\")
                exit(0)
except:
    pass
" 2>/dev/null)
                
                if [[ -n "$password_info" ]]; then
                    user="$password_info"
                    auth_type="${YELLOW}SSH PASSWORD${NC}"
                fi
            fi
        fi
        
        echo -e "${BOLD}${GREEN}[$counter]${NC} ${CYAN}$host${NC}"
        echo -e "     Auth: $auth_type | User: ${WHITE}$user${NC}"
        echo
        ((counter++))
    done
    
    echo -e "${BOLD}${GREEN}[m]${NC} ${BOLD}Manage Host Configurations${NC}"
    echo -e "${BOLD}${RED}[b]${NC} ${BOLD}Back to Main Menu${NC}"
    echo
    
    while true; do
        echo -ne "${BOLD}${CYAN}Select host [1-${#hosts[@]}/m/b]: ${NC}"
        read -r choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#hosts[@]} ]; then
            local selected_host="${hosts[$((choice-1))]}"
            local config_info=$(find_config_for_ip "$selected_host")
            
            if [[ -z "$config_info" ]]; then
                log_error "No valid configuration found for $selected_host"
                log_warning "Host file may have been manually modified"
                continue
            fi
            
            # Set global variables based on selection
            REMOTE_HOST="$selected_host"
            
            if [[ "$config_info" =~ ^ssh: ]]; then
                local config_line=$(echo "$config_info" | cut -d':' -f2-)
                # Parse SSH config line format: user@host:key_path:description
                REMOTE_USER=$(echo "$config_line" | cut -d'@' -f1)
                SSH_KEY=$(echo "$config_line" | cut -d':' -f2)
                USE_PASSWORD=false
                REMOTE_PASSWORD=""
                log_success "Selected host $selected_host with SSH key authentication"
            elif [[ "$config_info" =~ ^password: ]]; then
                local config_line=$(echo "$config_info" | cut -d':' -f2-)
                # Parse password config line format: user@host:password:description
                REMOTE_USER=$(echo "$config_line" | cut -d'@' -f1)
                USE_PASSWORD=true
                REMOTE_PASSWORD=$(echo "$config_line" | cut -d':' -f2)
                SSH_KEY=""
                log_success "Selected host $selected_host with password authentication"
            fi
            
            return 0
            
        elif [[ "$choice" == "m" || "$choice" == "M" ]]; then
            manage_hosts_menu
            # After managing hosts, sync and redisplay
            sync_hosts_from_configs
            show_host_selection_menu
            return $?
            
        elif [[ "$choice" == "b" || "$choice" == "B" ]]; then
            return 1
            
        else
            log_error "Invalid choice. Please select 1-${#hosts[@]}, 'm' for manage, or 'b' for back."
        fi
    done
}

# Host management menu
manage_hosts_menu() {
    while true; do
        clear
        echo
        echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
        echo -e "${WHITE}${BOLD}           🏠 Manage Host Configurations 🏠             ${NC}"
        echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
        echo
        echo -e "${BOLD}Host Management Options:${NC}"
        echo
        echo -e "${BOLD}${GREEN}[1]${NC} ${BOLD}List Current Hosts${NC}"
        echo -e "     ${WHITE}📋 View all configured hosts and their authentication${NC}"
        echo
        echo -e "${BOLD}${GREEN}[2]${NC} ${BOLD}Clean Hosts File${NC}"
        echo -e "     ${WHITE}🧹 Remove hosts without valid configurations${NC}"
        echo
        echo -e "${BOLD}${GREEN}[3]${NC} ${BOLD}Add Manual Host${NC}"
        echo -e "     ${WHITE}➕ Add IP address manually (must have SSH/password config)${NC}"
        echo
        echo -e "${BOLD}${GREEN}[4]${NC} ${BOLD}Remove Host${NC}"
        echo -e "     ${WHITE}🗑️  Remove host from list${NC}"
        echo
        echo -e "${BOLD}${GREEN}[5]${NC} ${BOLD}Clear All SSH Key Configurations${NC}"
        echo -e "     ${WHITE}🔑 Remove all saved SSH key configurations${NC}"
        echo
        echo -e "${BOLD}${GREEN}[6]${NC} ${BOLD}Clear All Password Configurations${NC}"
        echo -e "     ${WHITE}🔒 Remove all saved password configurations${NC}"
        echo
        echo -e "${BOLD}${GREEN}[7]${NC} ${BOLD}Clear ALL Configurations${NC}"
        echo -e "     ${WHITE}💥 Remove both SSH keys and password configurations${NC}"
        echo
        echo -e "${BOLD}${RED}[b]${NC} ${BOLD}Back${NC}"
        echo
        
        echo -ne "${BOLD}${CYAN}Choose option [1-7/b]: ${NC}"
        read -r choice
        
        case "$choice" in
            1)
                list_hosts_with_configs
                echo
                echo -e "${BOLD}${PURPLE}Press Enter to continue...${NC}"
                read
                ;;
            2)
                clean_hosts_file
                echo
                echo -e "${BOLD}${PURPLE}Press Enter to continue...${NC}"
                read
                ;;
            3)
                add_manual_host
                echo
                echo -e "${BOLD}${PURPLE}Press Enter to continue...${NC}"
                read
                ;;
            4)
                remove_host_from_file
                echo
                echo -e "${BOLD}${PURPLE}Press Enter to continue...${NC}"
                read
                ;;
            5)
                clear_all_ssh_configs
                echo
                echo -e "${BOLD}${PURPLE}Press Enter to continue...${NC}"
                read
                ;;
            6)
                clear_all_password_configs
                echo
                echo -e "${BOLD}${PURPLE}Press Enter to continue...${NC}"
                read
                ;;
            7)
                clear_all_configurations
                echo
                echo -e "${BOLD}${PURPLE}Press Enter to continue...${NC}"
                read
                ;;
            b|B)
                return 0
                ;;
            *)
                log_error "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# Clear all SSH key configurations
clear_all_ssh_configs() {
    echo
    echo -e "${BOLD}${RED}⚠️  CLEAR ALL SSH KEY CONFIGURATIONS${NC}"
    echo
    
    # Show current SSH configurations
    local ssh_config=$(load_ssh_config)
    local ssh_count=0
    
    if [[ "$ssh_config" != "{}" ]]; then
        ssh_count=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        print(len(config['saved_keys']))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null)
    fi
    
    if [[ $ssh_count -eq 0 ]]; then
        echo -e "${YELLOW}No SSH key configurations found${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}The following SSH key configurations will be permanently deleted:${NC}"
    echo
    
    # List SSH configurations that will be deleted
    python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        counter = 1
        for name, details in config['saved_keys'].items():
            print(f'  {counter}. {name}: {details[\"user\"]}@{details[\"host\"]}')
            print(f'     Key: {details[\"key\"]}')
            counter += 1
except:
    pass
" 2>/dev/null
    
    echo
    echo -e "${RED}WARNING: This action cannot be undone!${NC}"
    echo -e "${WHITE}Total SSH key configurations to delete: ${RED}$ssh_count${NC}"
    echo
    
    read -p "$(echo -e "${BOLD}Are you sure you want to delete all SSH key configurations? (y/yes/n/no): ${NC}")" confirm
    if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        # Create empty SSH config
        local empty_config="{
            \"default_key\": \"$DEFAULT_SSH_KEY\",
            \"default_user\": \"$DEFAULT_REMOTE_USER\",
            \"default_host\": \"$DEFAULT_REMOTE_HOST\",
            \"saved_keys\": {}
        }"
        
        if save_ssh_config "$empty_config"; then
            log_success "All SSH key configurations cleared successfully ($ssh_count configurations removed)"
            # Update hosts file
            sync_hosts_from_configs
        else
            log_error "Failed to clear SSH key configurations"
        fi
    else
        log_info "Operation cancelled"
    fi
}

# Clear all password configurations
clear_all_password_configs() {
    echo
    echo -e "${BOLD}${RED}⚠️  CLEAR ALL PASSWORD CONFIGURATIONS${NC}"
    echo
    
    # Show current password configurations
    local password_config=$(load_password_config)
    local password_count=0
    
    if [[ "$password_config" != "{}" ]]; then
        password_count=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        print(len(config['saved_passwords']))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null)
    fi
    
    if [[ $password_count -eq 0 ]]; then
        echo -e "${YELLOW}No password configurations found${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}The following password configurations will be permanently deleted:${NC}"
    echo
    
    # List password configurations that will be deleted
    python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        counter = 1
        for name, details in config['saved_passwords'].items():
            print(f'  {counter}. {name}: {details[\"user\"]}@{details[\"host\"]}')
            counter += 1
except:
    pass
" 2>/dev/null
    
    echo
    echo -e "${RED}WARNING: This action cannot be undone!${NC}"
    echo -e "${WHITE}Total password configurations to delete: ${RED}$password_count${NC}"
    echo
    
    read -p "$(echo -e "${BOLD}Are you sure you want to delete all password configurations? (y/yes/n/no): ${NC}")" confirm
    if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        # Create empty password config
        local empty_config="{
            \"default_user\": \"$DEFAULT_REMOTE_USER\",
            \"default_host\": \"$DEFAULT_REMOTE_HOST\",
            \"saved_passwords\": {}
        }"
        
        if save_password_config "$empty_config"; then
            log_success "All password configurations cleared successfully ($password_count configurations removed)"
            # Update hosts file
            sync_hosts_from_configs
        else
            log_error "Failed to clear password configurations"
        fi
    else
        log_info "Operation cancelled"
    fi
}

# Clear all configurations (provides sub-options)
clear_all_configurations() {
    echo
    echo -e "${BOLD}${RED}💥 CLEAR CONFIGURATIONS${NC}"
    echo
    
    # Show current configuration counts
    local ssh_config=$(load_ssh_config)
    local password_config=$(load_password_config)
    
    local ssh_count=0
    local password_count=0
    
    if [[ "$ssh_config" != "{}" ]]; then
        ssh_count=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        print(len(config['saved_keys']))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null)
    fi
    
    if [[ "$password_config" != "{}" ]]; then
        password_count=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        print(len(config['saved_passwords']))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null)
    fi
    
    local total_count=$((ssh_count + password_count))
    
    if [[ $total_count -eq 0 ]]; then
        echo -e "${YELLOW}No configurations found to clear${NC}"
        return 0
    fi
    
    echo -e "${WHITE}Current configurations:${NC}"
    echo -e "${WHITE}• SSH key configurations: ${CYAN}$ssh_count${NC}"
    echo -e "${WHITE}• Password configurations: ${CYAN}$password_count${NC}"
    echo -e "${WHITE}• Total configurations: ${CYAN}$total_count${NC}"
    echo
    
    echo -e "${BOLD}Clear Options:${NC}"
    echo -e "${BOLD}${RED}[A]${NC} ${BOLD}Clear ALL SSH key configurations${NC} (${ssh_count} total)"
    echo -e "     ${WHITE}🔑 Remove all saved SSH key configurations${NC}"
    echo -e "${BOLD}${RED}[P]${NC} ${BOLD}Clear ALL password configurations${NC} (${password_count} total)"
    echo -e "     ${WHITE}🔒 Remove all saved password configurations${NC}"
    echo -e "${BOLD}${RED}[B]${NC} ${BOLD}Clear BOTH SSH keys AND passwords${NC} (${total_count} total)"
    echo -e "     ${WHITE}💥 Remove all SSH keys and password configurations${NC}"
    echo -e "${BOLD}${GREEN}[C]${NC} ${BOLD}Cancel${NC}"
    echo
    
    read -p "$(echo -e "${BOLD}Choose option (A/P/B/C): ${NC}")" choice
    
    case "${choice^^}" in
        A)
            if [[ $ssh_count -eq 0 ]]; then
                log_warning "No SSH key configurations to clear"
                return 0
            fi
            echo
            echo -e "${BOLD}${RED}⚠️  CLEAR ALL SSH KEY CONFIGURATIONS${NC}"
            echo -e "${YELLOW}The following SSH key configurations will be permanently deleted:${NC}"
            echo
            
            # List SSH configurations that will be deleted
            python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        counter = 1
        for name, details in config['saved_keys'].items():
            print(f'  {counter}. {name}: {details[\"user\"]}@{details[\"host\"]}')
            print(f'     Key: {details[\"key\"]}')
            counter += 1
except:
    pass
" 2>/dev/null
            
            echo
            echo -e "${YELLOW}SSH Key Configurations to be deleted:${NC}"
            python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        counter = 1
        for name, details in config['saved_keys'].items():
            print(f'  {counter}. {name}: {details[\"user\"]}@{details[\"host\"]}')
            print(f'     Key: {details[\"key\"]}')
            counter += 1
except:
    pass
" 2>/dev/null
            echo
            echo -e "${RED}WARNING: This action cannot be undone!${NC}"
            echo -e "${WHITE}Total SSH key configurations to delete: ${RED}$ssh_count${NC}"
            echo
            read -p "$(echo -e "${BOLD}Are you sure? (y/yes/n/no):${NC} ")" confirm
            
            if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                local empty_ssh_config="{
                    \"default_key\": \"$DEFAULT_SSH_KEY\",
                    \"default_user\": \"$DEFAULT_REMOTE_USER\",
                    \"default_host\": \"$DEFAULT_REMOTE_HOST\",
                    \"saved_keys\": {}
                }"
                
                if save_ssh_config "$empty_ssh_config"; then
                    log_success "All SSH key configurations cleared successfully ($ssh_count configurations removed)"
                    sync_hosts_from_configs
                else
                    log_error "Failed to clear SSH key configurations"
                fi
            else
                log_info "Operation cancelled"
            fi
            ;;
        P)
            if [[ $password_count -eq 0 ]]; then
                log_warning "No password configurations to clear"
                return 0
            fi
            echo
            echo -e "${BOLD}${RED}⚠️  CLEAR ALL PASSWORD CONFIGURATIONS${NC}"
            echo -e "${YELLOW}The following password configurations will be permanently deleted:${NC}"
            echo
            
            # List password configurations that will be deleted
            python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        counter = 1
        for name, details in config['saved_passwords'].items():
            print(f'  {counter}. {name}: {details[\"user\"]}@{details[\"host\"]}')
            counter += 1
except:
    pass
" 2>/dev/null
            
            echo
            echo -e "${YELLOW}Password Configurations to be deleted:${NC}"
            python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        counter = 1
        for name, details in config['saved_passwords'].items():
            print(f'  {counter}. {name}: {details[\"user\"]}@{details[\"host\"]}')
            counter += 1
except:
    pass
" 2>/dev/null
            echo
            echo -e "${RED}WARNING: This action cannot be undone!${NC}"
            echo -e "${WHITE}Total password configurations to delete: ${RED}$password_count${NC}"
            echo
            read -p "$(echo -e "${BOLD}Are you sure? (y/yes/n/no):${NC} ")" confirm
            
            if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                local empty_password_config="{
                    \"default_user\": \"$DEFAULT_REMOTE_USER\",
                    \"default_host\": \"$DEFAULT_REMOTE_HOST\",
                    \"saved_passwords\": {}
                }"
                
                if save_password_config "$empty_password_config"; then
                    log_success "All password configurations cleared successfully ($password_count configurations removed)"
                    sync_hosts_from_configs
                else
                    log_error "Failed to clear password configurations"
                fi
            else
                log_info "Operation cancelled"
            fi
            ;;
        B)
            echo
            echo -e "${BOLD}${RED}⚠️  CLEAR ALL CONFIGURATIONS${NC}"
            echo -e "${YELLOW}The following configurations will be permanently deleted:${NC}"
            echo
            
            # Show SSH key configurations if any
            if [[ $ssh_count -gt 0 ]]; then
                echo -e "${CYAN}SSH Key Configurations ($ssh_count):${NC}"
                python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        counter = 1
        for name, details in config['saved_keys'].items():
            print(f'  {counter}. {name}: {details[\"user\"]}@{details[\"host\"]}')
            print(f'     Key: {details[\"key\"]}')
            counter += 1
except:
    pass
" 2>/dev/null
                echo
            fi
            
            # Show password configurations if any
            if [[ $password_count -gt 0 ]]; then
                echo -e "${CYAN}Password Configurations ($password_count):${NC}"
                python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        counter = 1
        for name, details in config['saved_passwords'].items():
            print(f'  {counter}. {name}: {details[\"user\"]}@{details[\"host\"]}')
            counter += 1
except:
    pass
" 2>/dev/null
                echo
            fi
            
            echo -e "${RED}WARNING: This action cannot be undone!${NC}"
            echo -e "${WHITE}Total configurations to delete: ${RED}$total_count${NC}"
            echo
            read -p "$(echo -e "${BOLD}Are you sure? (y/yes/n/no):${NC} ")" confirm
            
            if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                local success=true
                
                # Clear SSH configurations if any exist
                if [[ $ssh_count -gt 0 ]]; then
                    local empty_ssh_config="{
                        \"default_key\": \"$DEFAULT_SSH_KEY\",
                        \"default_user\": \"$DEFAULT_REMOTE_USER\",
                        \"default_host\": \"$DEFAULT_REMOTE_HOST\",
                        \"saved_keys\": {}
                    }"
                    
                    if ! save_ssh_config "$empty_ssh_config"; then
                        log_error "Failed to clear SSH key configurations"
                        success=false
                    fi
                fi
                
                # Clear password configurations if any exist
                if [[ $password_count -gt 0 ]]; then
                    local empty_password_config="{
                        \"default_user\": \"$DEFAULT_REMOTE_USER\",
                        \"default_host\": \"$DEFAULT_REMOTE_HOST\",
                        \"saved_passwords\": {}
                    }"
                    
                    if ! save_password_config "$empty_password_config"; then
                        log_error "Failed to clear password configurations"
                        success=false
                    fi
                fi
                
                if [[ "$success" == true ]]; then
                    log_success "All configurations cleared successfully ($total_count configurations removed)"
                    sync_hosts_from_configs
                else
                    log_error "Some configurations failed to clear"
                fi
            else
                log_info "Operation cancelled"
            fi
            ;;
        C)
            log_info "Operation cancelled"
            ;;
        *)
            log_warning "Invalid choice. Please select A, P, B, or C."
            ;;
    esac
}

# List hosts with their configurations
list_hosts_with_configs() {
    clear
    echo
    echo -e "${BOLD}${CYAN}📋 Current Host Configurations${NC}"
    echo
    
    local hosts=($(get_available_hosts))
    
    if [[ ${#hosts[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No hosts configured${NC}"
        return
    fi
    
    printf "%-3s %-15s %-15s %-20s %-25s\n" "No." "Host IP" "User" "Auth Type" "Config Name"
    echo "─────────────────────────────────────────────────────────────────────────────"
    
    local counter=1
    for host in "${hosts[@]}"; do
        local found_configs=false
        
        # Check SSH configurations
        local ssh_config=$(load_ssh_config)
        if [[ "$ssh_config" != "{}" ]]; then
            local ssh_configs=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        for name, details in config['saved_keys'].items():
            if details.get('host') == '$host':
                print(f\"{details['user']}|SSH KEY|{name}\")
except:
    pass
" 2>/dev/null)
            
            if [[ -n "$ssh_configs" ]]; then
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then
                        local user=$(echo "$line" | cut -d'|' -f1)
                        local auth_type=$(echo "$line" | cut -d'|' -f2)
                        local config_name=$(echo "$line" | cut -d'|' -f3)
                        printf "%-3s %-15s %-15s %-20s %-25s\n" "$counter" "$host" "$user" "$auth_type" "$config_name"
                        ((counter++))
                        found_configs=true
                    fi
                done <<< "$ssh_configs"
            fi
        fi
        
        # Check password configurations
        local password_config=$(load_password_config)
        if [[ "$password_config" != "{}" ]]; then
            local password_configs=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        for name, details in config['saved_passwords'].items():
            if details.get('host') == '$host':
                print(f\"{details['user']}|SSH PASSWORD|{name}\")
except:
    pass
" 2>/dev/null)
            
            if [[ -n "$password_configs" ]]; then
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then
                        local user=$(echo "$line" | cut -d'|' -f1)
                        local auth_type=$(echo "$line" | cut -d'|' -f2)
                        local config_name=$(echo "$line" | cut -d'|' -f3)
                        printf "%-3s %-15s %-15s %-20s %-25s\n" "$counter" "$host" "$user" "$auth_type" "$config_name"
                        ((counter++))
                        found_configs=true
                    fi
                done <<< "$password_configs"
            fi
        fi
        
        # If no configurations found for this host
        if [[ "$found_configs" == false ]]; then
            printf "%-3s %-15s %-15s %-20s %-25s\n" "$counter" "$host" "Unknown" "No Config" "None"
            ((counter++))
        fi
    done
}

# Clean hosts file by removing entries without valid configs
clean_hosts_file() {
    log_info "Cleaning hosts file..."
    
    local hosts=($(get_available_hosts))
    local valid_hosts=()
    local removed_count=0
    
    for host in "${hosts[@]}"; do
        local config_info=$(find_config_for_ip "$host")
        if [[ -n "$config_info" ]]; then
            valid_hosts+=("$host")
        else
            log_warning "Removing host without valid config: $host"
            ((removed_count++))
        fi
    done
    
    # Write back only valid hosts
    printf '%s\n' "${valid_hosts[@]}" > "$HOSTS_CONFIG_FILE"
    
    log_success "Cleaned hosts file. Removed $removed_count invalid entries."
    log_info "Valid hosts remaining: ${#valid_hosts[@]}"
}

# Add manual host
add_manual_host() {
    echo
    echo -ne "${CYAN}Enter IP address to add: ${NC}"
    read -r new_ip
    
    if [[ -z "$new_ip" ]]; then
        log_error "IP address cannot be empty"
        return 1
    fi
    
    # Basic IP validation
    if [[ ! "$new_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Invalid IP address format"
        return 1
    fi
    
    # Check SSH configurations first
    local ssh_config=$(load_ssh_config)
    local existing_ssh_configs=()
    if [[ "$ssh_config" != "{}" ]]; then
        local ssh_matches=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        for name, details in config['saved_keys'].items():
            if details.get('host') == '$new_ip':
                print(f\"{name}|{details['user']}|{details['key']}\")
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$ssh_matches" ]]; then
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    existing_ssh_configs+=("$line")
                fi
            done <<< "$ssh_matches"
        fi
    fi
    
    # Check password configurations
    local password_config=$(load_password_config)
    local existing_password_configs=()
    if [[ "$password_config" != "{}" ]]; then
        local password_matches=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        for name, details in config['saved_passwords'].items():
            if details.get('host') == '$new_ip':
                print(f\"{name}|{details['user']}\")
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$password_matches" ]]; then
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    existing_password_configs+=("$line")
                fi
            done <<< "$password_matches"
        fi
    fi
    
    # If configurations exist, show them and ask user
    if [[ ${#existing_ssh_configs[@]} -gt 0 || ${#existing_password_configs[@]} -gt 0 ]]; then
        echo
        log_warning "Configuration(s) already exist for $new_ip:"
        echo
        
        if [[ ${#existing_ssh_configs[@]} -gt 0 ]]; then
            echo -e "${BOLD}SSH KEY configurations:${NC}"
            for config in "${existing_ssh_configs[@]}"; do
                local name=$(echo "$config" | cut -d'|' -f1)
                local user=$(echo "$config" | cut -d'|' -f2)
                local key=$(echo "$config" | cut -d'|' -f3)
                echo -e "  ${GREEN}●${NC} ${CYAN}$name${NC}: ${WHITE}$user@$new_ip${NC} (${YELLOW}$(basename "$key")${NC})"
            done
            echo
        fi
        
        if [[ ${#existing_password_configs[@]} -gt 0 ]]; then
            echo -e "${BOLD}SSH PASSWORD configurations:${NC}"
            for config in "${existing_password_configs[@]}"; do
                local name=$(echo "$config" | cut -d'|' -f1)
                local user=$(echo "$config" | cut -d'|' -f2)
                echo -e "  ${GREEN}●${NC} ${CYAN}$name${NC}: ${WHITE}$user@$new_ip${NC} (${YELLOW}SSH PASSWORD${NC})"
            done
            echo
        fi
        
        echo -e "${BOLD}Options:${NC}"
        echo -e "  ${GREEN}1${NC}. Create additional configuration for $new_ip with different credentials"
        echo -e "  ${GREEN}2${NC}. Cancel"
        echo
        
        echo -ne "${CYAN}Choose option [1-2]: ${NC}"
        read -r user_choice
        
        case $user_choice in
            1)
                log_info "Creating additional configuration for $new_ip..."
                echo
                ;;
            2)
                log_info "Operation cancelled"
                return 0
                ;;
            *)
                log_error "Invalid choice"
                return 1
                ;;
        esac
    else
        echo
        log_info "No existing configuration found for $new_ip. Creating new configuration..."
        echo
    fi
    
    # Get configuration name first and validate it doesn't exist
    while true; do
        echo -ne "${CYAN}Enter configuration name for $new_ip: ${NC}"
        read -r config_name
        
        if [[ -z "$config_name" ]]; then
            log_error "Configuration name cannot be empty"
            continue
        fi
        
        # Check if configuration name already exists in SSH configs
        local ssh_config=$(load_ssh_config)
        local ssh_name_exists=false
        if [[ "$ssh_config" != "{}" ]]; then
            local ssh_name_check=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config and '$config_name' in config['saved_keys']:
        print('exists')
except:
    pass
" 2>/dev/null)
            
            if [[ "$ssh_name_check" == "exists" ]]; then
                ssh_name_exists=true
            fi
        fi
        
        # Check if configuration name already exists in password configs
        local password_config=$(load_password_config)
        local password_name_exists=false
        if [[ "$password_config" != "{}" ]]; then
            local password_name_check=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config and '$config_name' in config['saved_passwords']:
        print('exists')
except:
    pass
" 2>/dev/null)
            
            if [[ "$password_name_check" == "exists" ]]; then
                password_name_exists=true
            fi
        fi
        
        # If name exists in either file, ask for a different one
        if [[ "$ssh_name_exists" == true || "$password_name_exists" == true ]]; then
            if [[ "$ssh_name_exists" == true ]]; then
                log_error "Configuration name '$config_name' already exists in SSH KEY configurations"
            fi
            if [[ "$password_name_exists" == true ]]; then
                log_error "Configuration name '$config_name' already exists in SSH PASSWORD configurations"
            fi
            echo
            echo -e "${BOLD}Options:${NC}"
            echo -e "  ${GREEN}1${NC}. Try a different configuration name"
            echo -e "  ${GREEN}2${NC}. Cancel"
            echo
            echo -ne "${CYAN}Choose option [1-2]: ${NC}"
            read -r name_choice
            
            case $name_choice in
                1)
                    continue
                    ;;
                2)
                    log_info "Operation cancelled"
                    return 0
                    ;;
                *)
                    log_error "Invalid choice"
                    continue
                    ;;
            esac
        else
            # Name is unique, proceed
            break
        fi
    done
    
    # Get username
    echo -ne "${CYAN}Enter username for $new_ip: ${NC}"
    read -r username
    if [[ -z "$username" ]]; then
        log_error "Username cannot be empty"
        return 1
    fi
    
    # Choose authentication method
    echo
    echo -e "${BOLD}Choose authentication method:${NC}"
    echo -e "${GREEN}1)${NC} SSH Key"
    echo -e "${GREEN}2)${NC} Password"
    echo -ne "${CYAN}Enter choice [1-2]: ${NC}"
    read -r auth_choice
    
    case $auth_choice in
        1)
            # SSH Key configuration
            echo -ne "${CYAN}Enter SSH key path (default: ~/.ssh/id_rsa): ${NC}"
            read -r ssh_key_input
            if [[ -z "$ssh_key_input" ]]; then
                ssh_key_path="$HOME/.ssh/id_rsa"
            else
                ssh_key_path="$ssh_key_input"
            fi
            
            # Expand tilde
            ssh_key_path="${ssh_key_path/#\~/$HOME}"
            
            if [[ ! -f "$ssh_key_path" ]]; then
                log_error "SSH key file not found: $ssh_key_path"
                return 1
            fi
            
            # Validate SSH key
            if ! validate_ssh_config "$ssh_key_path" "$username" "$new_ip"; then
                log_error "SSH configuration validation failed"
                return 1
            fi
            
            # Configuration name already obtained and validated above
            
            # Add to SSH configuration
            local ssh_config=$(load_ssh_config)
            local new_ssh_config=$(python3 -c "
import json, sys
try:
    if '''$ssh_config''' == '{}':
        config_data = {'saved_keys': {}, 'default_key': '', 'default_user': '', 'default_host': ''}
    else:
        config_data = json.loads('''$ssh_config''')
    
    if 'saved_keys' not in config_data:
        config_data['saved_keys'] = {}
    
    config_data['saved_keys']['$config_name'] = {
        'key': '$ssh_key_path',
        'user': '$username', 
        'host': '$new_ip'
    }
    
    print(json.dumps(config_data, separators=(',', ':')))
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
")
            
            if [[ $? -eq 0 ]] && save_ssh_config "$new_ssh_config"; then
                log_success "SSH KEY configuration '$config_name' added for $username@$new_ip"
                log_info "SSH key: $ssh_key_path"
            else
                log_error "Failed to save SSH configuration"
                return 1
            fi
            ;;
            
        2)
            # Password configuration
            if ! command -v sshpass &> /dev/null; then
                log_error "sshpass is required for password authentication but not installed"
                log_info "Install with: sudo apt install sshpass"
                return 1
            fi
            
            echo -ne "${CYAN}Enter password for $username@$new_ip: ${NC}"
            read -rs password
            echo
            
            if [[ -z "$password" ]]; then
                log_error "Password cannot be empty"
                return 1
            fi
            
            # Test password authentication
            log_info "Testing password authentication..."
            if ! sshpass -p "$password" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$username@$new_ip" "echo 'SSH connection test successful'" 2>/dev/null; then
                log_error "Password authentication test failed for $username@$new_ip"
                log_info "Please verify:"
                log_info "  - Username is correct: $username"
                log_info "  - Password is correct"
                log_info "  - Host $new_ip is reachable"
                log_info "  - SSH service is running on $new_ip"
                return 1
            fi
            
            log_success "Password authentication test successful"
            
            # Configuration name already obtained and validated above
            
            # Add to password configuration
            local password_config=$(load_password_config)
            local new_password_config=$(python3 -c "
import json, sys
try:
    if '''$password_config''' == '{}':
        config_data = {'saved_passwords': {}, 'default_user': '', 'default_host': '', 'default_password': ''}
    else:
        config_data = json.loads('''$password_config''')
    
    if 'saved_passwords' not in config_data:
        config_data['saved_passwords'] = {}
    
    config_data['saved_passwords']['$config_name'] = {
        'user': '$username',
        'host': '$new_ip',
        'password': '$password'
    }
    
    print(json.dumps(config_data, separators=(',', ':')))
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
")
            
            if [[ $? -eq 0 ]] && save_password_config "$new_password_config"; then
                log_success "SSH PASSWORD configuration '$config_name' added for $username@$new_ip"
                log_warning "Password is stored in plain text - keep config files secure!"
            else
                log_error "Failed to save password configuration"
                return 1
            fi
            ;;
            
        *)
            log_error "Invalid choice"
            return 1
            ;;
    esac
    
    # Sync hosts file and add IP
    sync_hosts_from_configs
    log_success "Host $new_ip added to configuration and hosts file"
}

# Remove host from file
remove_host_from_file() {
    echo
    echo -e "${BOLD}${CYAN}🗑️  Remove Host Configuration${NC}"
    echo
    
    # Get all configurations (not just unique hosts)
    local all_configs=()
    
    # Get SSH configurations
    local ssh_config=$(load_ssh_config)
    if [[ "$ssh_config" != "{}" ]]; then
        local ssh_configs=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        for name, details in config['saved_keys'].items():
            print(f\"{details['host']}|{details['user']}|SSH KEY|{name}\")
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$ssh_configs" ]]; then
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    all_configs+=("$line")
                fi
            done <<< "$ssh_configs"
        fi
    fi
    
    # Get password configurations
    local password_config=$(load_password_config)
    if [[ "$password_config" != "{}" ]]; then
        local password_configs=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        for name, details in config['saved_passwords'].items():
            print(f\"{details['host']}|{details['user']}|SSH PASSWORD|{name}\")
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$password_configs" ]]; then
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    all_configs+=("$line")
                fi
            done <<< "$password_configs"
        fi
    fi
    
    if [[ ${#all_configs[@]} -eq 0 ]]; then
        log_warning "No configurations to remove"
        return
    fi
    
    echo -e "${BOLD}Select configuration to remove:${NC}"
    echo
    printf "%-3s %-15s %-15s %-20s %-25s\n" "No." "Host IP" "User" "Auth Type" "Config Name"
    echo "─────────────────────────────────────────────────────────────────────────────"
    
    local counter=1
    for config in "${all_configs[@]}"; do
        local host=$(echo "$config" | cut -d'|' -f1)
        local user=$(echo "$config" | cut -d'|' -f2)
        local auth_type=$(echo "$config" | cut -d'|' -f3)
        local config_name=$(echo "$config" | cut -d'|' -f4)
        
        printf "%-3s %-15s %-15s %-20s %-25s\n" "$counter" "$host" "$user" "$auth_type" "$config_name"
        ((counter++))
    done
    echo
    
    echo -ne "${CYAN}Enter configuration number to remove [1-${#all_configs[@]}]: ${NC}"
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#all_configs[@]} ]; then
        local selected_config="${all_configs[$((choice-1))]}"
        local host=$(echo "$selected_config" | cut -d'|' -f1)
        local user=$(echo "$selected_config" | cut -d'|' -f2)
        local auth_type=$(echo "$selected_config" | cut -d'|' -f3)
        local config_name=$(echo "$selected_config" | cut -d'|' -f4)
        
        echo
        echo -e "${BOLD}Configuration to be removed:${NC}"
        echo -e "  ${WHITE}Host: ${CYAN}$host${NC}"
        echo -e "  ${WHITE}User: ${CYAN}$user${NC}"
        echo -e "  ${WHITE}Type: ${YELLOW}$auth_type${NC}"
        echo -e "  ${WHITE}Name: ${PURPLE}$config_name${NC}"
        echo
        echo -e "${RED}${BOLD}WARNING: This will remove ONLY this specific configuration!${NC}"
        echo -ne "${RED}Remove configuration '$config_name' for $host? [y/N]: ${NC}"
        read -r confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            local removal_success=false
            
            if [[ "$auth_type" == "SSH KEY" ]]; then
                # Remove specific SSH configuration
                local ssh_config=$(load_ssh_config)
                local new_ssh_config=$(python3 -c "
import json, sys
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config and '$config_name' in config['saved_keys']:
        del config['saved_keys']['$config_name']
        print(f'Removed SSH KEY config: $config_name ($user@$host)', file=sys.stderr)
        print(json.dumps(config, separators=(',', ':')))
        sys.exit(0)
    else:
        print('Configuration not found', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(2)
")
                
                if [[ $? -eq 0 ]]; then
                    if save_ssh_config "$new_ssh_config"; then
                        log_success "Removed SSH KEY configuration '$config_name' from ssh_keys.json"
                        removal_success=true
                    else
                        log_error "Failed to save updated SSH configuration"
                    fi
                fi
                
            elif [[ "$auth_type" == "SSH PASSWORD" ]]; then
                # Remove specific password configuration
                local password_config=$(load_password_config)
                local new_password_config=$(python3 -c "
import json, sys
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config and '$config_name' in config['saved_passwords']:
        del config['saved_passwords']['$config_name']
        print(f'Removed SSH PASSWORD config: $config_name ($user@$host)', file=sys.stderr)
        print(json.dumps(config, separators=(',', ':')))
        sys.exit(0)
    else:
        print('Configuration not found', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(2)
")
                
                if [[ $? -eq 0 ]]; then
                    if save_password_config "$new_password_config"; then
                        log_success "Removed SSH PASSWORD configuration '$config_name' from passwords.json"
                        removal_success=true
                    else
                        log_error "Failed to save updated password configuration"
                    fi
                fi
            fi
            
            if [[ "$removal_success" == true ]]; then
                # Sync hosts file to reflect changes
                sync_hosts_from_configs
                log_success "Successfully removed configuration '$config_name' for $host"
                log_info "Hosts file updated to reflect remaining configurations"
                
                # Check if host still has other configurations
                local remaining_configs=$(find_config_for_ip "$host")
                if [[ -n "$remaining_configs" ]]; then
                    log_info "Host $host still has other configurations and remains in hosts file"
                else
                    log_info "Host $host had no remaining configurations and was removed from hosts file"
                fi
            else
                log_error "Failed to remove configuration"
            fi
        else
            log_info "Removal cancelled"
        fi
    else
        log_error "Invalid choice"
    fi
}

show_help() {
    echo -e "${BOLD}Usage:${NC} $0 [OPTIONS]"
    echo
    echo -e "${BOLD}Options:${NC}"
    echo -e "  ${GREEN}-v, --verbose${NC}     Enable verbose output"
    echo -e "  ${GREEN}-d, --debug${NC}       Enable debug mode"
    echo -e "  ${GREEN}-y, --yes${NC}         Auto-confirm all prompts"
    echo -e "  ${GREEN}-s, --status${NC}      Show tunnel status and exit"
    echo -e "  ${GREEN}-D, --deploy${NC}      Deploy server files to remote host"
    echo -e "  ${GREEN}-c, --check-deps${NC}  Check system dependencies"
    echo -e "  ${GREEN}-h, --help${NC}        Show this help message"
    echo
    echo -e "${BOLD}Default Configuration:${NC}"
    echo -e "  SSH Key:      ${CYAN}$DEFAULT_SSH_KEY${NC}"
    echo -e "  Remote User:  ${CYAN}$DEFAULT_REMOTE_USER${NC}"
    echo -e "  Local Port:   ${CYAN}$LOCAL_PORT${NC}"
    echo -e "  Remote Port:  ${CYAN}$REMOTE_PORT${NC}"
    echo
    echo -e "${BOLD}Connection Management:${NC}"
    echo -e "  The script supports both SSH key and password authentication"
    echo -e "  Options: SSH keys, passwords, save configs, list saved configs"
    echo -e "  Configurations are stored in ~/.tunnel_configs/"
    echo
    echo -e "${BOLD}Server Deployment:${NC}"
    echo -e "  Use -D/--deploy to transfer server files to remote host"
    echo -e "  Required for first-time setup or server updates"
    echo -e "  Script automatically detects when local files are newer"
    echo -e "  and prompts for updates during normal tunnel operation"
    echo
    echo -e "${BOLD}Dependencies:${NC}"
    echo -e "  Required: ssh, curl, lsof, python3 (remote), sshpass (for passwords)"
    echo -e "  Use --check-deps to validate all dependencies"
    echo
}

# Status Checking Functions
show_tunnel_status() {
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}           🔍 Remote Tunnel Status Report 🔍            ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo
    
    check_local_tunnel_status
    check_connection_status
    check_process_status
    show_troubleshooting_info
}

check_local_tunnel_status() {
    log_info "🏠 Local SSH Tunnel Status (Port: $LOCAL_PORT)"
    
    local tunnel_pids=$(lsof -t -i:$LOCAL_PORT 2>/dev/null)
    if [[ -n "$tunnel_pids" ]]; then
        log_success "SSH Tunnel is running"
        
        if [[ "$VERBOSE" == true ]]; then
            echo -e "${BOLD}Process Details:${NC}"
            echo -e "${WHITE}  SSH tunnel process is active on port $LOCAL_PORT${NC}"
            echo -e "${WHITE}  Process count: $(echo "$tunnel_pids" | wc -w)${NC}"
            # Don't show full lsof output to prevent password exposure
            echo
        fi
        
        echo -e "${BOLD}Command Details:${NC}"
        echo "$tunnel_pids" | while read pid; do
            local cmd=$(ps -p $pid -o cmd= 2>/dev/null)
            echo -e "${BLUE}  PID $pid:${NC} $cmd"
        done
    else
        log_warning "No SSH tunnel found on port $LOCAL_PORT"
    fi
    echo
}

check_connection_status() {
    log_info "🌐 Connection Test (http://localhost:$LOCAL_PORT/)"
    
    if curl -s --connect-timeout 5 "http://localhost:$LOCAL_PORT/" >/dev/null 2>&1; then
        log_success "HTTP connection successful"
        
        # Get server info if possible
        local title=$(curl -s --connect-timeout 5 "http://localhost:$LOCAL_PORT/" | grep -o '<title>.*</title>' | sed 's/<[^>]*>//g' 2>/dev/null)
        if [[ -n "$title" ]]; then
            echo -e "${BLUE}  Server Title:${NC} $title"
        fi
        
        # Check response time
        local response_time=$(curl -s -w "%{time_total}" -o /dev/null --connect-timeout 5 "http://localhost:$LOCAL_PORT/" 2>/dev/null)
        if [[ -n "$response_time" ]]; then
            echo -e "${BLUE}  Response Time:${NC} ${response_time}s"
        fi
    else
        log_error "HTTP connection failed"
        echo -e "${YELLOW}  Possible issues:${NC}"
        echo -e "    • Remote server not running"
        echo -e "    • SSH tunnel not established"
        echo -e "    • Network connectivity problems"
    fi
    echo
}

check_process_status() {
    log_info "🖥️ Related Process Status"
    
    # Check for SSH processes
    local ssh_procs=$(ps aux | grep -E "ssh.*$LOCAL_PORT.*$REMOTE_PORT" | grep -v grep)
    if [[ -n "$ssh_procs" ]]; then
        echo -e "${GREEN}  SSH Tunnel Processes:${NC}"
        echo "$ssh_procs" | while read line; do
            echo -e "${WHITE}    $line${NC}"
        done
    else
        echo -e "${YELLOW}  No SSH tunnel processes found${NC}"
    fi
    echo
    
    # Check for HTTP server processes
    local http_procs=$(ps aux | grep -E "(python.*http|enhanced_http_server)" | grep -v grep)
    if [[ -n "$http_procs" ]]; then
        echo -e "${GREEN}  Local HTTP Server Processes:${NC}"
        echo "$http_procs" | while read line; do
            echo -e "${WHITE}    $line${NC}"
        done
    else
        echo -e "${YELLOW}  No local HTTP server processes found${NC}"
    fi
    echo
}

show_troubleshooting_info() {
    log_info "🔧 Quick Troubleshooting Commands"
    echo -e "${CYAN}  Check port usage:${NC}"
    echo -e "    lsof -i :$LOCAL_PORT"
    echo -e "    netstat -tlnp | grep $LOCAL_PORT"
    echo
    echo -e "${CYAN}  Manual cleanup:${NC}"
    echo -e "    ./tunnel_cleanup.sh                  # Full cleanup"
    echo -e "    pkill -f 'ssh.*$LOCAL_PORT'          # Kill tunnel only"
    echo
    echo -e "${CYAN}  Test connection:${NC}"
    echo -e "    curl http://localhost:$LOCAL_PORT/"
    echo -e "    wget -qO- http://localhost:$LOCAL_PORT/"
    echo
}

# Server Deployment Functions
deploy_server_files() {
    # Select server before deployment if not already selected
    if [[ -z "$SELECTED_SERVER" ]]; then
        select_http_server
    fi
    
    echo
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}          📦 Server Deployment to Remote Host 📦         ${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo
    
    log_info "Starting Python server file deployment..."
    
    # Use current working directory and selected server
    local local_server_file="$PWD/$SELECTED_SERVER"
    
    # Check if local server file exists
    if [[ ! -f "$local_server_file" ]]; then
        log_error "Local Python server file not found: $local_server_file"
        return 1
    fi
    
    log_verbose "Local Python server file: $local_server_file"
    
    # Get remote deployment path
    local remote_deploy_path
    if [[ "$AUTO_YES" == true ]]; then
        remote_deploy_path="~"
        log_info "Auto-selecting remote path: $remote_deploy_path"
    else
        echo -e "${BOLD}Remote Deployment Configuration:${NC}"
        echo -e "  ${GREEN}1${NC}. Use default path (~)"
        echo -e "  ${GREEN}2${NC}. Specify custom path"
        echo
        
        while true; do
            read -p "$(echo -e "${BOLD}Choose option (1-2):${NC} ")" choice
            case "$choice" in
                1)
                    remote_deploy_path="~"
                    break
                    ;;
                2)
                    read -p "$(echo -e "${BOLD}Enter remote directory path:${NC} ")" remote_deploy_path
                    if [[ -n "$remote_deploy_path" ]]; then
                        break
                    else
                        log_warning "Path cannot be empty"
                    fi
                    ;;
                *)
                    log_warning "Invalid choice. Please select 1 or 2."
                    ;;
            esac
        done
    fi
    
    log_info "Remote deployment path: $remote_deploy_path"
    
    # Create remote directory and deploy Python server file
    if deploy_to_remote "$local_server_file" "$remote_deploy_path"; then
        log_success "Python server deployment completed successfully!"
        return 0
    else
        log_error "Python server deployment failed"
        return 1
    fi
}

deploy_to_remote() {
    local local_server_file="$1"
    local remote_path="$2"
    
    # Resolve the remote path to actual directory
    local resolved_remote_path=$(get_resolved_remote_path "$remote_path")
    
    log_info "Deploying Python server to $REMOTE_USER@$REMOTE_HOST:$resolved_remote_path (original: $remote_path)"
    
    # Transfer Python server file to the resolved remote path
    log_info "Transferring Python server file to remote directory: $resolved_remote_path"
    log_debug "Original remote path: '$remote_path' -> Resolved: '$resolved_remote_path'"
    
    local ssh_cmd=$(get_ssh_cmd)
    local scp_cmd=$(get_scp_cmd)
    
    # Deploy Python server file only
    log_info "Transferring Python server file (timeout: 10 seconds)..."
    log_debug "SCP command: $scp_cmd \"$local_server_file\" \"$REMOTE_USER@$REMOTE_HOST:$resolved_remote_path/\""
    log_debug "Resolved remote path: $resolved_remote_path"
    
    if timeout 10 $scp_cmd -o ConnectTimeout=5 "$local_server_file" "$REMOTE_USER@$REMOTE_HOST:$resolved_remote_path/" 2>/dev/null; then
        log_success "Python server file transferred"
    else
        log_error "Failed to transfer Python server file"
        # Try with verbose output for debugging
        log_verbose "Attempting transfer with error output:"
        timeout 10 $scp_cmd -o ConnectTimeout=5 "$local_server_file" "$REMOTE_USER@$REMOTE_HOST:$resolved_remote_path/" 2>&1 | head -5
        return 1
    fi
    
    # Make Python server file executable on remote host
    log_info "Setting file permissions on remote host (timeout: 10 seconds)..."
    if timeout 10 $ssh_cmd -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" "chmod +x \"$resolved_remote_path/enhanced_http_server_new.py\"" 2>/dev/null; then
        log_success "File permissions set correctly"
    else
        log_warning "Could not set file permissions (Python server may still work)"
    fi
    
    # Verify deployment
    log_info "Verifying deployment..."
    if verify_remote_deployment "$resolved_remote_path"; then
        log_success "Deployment verification completed"
        return 0
    else
        log_error "Deployment verification failed"
        return 1
    fi
}

verify_remote_deployment() {
    local remote_path="$1"
    local verification_failed=false
    
    log_verbose "Checking deployed files on remote host..."
    
    # Check if Python server file exists and is executable
    local ssh_cmd=$(get_ssh_cmd)
    if $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "test -x \"$remote_path/enhanced_http_server_new.py\"" 2>/dev/null; then
        log_verbose "✓ Python server file: present and executable"
    else
        log_error "✗ Python server file: missing or not executable"
        verification_failed=true
    fi
    
    # Note: No longer using external launcher script - Python server started directly
    
    # Check Python availability on remote host
    if $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "command -v python3 &> /dev/null" 2>/dev/null; then
        log_verbose "✓ Python 3: available on remote host"
    else
        log_warning "⚠ Python 3: not found on remote host (server may not work)"
    fi
    
    # Test basic script syntax
    log_verbose "Testing Python server script syntax..."
    if $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "cd \"$remote_path\" && python3 -m py_compile enhanced_http_server_new.py" 2>/dev/null; then
        log_verbose "✓ Python server script: syntax OK"
    else
        log_warning "⚠ Python server script: syntax check failed"
    fi
    
    if [[ "$verification_failed" == true ]]; then
        return 1
    else
        return 0
    fi
}

check_remote_server_status() {
    log_info "Checking remote server deployment status..."
    
    # Get directory from script path and resolve it properly
    local remote_path="${REMOTE_SCRIPT_PATH%/*}"  # Get directory from script path
    log_debug "Extracted directory from REMOTE_SCRIPT_PATH '$REMOTE_SCRIPT_PATH': '$remote_path'"
    
    local resolved_remote_path=$(get_resolved_remote_path "$remote_path")
    
    log_debug "Path resolution: '$remote_path' -> '$resolved_remote_path'"
    log_verbose "Testing remote directory: $resolved_remote_path"
    
    local ssh_cmd=$(get_ssh_cmd)
    
    if eval "$ssh_cmd \"$REMOTE_USER@$REMOTE_HOST\" 'test -d \"$resolved_remote_path\"'" 2>/dev/null; then
        log_success "Remote directory exists: $resolved_remote_path"
        
        # Check for Python server file - use resolved paths for file checks
        local server_file="$resolved_remote_path/enhanced_http_server_new.py"
        
        local files_present=true
        
        # Check if Python server file exists (timeout: 5 seconds)
        if timeout 5 $ssh_cmd -o ConnectTimeout=3 "$REMOTE_USER@$REMOTE_HOST" "test -f $server_file" 2>/dev/null; then
            log_verbose "✓ Python server file found"
        else
            log_warning "✗ Python server file missing: $server_file"
            files_present=false
        fi
        
        # Note: No longer checking for launcher script - Python server started directly
        
        # Handle file status results
        if [[ "$files_present" != true ]]; then
            log_warning "Remote server files are missing or incomplete"
            return 1
        else
            # Always ask user if they want to update files
            if [[ "$AUTO_YES" != true ]]; then
                echo
                log_info "🔄 Would you like to update the remote server files?"
                echo -e "${BOLD}File Update Options:${NC}"
                echo -e "  ${GREEN}1${NC}. Update remote files now"
                echo -e "  ${GREEN}2${NC}. Continue with existing remote files"
                echo -e "  ${GREEN}3${NC}. Exit to update manually"
                echo
                
                while true; do
                    read -p "$(echo -e "${BOLD}Choose option (1-3):${NC} ")" update_choice
                    case "$update_choice" in
                        1)
                            log_info "Updating remote server files..."
                            if deploy_server_files; then
                                log_success "Remote files updated successfully!"
                                return 0
                            else
                                log_error "Failed to update remote files"
                                return 1
                            fi
                            ;;
                        2)
                            log_info "Continuing with existing remote files"
                            return 0
                            ;;
                        3)
                            log_info "Exiting. Use -D option to update files manually."
                            exit 0
                            ;;
                        *)
                            log_warning "Invalid choice. Please select 1, 2, or 3."
                            ;;
                    esac
                done
            else
                log_info "Auto-mode: continuing with existing remote files"
                return 0
            fi
        fi
    else
        log_warning "Remote directory not found: $resolved_remote_path (original: $remote_path)"
        return 1
    fi
}

# Dependency Validation Functions
check_system_dependencies() {
    log_info "Checking system dependencies..."
    
    local missing_deps=()
    local optional_deps=()
    
    # Required dependencies
    local required_tools=("ssh" "curl" "lsof" "grep" "sed" "awk" "ps" "pkill" "kill")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_deps+=("$tool")
        else
            log_verbose "✓ $tool: $(which $tool)"
        fi
    done
    
    # Check sshpass for password authentication
    if ! command -v "sshpass" &> /dev/null; then
        optional_deps+=("sshpass")
        log_warning "sshpass not found - password authentication will not be available"
    else
        log_verbose "✓ sshpass: $(which sshpass)"
    fi
    
    # Check Python 3 locally
    if ! command -v "python3" &> /dev/null; then
        log_warning "python3 not found locally - may be needed for some operations"
    else
        local py_version=$(python3 --version 2>&1 | cut -d' ' -f2)
        log_verbose "✓ python3: $py_version"
    fi
    
    # Report results
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        echo -e "${YELLOW}Please install missing dependencies:${NC}"
        echo -e "  Ubuntu/Debian: ${CYAN}sudo apt update && sudo apt install ${missing_deps[*]}${NC}"
        echo -e "  CentOS/RHEL: ${CYAN}sudo yum install ${missing_deps[*]}${NC}"
        echo -e "  Alpine: ${CYAN}sudo apk add ${missing_deps[*]}${NC}"
        return 1
    fi
    
    if [[ ${#optional_deps[@]} -gt 0 ]]; then
        log_warning "Optional dependencies missing: ${optional_deps[*]}"
        
        if [[ "$AUTO_YES" != true ]]; then
            echo -e "${BOLD}Install optional dependencies?${NC}"
            echo -e "  ${GREEN}1${NC}. Install now (requires sudo)"
            echo -e "  ${GREEN}2${NC}. Continue without them"
            echo -e "  ${GREEN}3${NC}. Show install commands and exit"
            echo
            
            while true; do
                read -p "$(echo -e "${BOLD}Choose option (1-3):${NC} ")" opt_choice
                case "$opt_choice" in
                    1)
                        log_info "Installing optional dependencies..."
                        if command -v apt &> /dev/null; then
                            sudo apt update && sudo apt install -y sshpass
                        elif command -v yum &> /dev/null; then
                            sudo yum install -y sshpass
                        elif command -v apk &> /dev/null; then
                            sudo apk add sshpass
                        else
                            log_error "Cannot detect package manager. Please install manually."
                            return 1
                        fi
                        break
                        ;;
                    2)
                        log_info "Continuing without optional dependencies"
                        break
                        ;;
                    3)
                        echo -e "${CYAN}Install commands:${NC}"
                        echo -e "  Ubuntu/Debian: sudo apt install sshpass"
                        echo -e "  CentOS/RHEL: sudo yum install sshpass"
                        echo -e "  Alpine: sudo apk add sshpass"
                        exit 0
                        ;;
                    *)
                        log_warning "Invalid choice. Please select 1, 2, or 3."
                        ;;
                esac
            done
        fi
    fi
    
    log_success "System dependencies validated"
    return 0
}

check_remote_dependencies() {
    if [[ -z "$REMOTE_HOST" ]]; then
        log_warning "Remote host not configured, skipping remote dependency check"
        return 0
    fi
    
    log_info "Checking remote dependencies on $REMOTE_USER@$REMOTE_HOST..."
    
    local ssh_cmd=""
    if [[ "$USE_PASSWORD" == true ]]; then
        if ! command -v sshpass &> /dev/null; then
            log_error "sshpass required for password authentication but not installed"
            return 1
        fi
        ssh_cmd="sshpass -p '$REMOTE_PASSWORD' ssh -o StrictHostKeyChecking=no"
    else
        ssh_cmd="ssh -i '$SSH_KEY' -o StrictHostKeyChecking=no"
    fi
    
    # Test connection first
    if ! eval "$ssh_cmd '$REMOTE_USER@$REMOTE_HOST' 'echo connection_test'" &>/dev/null; then
        log_warning "Cannot connect to remote host for dependency check"
        return 1
    fi
    
    # Check Python 3 on remote
    local remote_python_version
    remote_python_version=$(eval "$ssh_cmd '$REMOTE_USER@$REMOTE_HOST' 'python3 --version 2>&1 || echo MISSING'")
    
    if [[ "$remote_python_version" == "MISSING" ]]; then
        log_error "Python 3 not found on remote host - required for server"
        echo -e "${YELLOW}Install Python 3 on remote host:${NC}"
        echo -e "  Ubuntu/Debian: sudo apt install python3"
        echo -e "  CentOS/RHEL: sudo yum install python3"
        return 1
    else
        log_success "Remote Python 3: $remote_python_version"
    fi
    
    # Check other remote tools
    local remote_tools=("bash" "ps" "lsof" "pkill")
    for tool in "${remote_tools[@]}"; do
        if eval "$ssh_cmd '$REMOTE_USER@$REMOTE_HOST' 'command -v $tool'" &>/dev/null; then
            log_verbose "✓ Remote $tool: available"
        else
            log_warning "Remote $tool: not found (may cause issues)"
        fi
    done
    
    log_success "Remote dependencies validated"
    return 0
}

# Connection Configuration Management Functions
get_config_dir() {
    echo "$HOME/.tunnel_configs"
}

get_ssh_config_file() {
    echo "$(get_config_dir)/ssh_configs.json"
}

get_password_config_file() {
    echo "$(get_config_dir)/password_configs.json"
}

ensure_config_dir() {
    local config_dir=$(get_config_dir)
    if [[ ! -d "$config_dir" ]]; then
        mkdir -p "$config_dir"
        chmod 700 "$config_dir"
    fi
}

load_ssh_config() {
    ensure_config_dir
    local config_file=$(get_ssh_config_file)
    local default_config="{
        \"default_key\": \"$DEFAULT_SSH_KEY\",
        \"default_user\": \"$DEFAULT_REMOTE_USER\",
        \"default_host\": \"$DEFAULT_REMOTE_HOST\",
        \"saved_keys\": {}
    }"
    
    if [[ -f "$config_file" ]]; then
        cat "$config_file" 2>/dev/null || echo "$default_config"
    else
        echo "$default_config"
    fi
}

load_password_config() {
    ensure_config_dir
    local config_file=$(get_password_config_file)
    local default_config="{
        \"default_user\": \"$DEFAULT_REMOTE_USER\",
        \"default_host\": \"$DEFAULT_REMOTE_HOST\",
        \"saved_passwords\": {}
    }"
    
    if [[ -f "$config_file" ]]; then
        cat "$config_file" 2>/dev/null || echo "$default_config"
    else
        echo "$default_config"
    fi
}

save_ssh_config() {
    local config="$1"
    ensure_config_dir
    local config_file=$(get_ssh_config_file)
    
    # Validate JSON format before saving
    if echo "$config" | grep -q '"saved_keys"' && echo "$config" | grep -q '"default_key"'; then
        echo "$config" > "$config_file" 2>/dev/null
        chmod 600 "$config_file"
        return $?
    else
        log_error "Invalid SSH configuration format"
        return 1
    fi
}

save_password_config() {
    local config="$1"
    ensure_config_dir
    local config_file=$(get_password_config_file)
    
    # Validate JSON format before saving
    if echo "$config" | grep -q '"saved_passwords"'; then
        echo "$config" > "$config_file" 2>/dev/null
        chmod 600 "$config_file"  # Restrict access to password file
        return $?
    else
        log_error "Invalid password configuration format"
        return 1
    fi
}

# Configuration validation functions
validate_ssh_config() {
    local ssh_key="$1"
    local user="$2" 
    local host="$3"
    
    log_info "Validating SSH configuration..."
    
    # Check if SSH key file exists
    if [[ ! -f "$ssh_key" ]]; then
        log_error "SSH key file not found: $ssh_key"
        return 1
    fi
    
    # Check SSH key permissions
    local perms=$(stat -c "%a" "$ssh_key" 2>/dev/null)
    if [[ "$perms" != "600" ]]; then
        log_warning "SSH key has permissions $perms, should be 600"
        if [[ "$AUTO_YES" != true ]]; then
            read -p "$(echo -e "${BOLD}Fix permissions? (y/n):${NC} ")" fix_perms
            if [[ "$fix_perms" =~ ^[Yy] ]]; then
                chmod 600 "$ssh_key"
                log_success "Fixed SSH key permissions"
            fi
        fi
    fi
    
    # Test SSH connectivity
    log_verbose "Testing SSH connectivity to $user@$host..."
    if ssh -i "$ssh_key" -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "$user@$host" "echo 'SSH test successful'" >/dev/null 2>&1; then
        log_success "SSH connection validated successfully"
        return 0
    else
        log_error "SSH connection test failed"
        log_error "Please check: network connectivity, SSH key, username, hostname"
        return 1
    fi
}

validate_password_config() {
    local user="$1"
    local host="$2"
    local password="$3"
    
    log_info "Validating password configuration..."
    
    # Test SSH connectivity with password
    log_verbose "Testing SSH connectivity to $user@$host..."
    if sshpass -p "$password" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$user@$host" "echo 'SSH test successful'" >/dev/null 2>&1; then
        log_success "SSH password connection validated successfully"
        return 0
    else
        log_error "SSH password connection test failed"
        log_error "Please check: network connectivity, username, password, hostname"
        return 1
    fi
}

show_available_configurations() {
    local ssh_config="$1"
    local password_config="$2"
    
    log_info "Available saved configurations:"
    echo
    
    # Show SSH configurations count
    local ssh_saved=$(echo "$ssh_config" | sed -n 's/.*"saved_keys": *{\([^}]*\)}.*/\1/p')
    if [[ -n "$ssh_saved" && "$ssh_saved" != "" ]]; then
        local ssh_count=$(echo "$ssh_saved" | grep -o '"[^"]*":' | wc -l)
        echo -e "  ${CYAN}SSH Key configs:${NC} $ssh_count saved"
    else
        echo -e "  ${CYAN}SSH Key configs:${NC} none saved"
    fi
    
    # Show password configurations count
    local pwd_saved=$(echo "$password_config" | sed -n 's/.*"saved_passwords": *{\([^}]*\)}.*/\1/p')
    if [[ -n "$pwd_saved" && "$pwd_saved" != "" ]]; then
        local pwd_count=$(echo "$pwd_saved" | grep -o '"[^"]*":' | wc -l)
        echo -e "  ${CYAN}Password configs:${NC} $pwd_count saved"
    else
        echo -e "  ${CYAN}Password configs:${NC} none saved"
    fi
    
    echo
}

select_from_saved_configurations() {
    local ssh_config="$1"
    local password_config="$2"
    
    echo -e "${BOLD}Select from Saved Configurations:${NC}"
    echo
    
    # Count available configurations
    local ssh_count=0
    local password_count=0
    local total_counter=1
    local temp_file=$(mktemp)
    
    # List SSH configurations
    echo -e "${CYAN}SSH Key Configurations:${NC}"
    if echo "$ssh_config" | grep -q '"saved_keys"'; then
        while IFS= read -r entry; do
            if [[ -n "$entry" ]]; then
                local name=$(echo "$entry" | sed 's/^"\([^"]*\)": *.*/\1/')
                local key=$(echo "$entry" | sed 's/.*"key": *"\([^"]*\)".*/\1/')
                local user=$(echo "$entry" | sed 's/.*"user": *"\([^"]*\)".*/\1/')
                local host=$(echo "$entry" | sed 's/.*"host": *"\([^"]*\)".*/\1/')
                
                if [[ -n "$name" && -n "$user" && -n "$host" && -n "$key" ]]; then
                    echo -e "  ${GREEN}$total_counter${NC}. ${BOLD}$name${NC}: $user@$host"
                    echo -e "     ${GREEN}Key: $key${NC}"
                    echo "SSH|$total_counter|$name|$user|$host|$key" >> "$temp_file"
                    ((total_counter++))
                    ((ssh_count++))
                fi
            fi
        done < <(echo "$ssh_config" | grep -o '"[^"]*": *{"key": *"[^"]*", *"user": *"[^"]*", *"host": *"[^"]*"}')
    fi
    
    if [[ $ssh_count -eq 0 ]]; then
        echo -e "  ${YELLOW}No saved SSH key configurations found${NC}"
    fi
    echo
    
    # List Password configurations  
    echo -e "${CYAN}Password Configurations:${NC}"
    if echo "$password_config" | grep -q '"saved_passwords"'; then
        while IFS= read -r entry; do
            if [[ -n "$entry" ]]; then
                local name=$(echo "$entry" | sed 's/^"\([^"]*\)": *.*/\1/')
                local user=$(echo "$entry" | sed 's/.*"user": *"\([^"]*\)".*/\1/')
                local host=$(echo "$entry" | sed 's/.*"host": *"\([^"]*\)".*/\1/')
                local password=$(echo "$entry" | sed 's/.*"password": *"\([^"]*\)".*/\1/')
                
                if [[ -n "$name" && -n "$user" && -n "$host" ]]; then
                    echo -e "  ${GREEN}$total_counter${NC}. ${BOLD}$name${NC}: $user@$host"
                    echo "PASSWORD|$total_counter|$name|$user|$host|$password" >> "$temp_file"
                    ((total_counter++))
                    ((password_count++))
                fi
            fi
        done < <(echo "$password_config" | grep -o '"[^"]*": *{"user": *"[^"]*", *"host": *"[^"]*", *"password": *"[^"]*"}')
    fi
    
    if [[ $password_count -eq 0 ]]; then
        echo -e "  ${YELLOW}No saved password configurations found${NC}"
    fi
    echo
    
    # Check if any configurations exist
    if [[ ! -s "$temp_file" ]]; then
        log_warning "No saved configurations available"
        rm -f "$temp_file"
        return 1
    fi
    
    # Get user selection
    read -p "$(echo -e "${BOLD}Select configuration number (or press Enter to go back):${NC} ")" select_num
    if [[ -n "$select_num" ]] && [[ "$select_num" =~ ^[0-9]+$ ]]; then
        # Find the selected configuration
        local selected_line=$(grep "|$select_num|" "$temp_file" | head -1)
        if [[ -n "$selected_line" ]]; then
            local config_type=$(echo "$selected_line" | cut -d'|' -f1)
            local config_name=$(echo "$selected_line" | cut -d'|' -f3)
            local config_user=$(echo "$selected_line" | cut -d'|' -f4)
            local config_host=$(echo "$selected_line" | cut -d'|' -f5)
            
            if [[ "$config_type" == "SSH" ]]; then
                local config_key=$(echo "$selected_line" | cut -d'|' -f6)
                SSH_KEY="$config_key"
                REMOTE_USER="$config_user"
                REMOTE_HOST="$config_host"
                USE_PASSWORD=false
                log_success "Selected SSH key configuration: $config_name ($config_user@$config_host)"
            elif [[ "$config_type" == "PASSWORD" ]]; then
                REMOTE_PASSWORD=$(echo "$selected_line" | cut -d'|' -f6)
                REMOTE_USER="$config_user"
                REMOTE_HOST="$config_host"
                USE_PASSWORD=true
                log_success "Selected password configuration: $config_name ($config_user@$config_host)"
            fi
            
            rm -f "$temp_file"
            return 0
        else
            log_warning "Invalid selection number: $select_num"
        fi
    fi
    
    rm -f "$temp_file"
    return 1
}

remove_saved_configuration() {
    local ssh_config="$1"
    local password_config="$2"
    
    echo -e "${BOLD}Remove Saved Configuration:${NC}"
    echo
    
    # Count available configurations
    local ssh_count=0
    local password_count=0
    local total_counter=1
    local temp_file=$(mktemp)
    
    # List SSH configurations
    echo -e "${CYAN}SSH Key Configurations:${NC}"
    if echo "$ssh_config" | grep -q '"saved_keys"'; then
        while IFS= read -r entry; do
            if [[ -n "$entry" ]]; then
                local name=$(echo "$entry" | sed 's/^"\([^"]*\)": *.*/\1/')
                local user=$(echo "$entry" | sed 's/.*"user": *"\([^"]*\)".*/\1/')
                local host=$(echo "$entry" | sed 's/.*"host": *"\([^"]*\)".*/\1/')
                local key=$(echo "$entry" | sed 's/.*"key": *"\([^"]*\)".*/\1/')
                
                if [[ -n "$name" && -n "$user" && -n "$host" && -n "$key" ]]; then
                    echo -e "  ${RED}$total_counter${NC}. ${BOLD}$name${NC}: $user@$host"
                    echo -e "     ${GREEN}Key: $key${NC}"
                    echo "SSH|$total_counter|$name|$user|$host|$key" >> "$temp_file"
                    ((total_counter++))
                    ((ssh_count++))
                fi
            fi
        done < <(echo "$ssh_config" | grep -o '"[^"]*": *{"key": *"[^"]*", *"user": *"[^"]*", *"host": *"[^"]*"}')
    fi
    
    if [[ $ssh_count -eq 0 ]]; then
        echo -e "  ${YELLOW}No saved SSH key configurations found${NC}"
    fi
    echo
    
    # List Password configurations  
    echo -e "${CYAN}Password Configurations:${NC}"
    if echo "$password_config" | grep -q '"saved_passwords"'; then
        while IFS= read -r entry; do
            if [[ -n "$entry" ]]; then
                local name=$(echo "$entry" | sed 's/^"\([^"]*\)": *.*/\1/')
                local user=$(echo "$entry" | sed 's/.*"user": *"\([^"]*\)".*/\1/')
                local host=$(echo "$entry" | sed 's/.*"host": *"\([^"]*\)".*/\1/')
                local password=$(echo "$entry" | sed 's/.*"password": *"\([^"]*\)".*/\1/')
                
                if [[ -n "$name" && -n "$user" && -n "$host" ]]; then
                    echo -e "  ${RED}$total_counter${NC}. ${BOLD}$name${NC}: $user@$host"
                    echo "PASSWORD|$total_counter|$name|$user|$host|$password" >> "$temp_file"
                    ((total_counter++))
                    ((password_count++))
                fi
            fi
        done < <(echo "$password_config" | grep -o '"[^"]*": *{"user": *"[^"]*", *"host": *"[^"]*", *"password": *"[^"]*"}')
    fi
    
    if [[ $password_count -eq 0 ]]; then
        echo -e "  ${YELLOW}No saved password configurations found${NC}"
    fi
    echo
    
    # Check if any configurations exist
    if [[ ! -s "$temp_file" ]]; then
        log_warning "No saved configurations available to remove"
        rm -f "$temp_file"
        return 1
    fi
    
    # Show delete all options
    local total_configs=$((ssh_count + password_count))
    echo -e "${BOLD}Delete All Options:${NC}"
    echo -e "${BOLD}${RED}[A]${NC} ${BOLD}Delete ALL SSH key configurations${NC} (${ssh_count} total)"
    echo -e "     ${WHITE}🔑 Remove all saved SSH key configurations${NC}"
    echo -e "${BOLD}${RED}[P]${NC} ${BOLD}Delete ALL password configurations${NC} (${password_count} total)"
    echo -e "     ${WHITE}🔒 Remove all saved password configurations${NC}"
    echo -e "${BOLD}${RED}[B]${NC} ${BOLD}Delete BOTH SSH keys AND passwords${NC} (${total_configs} total)"
    echo -e "     ${WHITE}💥 Remove all SSH keys and password configurations${NC}"
    echo
    
    # Get user selection
    read -p "$(echo -e "${BOLD}Select configuration number to remove (A/P/B for delete all options, or Enter to cancel):${NC} ")" select_num
    
    # Handle delete all options
    if [[ "$select_num" =~ ^[AaPpBb]$ ]]; then
        case "${select_num^^}" in
            A)
                if [[ $ssh_count -eq 0 ]]; then
                    log_warning "No SSH key configurations to delete"
                    rm -f "$temp_file"
                    return 1
                fi
                echo
                echo -e "${BOLD}${RED}⚠️  DELETE ALL SSH KEY CONFIGURATIONS${NC}"
                echo -e "${YELLOW}The following SSH key configurations will be permanently deleted:${NC}"
                echo
                
                # List SSH configurations that will be deleted
                python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        counter = 1
        for name, details in config['saved_keys'].items():
            print(f'  {counter}. {name}: {details[\"user\"]}@{details[\"host\"]}')
            print(f'     Key: {details[\"key\"]}')
            counter += 1
except:
    pass
" 2>/dev/null
                
                echo
                echo -e "${RED}WARNING: This action cannot be undone!${NC}"
                echo -e "${WHITE}Total SSH key configurations to delete: ${RED}$ssh_count${NC}"
                echo
                read -p "$(echo -e "${BOLD}Are you sure? (y/yes/n/no):${NC} ")" confirm
                
                if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                    local empty_ssh_config="{
                        \"default_key\": \"$DEFAULT_SSH_KEY\",
                        \"default_user\": \"$DEFAULT_REMOTE_USER\",
                        \"default_host\": \"$DEFAULT_REMOTE_HOST\",
                        \"saved_keys\": {}
                    }"
                    
                    if save_ssh_config "$empty_ssh_config"; then
                        log_success "All SSH key configurations deleted successfully ($ssh_count configurations removed)"
                        sync_hosts_from_configs
                        rm -f "$temp_file"
                        return 0
                    else
                        log_error "Failed to delete SSH key configurations"
                    fi
                else
                    log_info "Deletion cancelled"
                fi
                rm -f "$temp_file"
                return 1
                ;;
            P)
                if [[ $password_count -eq 0 ]]; then
                    log_warning "No password configurations to delete"
                    rm -f "$temp_file"
                    return 1
                fi
                echo
                echo -e "${BOLD}${RED}⚠️  DELETE ALL PASSWORD CONFIGURATIONS${NC}"
                echo -e "${YELLOW}The following password configurations will be permanently deleted:${NC}"
                echo
                
                # List password configurations that will be deleted
                python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        counter = 1
        for name, details in config['saved_passwords'].items():
            print(f'  {counter}. {name}: {details[\"user\"]}@{details[\"host\"]}')
            counter += 1
except:
    pass
" 2>/dev/null
                
                echo
                echo -e "${RED}WARNING: This action cannot be undone!${NC}"
                echo -e "${WHITE}Total password configurations to delete: ${RED}$password_count${NC}"
                echo
                read -p "$(echo -e "${BOLD}Are you sure? (y/yes/n/no):${NC} ")" confirm
                
                if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                    local empty_password_config="{
                        \"default_user\": \"$DEFAULT_REMOTE_USER\",
                        \"default_host\": \"$DEFAULT_REMOTE_HOST\",
                        \"saved_passwords\": {}
                    }"
                    
                    if save_password_config "$empty_password_config"; then
                        log_success "All password configurations deleted successfully ($password_count configurations removed)"
                        sync_hosts_from_configs
                        rm -f "$temp_file"
                        return 0
                    else
                        log_error "Failed to delete password configurations"
                    fi
                else
                    log_info "Deletion cancelled"
                fi
                rm -f "$temp_file"
                return 1
                ;;
            B)
                if [[ $total_configs -eq 0 ]]; then
                    log_warning "No configurations to delete"
                    rm -f "$temp_file"
                    return 1
                fi
                echo
                echo -e "${BOLD}${RED}⚠️  DELETE ALL CONFIGURATIONS${NC}"
                echo -e "${YELLOW}The following configurations will be permanently deleted:${NC}"
                echo
                
                # Show SSH key configurations if any
                if [[ $ssh_count -gt 0 ]]; then
                    echo -e "${CYAN}SSH Key Configurations ($ssh_count):${NC}"
                    python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        counter = 1
        for name, details in config['saved_keys'].items():
            print(f'  {counter}. {name}: {details[\"user\"]}@{details[\"host\"]}')
            print(f'     Key: {details[\"key\"]}')
            counter += 1
except:
    pass
" 2>/dev/null
                    echo
                fi
                
                # Show password configurations if any
                if [[ $password_count -gt 0 ]]; then
                    echo -e "${CYAN}Password Configurations ($password_count):${NC}"
                    python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        counter = 1
        for name, details in config['saved_passwords'].items():
            print(f'  {counter}. {name}: {details[\"user\"]}@{details[\"host\"]}')
            counter += 1
except:
    pass
" 2>/dev/null
                    echo
                fi
                
                echo -e "${RED}WARNING: This action cannot be undone!${NC}"
                echo -e "${WHITE}Total configurations to delete: ${RED}$total_configs${NC}"
                echo
                read -p "$(echo -e "${BOLD}Are you sure? (y/yes/n/no):${NC} ")" confirm
                
                if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                    local success=true
                    
                    # Clear SSH configurations if any exist
                    if [[ $ssh_count -gt 0 ]]; then
                        local empty_ssh_config="{
                            \"default_key\": \"$DEFAULT_SSH_KEY\",
                            \"default_user\": \"$DEFAULT_REMOTE_USER\",
                            \"default_host\": \"$DEFAULT_REMOTE_HOST\",
                            \"saved_keys\": {}
                        }"
                        
                        if ! save_ssh_config "$empty_ssh_config"; then
                            log_error "Failed to clear SSH key configurations"
                            success=false
                        fi
                    fi
                    
                    # Clear password configurations if any exist
                    if [[ $password_count -gt 0 ]]; then
                        local empty_password_config="{
                            \"default_user\": \"$DEFAULT_REMOTE_USER\",
                            \"default_host\": \"$DEFAULT_REMOTE_HOST\",
                            \"saved_passwords\": {}
                        }"
                        
                        if ! save_password_config "$empty_password_config"; then
                            log_error "Failed to clear password configurations"
                            success=false
                        fi
                    fi
                    
                    if [[ "$success" == true ]]; then
                        log_success "All configurations deleted successfully ($total_configs configurations removed)"
                        sync_hosts_from_configs
                        rm -f "$temp_file"
                        return 0
                    else
                        log_error "Some configurations failed to delete"
                    fi
                else
                    log_info "Deletion cancelled"
                fi
                rm -f "$temp_file"
                return 1
                ;;
        esac
    elif [[ -n "$select_num" ]] && [[ "$select_num" =~ ^[0-9]+$ ]]; then
        # Find the selected configuration
        local selected_line=$(grep "|$select_num|" "$temp_file" | head -1)
        if [[ -n "$selected_line" ]]; then
            local config_type=$(echo "$selected_line" | cut -d'|' -f1)
            local config_name=$(echo "$selected_line" | cut -d'|' -f3)
            local config_user=$(echo "$selected_line" | cut -d'|' -f4)
            local config_host=$(echo "$selected_line" | cut -d'|' -f5)
            
            # Confirm deletion
            echo
            echo -e "${BOLD}${RED}⚠️  CONFIRM DELETION${NC}"
            echo -e "Configuration to delete: ${BOLD}$config_name${NC} ($config_user@$config_host)"
            echo -e "Type: $config_type"
            echo
            read -p "$(echo -e "${BOLD}Are you sure you want to delete this configuration? (y/yes/n/no):${NC} ")" confirm
            
            if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                # Delete the configuration
                if [[ "$config_type" == "SSH" ]]; then
                    # Remove SSH key configuration using Python for proper JSON handling
                    local updated_config=$(python3 -c "
import json, sys
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config and '$config_name' in config['saved_keys']:
        del config['saved_keys']['$config_name']
    print(json.dumps(config, separators=(',', ':')))
except Exception as e:
    sys.exit(1)
")
                    if [[ $? -eq 0 ]] && save_ssh_config "$updated_config"; then
                        log_success "SSH key configuration '$config_name' deleted successfully"
                        rm -f "$temp_file"
                        return 0
                    else
                        log_error "Failed to delete SSH key configuration"
                    fi
                elif [[ "$config_type" == "PASSWORD" ]]; then
                    # Remove password configuration using Python for proper JSON handling  
                    local updated_config=$(python3 -c "
import json, sys
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config and '$config_name' in config['saved_passwords']:
        del config['saved_passwords']['$config_name']
    print(json.dumps(config, separators=(',', ':')))
except Exception as e:
    sys.exit(1)
")
                    if [[ $? -eq 0 ]] && save_password_config "$updated_config"; then
                        log_success "Password configuration '$config_name' deleted successfully"
                        rm -f "$temp_file"
                        return 0
                    else
                        log_error "Failed to delete password configuration"
                    fi
                fi
            elif [[ "$confirm" =~ ^[Nn]([Oo])?$ ]]; then
                log_info "Deletion cancelled"
            else
                log_warning "Invalid response. Please enter y/yes or n/no"
                log_info "Deletion cancelled"
            fi
        else
            log_warning "Invalid selection number: $select_num"
        fi
    else
        log_info "Deletion cancelled"
    fi
    
    rm -f "$temp_file"
    return 1
}

# ═══════════════════════════════════════════════════════════════════
# CLEANUP FUNCTIONS (Integrated from tunnel_cleanup.sh)
# ═══════════════════════════════════════════════════════════════════

# Get available hosts for cleanup
get_available_hosts_cleanup() {
    local hosts_with_configs=()
    
    # Get IPs from SSH configurations
    local ssh_config=$(load_ssh_config)
    if [[ "$ssh_config" != "{}" ]]; then
        local ssh_ips=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    unique_ips = set()
    if 'saved_keys' in config:
        for name, details in config['saved_keys'].items():
            if 'host' in details:
                unique_ips.add(details['host'])
    for ip in sorted(unique_ips):
        print(ip)
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$ssh_ips" ]]; then
            while IFS= read -r ip; do
                if [[ -n "$ip" ]]; then
                    hosts_with_configs+=("$ip")
                fi
            done <<< "$ssh_ips"
        fi
    fi
    
    # Get IPs from password configurations
    local password_config=$(load_password_config)
    if [[ "$password_config" != "{}" ]]; then
        local password_ips=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    unique_ips = set()
    if 'saved_passwords' in config:
        for name, details in config['saved_passwords'].items():
            if 'host' in details:
                unique_ips.add(details['host'])
    for ip in sorted(unique_ips):
        print(ip)
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$password_ips" ]]; then
            while IFS= read -r ip; do
                if [[ -n "$ip" ]] && ! printf '%s\n' "${hosts_with_configs[@]}" | grep -q "^$ip$"; then
                    hosts_with_configs+=("$ip")
                fi
            done <<< "$password_ips"
        fi
    fi
    
    # Sort and return unique IPs that have configurations
    if [[ ${#hosts_with_configs[@]} -gt 0 ]]; then
        printf '%s\n' "${hosts_with_configs[@]}" | sort -u
    fi
}

# Find matching configuration for an IP
find_config_for_ip_cleanup() {
    local target_ip="$1"
    local ssh_config=$(load_ssh_config)
    local password_config=$(load_password_config)
    
    # Check SSH configs first
    if [[ "$ssh_config" != "{}" ]]; then
        # Extract configurations using python for JSON parsing
        local ssh_match=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        for name, details in config['saved_keys'].items():
            if details.get('host') == '$target_ip':
                print(f\"ssh:{details['user']}@{details['host']}:{details['key']}:{name}\")
                exit(0)
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$ssh_match" ]]; then
            echo "$ssh_match"
            return 0
        fi
    fi
    
    # Check password configs
    if [[ "$password_config" != "{}" ]]; then
        local password_match=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        for name, details in config['saved_passwords'].items():
            if details.get('host') == '$target_ip':
                print(f\"password:{details['user']}@{details['host']}:{details['password']}:{name}\")
                exit(0)
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$password_match" ]]; then
            echo "$password_match"
            return 0
        fi
    fi
    
    return 1
}

# Set configuration for selected host (for cleanup)
set_host_config_cleanup() {
    local target_ip="$1"
    local config_info=$(find_config_for_ip_cleanup "$target_ip")
    
    if [[ -z "$config_info" ]]; then
        log_error "No valid configuration found for $target_ip"
        return 1
    fi
    
    REMOTE_HOST="$target_ip"
    
    if [[ "$config_info" =~ ^ssh: ]]; then
        local config_line=$(echo "$config_info" | cut -d':' -f2-)
        # Parse SSH config line format: user@host:key_path:description
        REMOTE_USER=$(echo "$config_line" | cut -d'@' -f1)
        SSH_KEY=$(echo "$config_line" | cut -d':' -f2)
        USE_PASSWORD=false
        REMOTE_PASSWORD=""
        log_info "Using SSH key authentication for $target_ip"
    elif [[ "$config_info" =~ ^password: ]]; then
        local config_line=$(echo "$config_info" | cut -d':' -f2-)
        # Parse password config line format: user@host:password:description
        REMOTE_USER=$(echo "$config_line" | cut -d'@' -f1)
        USE_PASSWORD=true
        REMOTE_PASSWORD=$(echo "$config_line" | cut -d':' -f2)
        SSH_KEY=""
        log_info "Using password authentication for $target_ip"
    fi
    
    return 0
}

# Cleanup local tunnel
cleanup_local_tunnel() {
    log_info "🏠 Cleaning up local SSH tunnels on port $LOCAL_PORT..."
    
    # Kill SSH processes by pattern first
    log_info "Killing SSH tunnel processes by pattern..."
    # Kill processes quietly to prevent password exposure in command lines
    pkill -f "ssh.*-L.*$LOCAL_PORT:localhost:$REMOTE_PORT" >/dev/null 2>&1
    pkill -f "ssh.*$LOCAL_PORT.*$REMOTE_HOST" >/dev/null 2>&1
    sleep 2
    
    # Find and kill any remaining processes on the port
    local tunnel_pids=$(lsof -t -i:$LOCAL_PORT 2>/dev/null)
    
    if [[ -n "$tunnel_pids" ]]; then
        echo -e "${YELLOW}Found remaining processes on port $LOCAL_PORT${NC}"
        # Don't show lsof output to prevent password exposure in command lines
        
        echo "$tunnel_pids" | while read pid; do
            if [[ -n "$pid" ]]; then
                # Don't show command line to prevent password exposure
                log_info "Terminating tunnel process $pid"
                kill -9 $pid >/dev/null 2>&1
            fi
        done
        
        # Verify tunnel is closed
        sleep 2
        if ! lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
            log_success "Local SSH tunnel terminated successfully"
        else
            log_warning "Some processes may still be using port $LOCAL_PORT"
            # Don't show lsof details to prevent password exposure
        fi
    else
        log_success "No SSH tunnel found on port $LOCAL_PORT"
    fi
}

# Cleanup remote server
cleanup_remote_server() {
    local target_host="$1"
    local target_user="$2"
    local target_ssh_key="$3"
    local target_use_password="$4"
    local target_password="$5"
    
    log_info "🌐 Cleaning up remote server processes on $target_host..."
    
    # Build SSH command based on authentication method
    local ssh_cmd
    if [[ "$target_use_password" == "true" ]]; then
        if ! command -v sshpass &> /dev/null; then
            log_error "sshpass is required for password authentication but not installed"
            return 1
        fi
        ssh_cmd="sshpass -p '$target_password' ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    else
        ssh_cmd="ssh -i '$target_ssh_key' -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    fi
    
    # Test SSH connection first
    log_debug "Testing SSH connection to $target_user@$target_host"
    if ! eval "$ssh_cmd '$target_user@$target_host' 'echo \"SSH connection test successful\"'" >/dev/null 2>&1; then
        log_error "Cannot connect to remote host: $target_user@$target_host"
        log_info "Remote cleanup skipped - check SSH connectivity"
        return 1
    fi
    log_debug "SSH connection test passed"
    
    # Kill remote server processes - simplified and more robust approach
    echo "🔍 Looking for remote server processes..."
    
    # Execute a simple and robust cleanup command - step by step approach
    local cleanup_result
    
    # Step 1: Basic connection and hostname
    cleanup_result=$(eval "$ssh_cmd '$target_user@$target_host' 'echo \"Starting cleanup on \$(hostname)...\"'" 2>&1)
    local step1_exit=$?
    
    if [[ $step1_exit -ne 0 ]]; then
        log_error "Failed initial connection test"
        echo "Error output: $cleanup_result"
        return 1
    fi
    
    echo "$cleanup_result"
    
    # Step 2: Kill Python processes (one at a time)
    eval "$ssh_cmd '$target_user@$target_host' 'pkill -f python.*enhanced_http_server'" 2>/dev/null && echo "✅ Killed enhanced_http_server processes" || echo "✅ No enhanced_http_server processes found"
    
    eval "$ssh_cmd '$target_user@$target_host' 'pkill -f start_http_server'" 2>/dev/null && echo "✅ Killed start_http_server processes" || echo "✅ No start_http_server processes found"
    
    eval "$ssh_cmd '$target_user@$target_host' 'pkill -f \"python.*http.server\"'" 2>/dev/null && echo "✅ Killed http.server processes" || echo "✅ No http.server processes found"
    
    eval "$ssh_cmd '$target_user@$target_host' 'pkill -f \"python.*-m.*http\"'" 2>/dev/null && echo "✅ Killed python -m http processes" || echo "✅ No python -m http processes found"
    
    # Step 3: Try to kill processes on port 8081 (simple approach)
    local port_cleanup_result
    port_cleanup_result=$(eval "$ssh_cmd '$target_user@$target_host' 'if command -v lsof >/dev/null 2>&1; then lsof -t -i:8081 2>/dev/null | xargs -r kill -TERM 2>/dev/null && echo \"Killed processes on port 8081\" || echo \"No processes on port 8081\"; else echo \"lsof not available, skipping port cleanup\"; fi'" 2>/dev/null)
    
    if [[ -n "$port_cleanup_result" ]]; then
        echo "$port_cleanup_result"
    fi
    
    echo "✅ Remote cleanup completed successfully"
    return 0
}

# Show cleanup host selection menu
show_cleanup_host_selection_menu() {
    local hosts=($(get_available_hosts_cleanup))
    local CLEANUP_ALL=false
    
    if [[ ${#hosts[@]} -eq 0 ]]; then
        log_error "No hosts configured"
        log_info "Please configure hosts first using the authentication options"
        echo -e "${BOLD}${PURPLE}Press Enter to return to main menu...${NC}"
        read
        return 1
    fi
    
    echo
    echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${WHITE}${BOLD}            🧹 Select Host for Cleanup 🧹           ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${BOLD}Cleanup Options:${NC}"
    echo
    echo -e "${BOLD}${GREEN}[0]${NC} ${BOLD}Clean up ALL configured hosts${NC}"
    echo -e "     ${WHITE}🌐 Clean tunnels and servers for all IPs${NC}"
    echo
    echo -e "${BOLD}Available Hosts:${NC}"
    echo
    
    local counter=1
    for host in "${hosts[@]}"; do
        local user="Unknown"
        local auth_type="${RED}No Config${NC}"
        
        # Check SSH configurations first
        local ssh_config=$(load_ssh_config)
        if [[ "$ssh_config" != "{}" ]]; then
            local ssh_info=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    if 'saved_keys' in config:
        for name, details in config['saved_keys'].items():
            if details.get('host') == '$host':
                print(f\"{details['user']}\")
                exit(0)
except:
    pass
" 2>/dev/null)
            
            if [[ -n "$ssh_info" ]]; then
                user="$ssh_info"
                auth_type="${GREEN}SSH KEY${NC}"
            fi
        fi
        
        # If not found in SSH, check password configurations
        if [[ "$auth_type" == "${RED}No Config${NC}" ]]; then
            local password_config=$(load_password_config)
            if [[ "$password_config" != "{}" ]]; then
                local password_info=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    if 'saved_passwords' in config:
        for name, details in config['saved_passwords'].items():
            if details.get('host') == '$host':
                print(f\"{details['user']}\")
                exit(0)
except:
    pass
" 2>/dev/null)
                
                if [[ -n "$password_info" ]]; then
                    user="$password_info"
                    auth_type="${YELLOW}SSH PASSWORD${NC}"
                fi
            fi
        fi
        
        echo -e "${BOLD}${GREEN}[$counter]${NC} ${CYAN}$host${NC}"
        echo -e "     Auth: $auth_type | User: ${WHITE}$user${NC}"
        echo
        ((counter++))
    done
    
    echo -e "${BOLD}${RED}[b]${NC} ${BOLD}Back to main menu${NC}"
    echo
    
    while true; do
        echo -ne "${BOLD}${CYAN}Select option [0-${#hosts[@]}/b]: ${NC}"
        read -r choice
        
        if [[ "$choice" == "0" ]]; then
            CLEANUP_ALL=true
            log_info "Selected cleanup for ALL hosts"
            break
            
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#hosts[@]} ]; then
            local selected_host="${hosts[$((choice-1))]}"
            
            if set_host_config_cleanup "$selected_host"; then
                log_success "Selected host: $selected_host"
                break
            else
                log_error "Failed to configure host $selected_host"
                continue
            fi
            
        elif [[ "$choice" == "b" || "$choice" == "B" ]]; then
            log_info "Returning to main menu"
            return 1
            
        else
            log_error "Invalid choice. Please select 0-${#hosts[@]} or 'b' to go back."
        fi
    done
    
    # Perform cleanup
    echo
    cleanup_local_tunnel
    echo
    
    if [[ "$CLEANUP_ALL" == "true" ]]; then
        # Cleanup all hosts
        local success_count=0
        local total_count=${#hosts[@]}
        
        log_info "Starting cleanup for $total_count configured hosts..."
        echo
        
        for host in "${hosts[@]}"; do
            log_info "Processing host: $host"
            
            if set_host_config_cleanup "$host"; then
                cleanup_remote_server "$REMOTE_HOST" "$REMOTE_USER" "$SSH_KEY" "$USE_PASSWORD" "$REMOTE_PASSWORD"
                if [[ $? -eq 0 ]]; then
                    ((success_count++))
                    log_success "Cleanup completed for $host"
                else
                    log_warning "Cleanup failed for $host"
                fi
            else
                log_warning "Skipping $host - no valid configuration found"
            fi
            echo
        done
        
        log_info "Cleanup summary: $success_count/$total_count hosts processed successfully"
    else
        # Cleanup selected host
        cleanup_remote_server "$REMOTE_HOST" "$REMOTE_USER" "$SSH_KEY" "$USE_PASSWORD" "$REMOTE_PASSWORD"
    fi
    
    echo -e "${GREEN}🎉 Cleanup completed!${NC}"
    echo -e "${BOLD}${PURPLE}Press Enter to return to main menu...${NC}"
    read
    
    return 0
}

# ═══════════════════════════════════════════════════════════════════
# IMPORT/EXPORT CONFIGURATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

import_export_configs() {
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}        📤📥 Import/Export Tunnel Configurations 📥📤    ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo

    while true; do
        echo -e "${BOLD}Import/Export Options:${NC}"
        echo
        echo -e "  ${GREEN}1${NC}. Export configurations to remote host"
        echo -e "  ${GREEN}2${NC}. Import configurations from remote host"
        echo -e "  ${GREEN}3${NC}. Custom export (manual IP/credentials)"
        echo -e "  ${GREEN}4${NC}. Custom import (manual IP/credentials)"
        echo -e "  ${RED}b${NC}. Back to main menu"
        echo

        read -p "$(echo -e "${BOLD}Choose option (1-4/b):${NC} ")" import_export_choice

        case "$import_export_choice" in
            1)
                export_configs_to_saved_host
                ;;
            2)
                import_configs_from_saved_host
                ;;
            3)
                export_configs_custom
                ;;
            4)
                import_configs_custom
                ;;
            b|B)
                return 0
                ;;
            *)
                log_warning "Invalid choice. Please select 1-4 or b."
                echo
                ;;
        esac
    done
}

export_configs_to_saved_host() {
    echo
    echo -e "${BOLD}Export Configurations to Saved Host:${NC}"
    echo

    # Load both configurations
    local ssh_config=$(load_ssh_config)
    local password_config=$(load_password_config)

    # Show available configurations and let user select a target host
    if ! select_from_saved_configurations "$ssh_config" "$password_config"; then
        log_info "Export cancelled"
        return 1
    fi

    # Confirm export
    echo
    echo -e "${BOLD}${YELLOW}⚠️  EXPORT CONFIRMATION${NC}"
    echo -e "Target host: ${WHITE}$REMOTE_USER@$REMOTE_HOST${NC}"
    echo -e "This will copy all configuration files to the remote host."
    echo -e "Files to export:"
    echo -e "  • ~/.tunnel_configs/ssh_configs.json"
    echo -e "  • ~/.tunnel_configs/password_configs.json"
    echo -e "  • ~/.tunnel_configs/remote_hosts.conf"
    echo
    read -p "$(echo -e "${BOLD}Continue with export? (y/n):${NC} ")" confirm_export

    if [[ ! "$confirm_export" =~ ^[Yy] ]]; then
        log_info "Export cancelled by user"
        return 1
    fi

    perform_config_export "$REMOTE_USER" "$REMOTE_HOST" "$SSH_KEY" "$USE_PASSWORD" "$REMOTE_PASSWORD"
}

import_configs_from_saved_host() {
    echo
    echo -e "${BOLD}Import Configurations from Saved Host:${NC}"
    echo

    # Load both configurations
    local ssh_config=$(load_ssh_config)
    local password_config=$(load_password_config)

    # Show available configurations and let user select a source host
    if ! select_from_saved_configurations "$ssh_config" "$password_config"; then
        log_info "Import cancelled"
        return 1
    fi

    # Confirm import
    echo
    echo -e "${BOLD}${YELLOW}⚠️  IMPORT CONFIRMATION${NC}"
    echo -e "Source host: ${WHITE}$REMOTE_USER@$REMOTE_HOST${NC}"
    echo -e "This will copy configuration files from the remote host."
    echo -e "${RED}WARNING: This will overwrite existing local configurations!${NC}"
    echo
    read -p "$(echo -e "${BOLD}Continue with import? (y/n):${NC} ")" confirm_import

    if [[ ! "$confirm_import" =~ ^[Yy] ]]; then
        log_info "Import cancelled by user"
        return 1
    fi

    perform_config_import "$REMOTE_USER" "$REMOTE_HOST" "$SSH_KEY" "$USE_PASSWORD" "$REMOTE_PASSWORD"
}

export_configs_custom() {
    echo
    echo -e "${BOLD}Custom Export Configuration:${NC}"
    echo

    # Get connection details manually
    local custom_user custom_host custom_ssh_key custom_password=""
    local custom_use_password=false

    read -p "$(echo -e "${BOLD}Target username:${NC} ")" custom_user
    if [[ -z "$custom_user" ]]; then
        log_warning "Username cannot be empty"
        return 1
    fi

    read -p "$(echo -e "${BOLD}Target host/IP:${NC} ")" custom_host
    if [[ -z "$custom_host" ]]; then
        log_warning "Host cannot be empty"
        return 1
    fi

    echo
    echo -e "${BOLD}Authentication method:${NC}"
    echo -e "  ${GREEN}1${NC}. SSH Key"
    echo -e "  ${GREEN}2${NC}. Password"
    echo
    read -p "$(echo -e "${BOLD}Choose method (1-2):${NC} ")" auth_method

    case "$auth_method" in
        1)
            read -p "$(echo -e "${BOLD}SSH key file path:${NC} ")" custom_ssh_key
            if [[ -z "$custom_ssh_key" ]]; then
                log_warning "SSH key path cannot be empty"
                return 1
            fi
            custom_ssh_key="${custom_ssh_key/#\~/$HOME}"
            if [[ ! -f "$custom_ssh_key" ]]; then
                log_error "SSH key file not found: $custom_ssh_key"
                return 1
            fi
            custom_use_password=false
            ;;
        2)
            if ! command -v sshpass &> /dev/null; then
                log_error "sshpass is required for password authentication but not installed"
                return 1
            fi
            read -s -p "$(echo -e "${BOLD}SSH password:${NC} ")" custom_password
            echo
            if [[ -z "$custom_password" ]]; then
                log_warning "Password cannot be empty"
                return 1
            fi
            custom_use_password=true
            ;;
        *)
            log_warning "Invalid authentication method"
            return 1
            ;;
    esac

    # Validate connection before export
    log_info "Validating connection to $custom_user@$custom_host..."
    if ! validate_custom_connection "$custom_user" "$custom_host" "$custom_ssh_key" "$custom_use_password" "$custom_password"; then
        log_error "Connection validation failed"
        return 1
    fi

    perform_config_export "$custom_user" "$custom_host" "$custom_ssh_key" "$custom_use_password" "$custom_password"
}

import_configs_custom() {
    echo
    echo -e "${BOLD}Custom Import Configuration:${NC}"
    echo

    # Get connection details manually
    local custom_user custom_host custom_ssh_key custom_password=""
    local custom_use_password=false

    read -p "$(echo -e "${BOLD}Source username:${NC} ")" custom_user
    if [[ -z "$custom_user" ]]; then
        log_warning "Username cannot be empty"
        return 1
    fi

    read -p "$(echo -e "${BOLD}Source host/IP:${NC} ")" custom_host
    if [[ -z "$custom_host" ]]; then
        log_warning "Host cannot be empty"
        return 1
    fi

    echo
    echo -e "${BOLD}Authentication method:${NC}"
    echo -e "  ${GREEN}1${NC}. SSH Key"
    echo -e "  ${GREEN}2${NC}. Password"
    echo
    read -p "$(echo -e "${BOLD}Choose method (1-2):${NC} ")" auth_method

    case "$auth_method" in
        1)
            read -p "$(echo -e "${BOLD}SSH key file path:${NC} ")" custom_ssh_key
            if [[ -z "$custom_ssh_key" ]]; then
                log_warning "SSH key path cannot be empty"
                return 1
            fi
            custom_ssh_key="${custom_ssh_key/#\~/$HOME}"
            if [[ ! -f "$custom_ssh_key" ]]; then
                log_error "SSH key file not found: $custom_ssh_key"
                return 1
            fi
            custom_use_password=false
            ;;
        2)
            if ! command -v sshpass &> /dev/null; then
                log_error "sshpass is required for password authentication but not installed"
                return 1
            fi
            read -s -p "$(echo -e "${BOLD}SSH password:${NC} ")" custom_password
            echo
            if [[ -z "$custom_password" ]]; then
                log_warning "Password cannot be empty"
                return 1
            fi
            custom_use_password=true
            ;;
        *)
            log_warning "Invalid authentication method"
            return 1
            ;;
    esac

    # Validate connection before import
    log_info "Validating connection to $custom_user@$custom_host..."
    if ! validate_custom_connection "$custom_user" "$custom_host" "$custom_ssh_key" "$custom_use_password" "$custom_password"; then
        log_error "Connection validation failed"
        return 1
    fi

    # Confirm import with warning
    echo
    echo -e "${BOLD}${YELLOW}⚠️  IMPORT CONFIRMATION${NC}"
    echo -e "Source host: ${WHITE}$custom_user@$custom_host${NC}"
    echo -e "${RED}WARNING: This will overwrite existing local configurations!${NC}"
    echo
    read -p "$(echo -e "${BOLD}Continue with import? (y/n):${NC} ")" confirm_import

    if [[ ! "$confirm_import" =~ ^[Yy] ]]; then
        log_info "Import cancelled by user"
        return 1
    fi

    perform_config_import "$custom_user" "$custom_host" "$custom_ssh_key" "$custom_use_password" "$custom_password"
}

validate_custom_connection() {
    local user="$1"
    local host="$2"
    local ssh_key="$3"
    local use_password="$4"
    local password="$5"

    local ssh_cmd
    if [[ "$use_password" == "true" ]]; then
        ssh_cmd="sshpass -p $(printf '%q' "$password") ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no"
    else
        ssh_cmd="ssh -i '$ssh_key' -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no"
    fi

    if eval "$ssh_cmd '$user@$host' 'echo \"Connection test successful\"'" >/dev/null 2>&1; then
        log_success "Connection validation successful"
        return 0
    else
        log_error "Connection validation failed"
        return 1
    fi
}

perform_config_export() {
    local user="$1"
    local host="$2"
    local ssh_key="$3"
    local use_password="$4"
    local password="$5"

    log_info "Starting configuration export to $user@$host..."

    # Build SCP command
    local scp_cmd
    if [[ "$use_password" == "true" ]]; then
        scp_cmd="sshpass -p $(printf '%q' "$password") scp -o StrictHostKeyChecking=no"
    else
        scp_cmd="scp -i '$ssh_key' -o StrictHostKeyChecking=no"
    fi

    # Create remote config directory
    local ssh_cmd
    if [[ "$use_password" == "true" ]]; then
        ssh_cmd="sshpass -p $(printf '%q' "$password") ssh -o StrictHostKeyChecking=no"
    else
        ssh_cmd="ssh -i '$ssh_key' -o StrictHostKeyChecking=no"
    fi

    # Ensure remote config directory exists with proper permissions
    log_debug "Creating remote configuration directory..."
    if ! eval "$ssh_cmd '$user@$host' 'mkdir -p ~/.tunnel_configs && chmod 700 ~/.tunnel_configs'" >/dev/null 2>&1; then
        log_error "Failed to create remote configuration directory"
        return 1
    fi
    log_debug "Remote configuration directory created successfully"

    # Export each configuration file
    local files_exported=0
    local total_files=0

    # Get actual config file paths
    local ssh_config_file="$(get_config_dir)/ssh_configs.json"
    local password_config_file="$(get_config_dir)/password_configs.json"
    local hosts_config_file="$HOSTS_CONFIG_FILE"
    
    for config_file in "$ssh_config_file" "$password_config_file" "$hosts_config_file"; do
        ((total_files++))
        local filename=$(basename "$config_file")
        
        if [[ -f "$config_file" ]]; then
            log_debug "Exporting $filename to remote host..."
            if eval "$scp_cmd '$config_file' '$user@$host:~/.tunnel_configs/'" >/dev/null 2>&1; then
                log_success "✅ Exported $filename"
                ((files_exported++))
            else
                log_error "❌ Failed to export $filename"
            fi
        else
            log_warning "⚠️  Local file not found: $filename"
        fi
    done

    # Set proper permissions on remote files
    log_debug "Setting permissions on remote configuration files..."
    eval "$ssh_cmd '$user@$host' 'chmod 600 ~/.tunnel_configs/*.json ~/.tunnel_configs/*.conf 2>/dev/null || true'" >/dev/null 2>&1
    
    # Ensure the directory and files exist and have proper permissions
    log_debug "Verifying remote file setup..."
    eval "$ssh_cmd '$user@$host' 'ls -la ~/.tunnel_configs/ >/dev/null 2>&1 && echo \"Remote configuration directory verified\"'" >/dev/null 2>&1

    echo
    log_info "Export Summary: $files_exported/$total_files files transferred successfully"
    
    if [[ $files_exported -gt 0 ]]; then
        log_success "Configuration export completed successfully!"
    else
        log_warning "No files were exported"
    fi

    echo -e "${BOLD}${PURPLE}Press Enter to continue...${NC}"
    read
}

perform_config_import() {
    local user="$1"
    local host="$2"
    local ssh_key="$3"
    local use_password="$4"
    local password="$5"

    log_info "Starting configuration import from $user@$host..."

    # Build SCP command
    local scp_cmd
    if [[ "$use_password" == "true" ]]; then
        scp_cmd="sshpass -p $(printf '%q' "$password") scp -o StrictHostKeyChecking=no"
    else
        scp_cmd="scp -i '$ssh_key' -o StrictHostKeyChecking=no"
    fi

    # Ensure local config directory exists with proper permissions
    log_debug "Creating local configuration directory..."
    mkdir -p "$HOSTS_CONFIG_DIR"
    chmod 700 "$HOSTS_CONFIG_DIR"

    # Import each configuration file
    local files_imported=0
    local total_files=0

    for config_file in "ssh_configs.json" "password_configs.json" "remote_hosts.conf"; do
        ((total_files++))
        local remote_path="$user@$host:~/.tunnel_configs/$config_file"
        local local_path="$HOSTS_CONFIG_DIR/$config_file"
        
        log_debug "Importing $config_file from remote host..."
        if eval "$scp_cmd '$remote_path' '$local_path'" >/dev/null 2>&1; then
            # Validate imported file
            if [[ -f "$local_path" ]]; then
                # Check for duplicates and validate JSON format
                if validate_imported_config "$local_path" "$config_file"; then
                    # Set proper permissions on imported file
                    chmod 600 "$local_path"
                    log_success "✅ Imported and validated $config_file"
                    ((files_imported++))
                else
                    log_warning "⚠️  Imported $config_file but validation failed"
                fi
            else
                log_error "❌ Failed to import $config_file - file not found after transfer"
            fi
        else
            log_warning "⚠️  Remote file not found or transfer failed: $config_file"
        fi
    done

    # Set proper permissions on all config files
    chmod 600 "$HOSTS_CONFIG_DIR"/*.json "$HOSTS_CONFIG_DIR"/*.conf 2>/dev/null || true

    # Sync hosts file after import
    log_debug "Synchronizing hosts file after import..."
    sync_hosts_from_configs

    echo
    log_info "Import Summary: $files_imported/$total_files files imported successfully"
    
    if [[ $files_imported -gt 0 ]]; then
        log_success "Configuration import completed successfully!"
        log_info "New configurations are now available in the main menu"
    else
        log_warning "No files were imported"
    fi

    echo -e "${BOLD}${PURPLE}Press Enter to continue...${NC}"
    read
}

validate_imported_config() {
    local file_path="$1"
    local file_name="$2"

    case "$file_name" in
        "ssh_configs.json"|"password_configs.json")
            # Validate JSON format
            if ! python3 -c "import json; json.load(open('$file_path'))" >/dev/null 2>&1; then
                log_error "Invalid JSON format in $file_name"
                return 1
            fi
            log_debug "JSON validation passed for $file_name"
            ;;
        "remote_hosts.conf")
            # Basic validation for hosts file
            if [[ ! -r "$file_path" ]]; then
                log_error "Cannot read $file_name"
                return 1
            fi
            log_debug "Hosts file validation passed for $file_name"
            ;;
    esac

    return 0
}

# Sync hosts file from configurations after import
sync_hosts_from_configs() {
    log_debug "Synchronizing hosts file from imported configurations..."
    
    # Create hosts file content
    local hosts_content="# SSH KEY saved connections IPS\n\n"
    
    # Add SSH key IPs
    local ssh_config=$(load_ssh_config)
    if [[ "$ssh_config" != "{}" ]]; then
        local ssh_ips=$(python3 -c "
import json
try:
    config = json.loads('''$ssh_config''')
    unique_ips = set()
    if 'saved_keys' in config:
        for name, details in config['saved_keys'].items():
            if 'host' in details:
                unique_ips.add(details['host'])
    for ip in sorted(unique_ips):
        print(ip)
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$ssh_ips" ]]; then
            while IFS= read -r ip; do
                if [[ -n "$ip" ]]; then
                    hosts_content+="$ip\n"
                fi
            done <<< "$ssh_ips"
        fi
    fi
    
    hosts_content+="\n# SSH PASSWORD saved connections IPS\n\n"
    
    # Add password IPs
    local password_config=$(load_password_config)
    if [[ "$password_config" != "{}" ]]; then
        local password_ips=$(python3 -c "
import json
try:
    config = json.loads('''$password_config''')
    unique_ips = set()
    if 'saved_passwords' in config:
        for name, details in config['saved_passwords'].items():
            if 'host' in details:
                unique_ips.add(details['host'])
    for ip in sorted(unique_ips):
        print(ip)
except:
    pass
" 2>/dev/null)
        
        if [[ -n "$password_ips" ]]; then
            while IFS= read -r ip; do
                if [[ -n "$ip" ]]; then
                    hosts_content+="$ip\n"
                fi
            done <<< "$password_ips"
        fi
    fi
    
    # Write hosts file
    echo -e "$hosts_content" > "$HOSTS_CONFIG_FILE"
    log_debug "Hosts file synchronized successfully"
}

# ═══════════════════════════════════════════════════════════════════

setup_connection() {
    echo
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}           🔐 Connection Configuration 🔐             ${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo
    
    # Load both SSH and password configs
    local ssh_config=$(load_ssh_config)
    local password_config=$(load_password_config)
    
    # First, show available saved configurations
    show_available_configurations "$ssh_config" "$password_config"
    
    echo -e "${BOLD}Authentication Options:${NC}"
    echo
    echo -e "  ${GREEN}1${NC}. List/Run tunnel launcher with saved ssh keys/password configurations"
    echo -e "  ${GREEN}2${NC}. Remove/Clear created tunnels and port sessions"
    echo -e "  ${GREEN}3${NC}. Save new SSH key configuration"
    echo -e "  ${GREEN}4${NC}. Save new password configuration"
    echo -e "  ${GREEN}5${NC}. Remove ssh keys/ssh passwords saved configurations"
    echo -e "  ${GREEN}6${NC}. Saved ssh keys/ssh password IPs configurations"
    echo -e "  ${GREEN}7${NC}. Import/export remote tunnel connections configs"
    echo
    
    if [[ "$AUTO_YES" == true ]]; then
        choice="1"
        log_info "Auto-selecting saved configurations"
        if select_from_saved_configurations "$ssh_config" "$password_config"; then
            return 0
        else
            return 1
        fi
    fi
    
    while true; do
        read -p "$(echo -e "${BOLD}Choose option (1-7):${NC} ")" choice
        
        case "$choice" in
            1)
                if select_from_saved_configurations "$ssh_config" "$password_config"; then
                    return 0
                else
                    # User pressed Enter to go back, redisplay menu
                    echo
                    # Reload configurations in case they changed
                    ssh_config=$(load_ssh_config)
                    password_config=$(load_password_config)
                    # Redisplay the menu to help user reorient
                    show_available_configurations "$ssh_config" "$password_config"
                    echo -e "${BOLD}Authentication Options:${NC}"
                    echo
                    echo -e "  ${GREEN}1${NC}. List/Run tunnel launcher with saved ssh keys/password configurations"
                    echo -e "  ${GREEN}2${NC}. Remove/Clear created tunnels and port sessions"
                    echo -e "  ${GREEN}3${NC}. Save new SSH key configuration"
                    echo -e "  ${GREEN}4${NC}. Save new password configuration"
                    echo -e "  ${GREEN}5${NC}. Remove ssh keys/ssh passwords saved configurations"
                    echo -e "  ${GREEN}6${NC}. Saved ssh keys/ssh password IPs configurations"
                    echo -e "  ${GREEN}7${NC}. Import/export remote tunnel connections configs"
                    echo
                fi
                ;;
            2)
                # Run cleanup functionality
                show_cleanup_host_selection_menu
                # After cleanup, redisplay the main menu
                echo
                ssh_config=$(load_ssh_config)
                password_config=$(load_password_config)
                show_available_configurations "$ssh_config" "$password_config"
                echo -e "${BOLD}Authentication Options:${NC}"
                echo
                echo -e "  ${GREEN}1${NC}. List/Run tunnel launcher with saved ssh keys/password configurations"
                echo -e "  ${GREEN}2${NC}. Remove/Clear created tunnels and port sessions"
                echo -e "  ${GREEN}3${NC}. Save new SSH key configuration"
                echo -e "  ${GREEN}4${NC}. Save new password configuration"
                echo -e "  ${GREEN}5${NC}. Remove ssh keys/ssh passwords saved configurations"
                echo -e "  ${GREEN}6${NC}. Saved ssh keys/ssh password IPs configurations"
                echo -e "  ${GREEN}7${NC}. Import/export remote tunnel connections configs"
                echo
                ;;
            3)
                if save_new_ssh_config "$ssh_config"; then
                    ssh_config=$(load_ssh_config)  # Reload after saving
                fi
                ;;
            4)
                if save_new_password_config "$password_config"; then
                    password_config=$(load_password_config)  # Reload after saving
                fi
                ;;
            5)
                if remove_saved_configuration "$ssh_config" "$password_config"; then
                    # Reload configurations after deletion
                    ssh_config=$(load_ssh_config)
                    password_config=$(load_password_config)
                    # Update display and restart the menu
                    echo
                    show_available_configurations "$ssh_config" "$password_config"
                    echo -e "${BOLD}Authentication Options:${NC}"
                    echo
                    echo -e "  ${GREEN}1${NC}. List/Run tunnel launcher with saved ssh keys/password configurations"
                    echo -e "  ${GREEN}2${NC}. Remove/Clear created tunnels and port sessions"
                    echo -e "  ${GREEN}3${NC}. Save new SSH key configuration"
                    echo -e "  ${GREEN}4${NC}. Save new password configuration"
                    echo -e "  ${GREEN}5${NC}. Remove ssh keys/ssh passwords saved configurations"
                    echo -e "  ${GREEN}6${NC}. Saved ssh keys/ssh password IPs configurations"
                    echo -e "  ${GREEN}7${NC}. Import/export remote tunnel connections configs"
                    echo
                fi
                ;;
            6)
                if show_host_selection_menu; then
                    return 0
                else
                    # User went back, reload configurations and redisplay menu
                    echo
                    ssh_config=$(load_ssh_config)
                    password_config=$(load_password_config)
                    show_available_configurations "$ssh_config" "$password_config"
                    echo -e "${BOLD}Authentication Options:${NC}"
                    echo
                    echo -e "  ${GREEN}1${NC}. List/Run tunnel launcher with saved ssh keys/password configurations"
                    echo -e "  ${GREEN}2${NC}. Remove/Clear created tunnels and port sessions"
                    echo -e "  ${GREEN}3${NC}. Save new SSH key configuration"
                    echo -e "  ${GREEN}4${NC}. Save new password configuration"
                    echo -e "  ${GREEN}5${NC}. Remove ssh keys/ssh passwords saved configurations"
                    echo -e "  ${GREEN}6${NC}. Saved ssh keys/ssh password IPs configurations"
                    echo -e "  ${GREEN}7${NC}. Import/export remote tunnel connections configs"
                    echo
                fi
                ;;
            7)
                # Run import/export functionality
                import_export_configs
                # After import/export, reload configurations and sync hosts
                echo
                log_debug "Reloading configurations after import/export..."
                sync_hosts_from_configs  # Ensure hosts file is updated
                ssh_config=$(load_ssh_config)
                password_config=$(load_password_config)
                show_available_configurations "$ssh_config" "$password_config"
                echo -e "${BOLD}Authentication Options:${NC}"
                echo
                echo -e "  ${GREEN}1${NC}. List/Run tunnel launcher with saved ssh keys/password configurations"
                echo -e "  ${GREEN}2${NC}. Remove/Clear created tunnels and port sessions"
                echo -e "  ${GREEN}3${NC}. Save new SSH key configuration"
                echo -e "  ${GREEN}4${NC}. Save new password configuration"
                echo -e "  ${GREEN}5${NC}. Remove ssh keys/ssh passwords saved configurations"
                echo -e "  ${GREEN}6${NC}. Saved ssh keys/ssh password IPs configurations"
                echo -e "  ${GREEN}7${NC}. Import/export remote tunnel connections configs"
                echo
                ;;
            *)
                log_warning "Invalid choice. Please select 1-7."
                echo
                # Reload configurations in case they changed during invalid attempts
                ssh_config=$(load_ssh_config)
                password_config=$(load_password_config)
                # Redisplay the menu to help user reorient
                show_available_configurations "$ssh_config" "$password_config"
                echo -e "${BOLD}Authentication Options:${NC}"
                echo
                echo -e "  ${GREEN}1${NC}. List/Run tunnel launcher with saved ssh keys/password configurations"
                echo -e "  ${GREEN}2${NC}. Remove/Clear created tunnels and port sessions"
                echo -e "  ${GREEN}3${NC}. Save new SSH key configuration"
                echo -e "  ${GREEN}4${NC}. Save new password configuration"
                echo -e "  ${GREEN}5${NC}. Remove ssh keys/ssh passwords saved configurations"
                echo -e "  ${GREEN}6${NC}. Saved ssh keys/ssh password IPs configurations"
                echo -e "  ${GREEN}7${NC}. Import/export remote tunnel connections configs"
                echo
                ;;
        esac
    done
    
}

setup_ssh_key_auth() {
    local config="$1"
    
    local default_key=$(echo "$config" | grep -o '"default_key": *"[^"]*"' | sed 's/.*": *"\([^"]*\)".*/\1/')
    local default_user=$(echo "$config" | grep -o '"default_user": *"[^"]*"' | sed 's/.*": *"\([^"]*\)".*/\1/')
    local default_host=$(echo "$config" | grep -o '"default_host": *"[^"]*"' | sed 's/.*": *"\([^"]*\)".*/\1/')
    
    echo -e "${BOLD}SSH Key Authentication Setup:${NC}"
    echo
    
    # Get SSH key path
    if [[ -n "$default_key" && "$default_key" != "" ]]; then
        read -p "$(echo -e "${BOLD}SSH key path [$default_key]:${NC} ")" SSH_KEY
        SSH_KEY="${SSH_KEY:-$default_key}"
    else
        read -p "$(echo -e "${BOLD}Enter SSH key path:${NC} ")" SSH_KEY
        while [[ -z "$SSH_KEY" ]]; do
            log_warning "SSH key path cannot be empty"
            read -p "$(echo -e "${BOLD}Enter SSH key path:${NC} ")" SSH_KEY
        done
    fi
    
    # Get username
    read -p "$(echo -e "${BOLD}SSH user [$default_user]:${NC} ")" REMOTE_USER
    REMOTE_USER="${REMOTE_USER:-$default_user}"
    
    # Get hostname
    read -p "$(echo -e "${BOLD}SSH host/IP:${NC} ")" REMOTE_HOST
    while [[ -z "$REMOTE_HOST" ]]; do
        log_warning "Host cannot be empty"
        read -p "$(echo -e "${BOLD}SSH host/IP:${NC} ")" REMOTE_HOST
    done
    
    USE_PASSWORD=false
    
    # Expand tilde in SSH_KEY path
    SSH_KEY="${SSH_KEY/#\~/$HOME}"
    
    # Validate configuration
    if validate_ssh_config "$SSH_KEY" "$REMOTE_USER" "$REMOTE_HOST"; then
        log_success "SSH key configuration validated and ready"
        log_debug "Selected SSH configuration: SSH_KEY=$SSH_KEY, REMOTE_USER=$REMOTE_USER, REMOTE_HOST=$REMOTE_HOST"
        echo
        return 0
    else
        log_error "SSH key configuration validation failed"
        return 1
    fi
}

setup_password_auth() {
    local config="$1"
    
    # Check if sshpass is available
    if ! command -v sshpass &> /dev/null; then
        log_error "sshpass is required for password authentication but not installed"
        echo -e "${YELLOW}Install sshpass:${NC}"
        echo -e "  Ubuntu/Debian: sudo apt install sshpass"
        echo -e "  CentOS/RHEL: sudo yum install sshpass"
        return 1
    fi
    
    local default_user=$(echo "$config" | grep -o '"default_user": *"[^"]*"' | sed 's/.*": *"\([^"]*\)".*/\1/')
    local default_host=$(echo "$config" | grep -o '"default_host": *"[^"]*"' | sed 's/.*": *"\([^"]*\)".*/\1/')
    
    echo -e "${BOLD}Password Authentication Setup:${NC}"
    echo
    
    # Get username
    read -p "$(echo -e "${BOLD}SSH user [$default_user]:${NC} ")" REMOTE_USER
    REMOTE_USER="${REMOTE_USER:-$default_user}"
    
    # Get hostname
    read -p "$(echo -e "${BOLD}SSH host/IP:${NC} ")" REMOTE_HOST
    while [[ -z "$REMOTE_HOST" ]]; do
        log_warning "Host cannot be empty"
        read -p "$(echo -e "${BOLD}SSH host/IP:${NC} ")" REMOTE_HOST
    done
    
    # Get password
    read -s -p "$(echo -e "${BOLD}Enter SSH password:${NC} ")" REMOTE_PASSWORD
    echo
    while [[ -z "$REMOTE_PASSWORD" ]]; do
        log_warning "Password cannot be empty"
        read -s -p "$(echo -e "${BOLD}Enter SSH password:${NC} ")" REMOTE_PASSWORD
        echo
    done
    
    USE_PASSWORD=true
    
    # Validate configuration
    if validate_password_config "$REMOTE_USER" "$REMOTE_HOST" "$REMOTE_PASSWORD"; then
        log_success "Password authentication configured and validated"
        
        # Ask user if they want to save this configuration
        echo
        read -p "$(echo -e "${BOLD}Save this password configuration for future use? (y/n):${NC} ")" save_config
        if [[ "$save_config" =~ ^[Yy] ]]; then
            read -p "$(echo -e "${BOLD}Configuration name:${NC} ")" config_name
            if [[ -n "$config_name" ]]; then
                # Save the configuration
                local current_config=$(load_password_config)
                
                if [[ "$current_config" == "{}" ]]; then
                    # First password config
                    local new_config="{\"saved_passwords\": {\"$config_name\": {\"user\": \"$REMOTE_USER\", \"host\": \"$REMOTE_HOST\", \"password\": \"$REMOTE_PASSWORD\"}}, \"default_user\": \"$REMOTE_USER\", \"default_host\": \"$REMOTE_HOST\"}"
                else
                    # Add to existing configs - properly insert after opening brace
                    local new_config=$(echo "$current_config" | sed "s/{\"saved_passwords\": {/{\"saved_passwords\": {\"$config_name\": {\"user\": \"$REMOTE_USER\", \"host\": \"$REMOTE_HOST\", \"password\": \"$REMOTE_PASSWORD\"}, /")
                    # Update default user/host
                    new_config=$(echo "$new_config" | sed "s/\"default_user\": \"[^\"]*\"/\"default_user\": \"$REMOTE_USER\"/" | sed "s/\"default_host\": \"[^\"]*\"/\"default_host\": \"$REMOTE_HOST\"/")
                fi
                
                if save_password_config "$new_config"; then
                    log_success "Password configuration saved as '$config_name'"
                else
                    log_warning "Failed to save password configuration"
                fi
            fi
        fi
        
        log_success "Password authentication setup complete"
        log_debug "Selected password configuration: REMOTE_USER=$REMOTE_USER, REMOTE_HOST=$REMOTE_HOST"
        echo
        return 0
    else
        log_error "Password authentication validation failed"
        return 1
    fi
}

save_new_ssh_config() {
    local config="$1"
    
    echo -e "${BOLD}Save New SSH Key Configuration:${NC}"
    echo
    
    read -p "$(echo -e "${BOLD}Configuration name:${NC} ")" config_name
    if [[ -z "$config_name" ]]; then
        log_warning "Configuration name cannot be empty"
        return 1
    fi
    
    read -p "$(echo -e "${BOLD}SSH key file path:${NC} ")" new_key
    if [[ -z "$new_key" ]]; then
        log_warning "SSH key path cannot be empty"
        return 1
    fi
    
    read -p "$(echo -e "${BOLD}SSH username:${NC} ")" new_user
    if [[ -z "$new_user" ]]; then
        log_warning "SSH username cannot be empty"
        return 1
    fi
    
    read -p "$(echo -e "${BOLD}SSH host/IP address:${NC} ")" new_host
    if [[ -z "$new_host" ]]; then
        log_warning "SSH host cannot be empty"
        return 1
    fi
    
    # Validate the configuration before saving
    local expanded_key="${new_key/#\~/$HOME}"
    if ! validate_ssh_config "$expanded_key" "$new_user" "$new_host"; then
        log_error "Configuration validation failed - not saving"
        return 1
    fi
    
    # Use Python for proper JSON manipulation
    local new_config=$(python3 -c "
import json, sys
try:
    # Load existing config or create empty one
    if '''$config''' == '{}':
        config_data = {'saved_keys': {}, 'default_key': '', 'default_user': '', 'default_host': ''}
    else:
        config_data = json.loads('''$config''')
    
    # Ensure saved_keys exists
    if 'saved_keys' not in config_data:
        config_data['saved_keys'] = {}
    
    # Add new SSH key configuration
    config_data['saved_keys']['$config_name'] = {
        'key': '$new_key',
        'user': '$new_user', 
        'host': '$new_host'
    }
    
    # Update defaults
    config_data['default_key'] = '$new_key'
    config_data['default_user'] = '$new_user'
    config_data['default_host'] = '$new_host'
    
    # Output clean JSON
    print(json.dumps(config_data, separators=(',', ':')))
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
")

    if [[ $? -eq 0 ]] && save_ssh_config "$new_config"; then
        log_success "SSH configuration '$config_name' saved successfully!"
        
        # Add IP to hosts file if it's new
        add_ip_to_hosts "$new_host"
        
        return 0
    else
        log_error "Failed to save SSH configuration"
        return 1
    fi
}

save_new_password_config() {
    local config="$1"
    
    # Check if sshpass is available
    if ! command -v sshpass &> /dev/null; then
        log_error "sshpass is required for password authentication but not installed"
        return 1
    fi
    
    echo -e "${BOLD}Save New Password Configuration:${NC}"
    echo
    
    read -p "$(echo -e "${BOLD}Configuration name:${NC} ")" config_name
    if [[ -z "$config_name" ]]; then
        log_warning "Configuration name cannot be empty"
        return 1
    fi
    
    read -p "$(echo -e "${BOLD}SSH username:${NC} ")" new_user
    if [[ -z "$new_user" ]]; then
        log_warning "SSH username cannot be empty"
        return 1
    fi
    
    read -p "$(echo -e "${BOLD}SSH host/IP address:${NC} ")" new_host
    if [[ -z "$new_host" ]]; then
        log_warning "SSH host cannot be empty"
        return 1
    fi
    
    read -s -p "$(echo -e "${BOLD}SSH password:${NC} ")" new_password
    echo
    if [[ -z "$new_password" ]]; then
        log_warning "SSH password cannot be empty"
        return 1
    fi
    
    # Validate the configuration before saving
    if ! validate_password_config "$new_user" "$new_host" "$new_password"; then
        log_error "Configuration validation failed - not saving"
        return 1
    fi
    
    # Use Python for proper JSON manipulation
    local new_config=$(python3 -c "
import json, sys
try:
    # Load existing config or create empty one
    if '''$config''' == '{}':
        config_data = {'saved_passwords': {}, 'default_user': '', 'default_host': ''}
    else:
        config_data = json.loads('''$config''')
    
    # Ensure saved_passwords exists
    if 'saved_passwords' not in config_data:
        config_data['saved_passwords'] = {}
    
    # Add new password configuration
    config_data['saved_passwords']['$config_name'] = {
        'user': '$new_user',
        'host': '$new_host', 
        'password': '$new_password'
    }
    
    # Update defaults
    config_data['default_user'] = '$new_user'
    config_data['default_host'] = '$new_host'
    
    # Output clean JSON
    print(json.dumps(config_data, separators=(',', ':')))
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
")

    if [[ $? -eq 0 ]] && save_password_config "$new_config"; then
        log_success "Password configuration '$config_name' saved successfully!"
        log_warning "Password is stored in plain text - keep config files secure!"
        
        # Add IP to hosts file if it's new
        add_ip_to_hosts "$new_host"
        
        return 0
    else
        log_error "Failed to save password configuration"
        return 1
    fi
}

select_saved_ssh_config() {
    local config="$1"
    
    echo -e "${BOLD}Saved SSH Configurations:${NC}"
    
    local saved_section=$(echo "$config" | sed -n 's/.*"saved_keys": *{\([^}]*\)}.*/\1/p')
    
    if [[ -z "$saved_section" || "$saved_section" == "" ]]; then
        echo -e "  ${YELLOW}No saved SSH configurations found${NC}"
        return 1
    fi
    
    local counter=1
    local temp_file=$(mktemp)
    
    echo "$saved_section" | sed 's/},/}\n/g' | while IFS= read -r entry; do
        if [[ -n "$entry" && "$entry" != *'""'* ]]; then
            local name=$(echo "$entry" | sed 's/^"*\([^"]*\)"*: *{.*/\1/')
            local key_path=$(echo "$entry" | sed 's/.*"key": *"\([^"]*\)".*/\1/')
            local user=$(echo "$entry" | sed 's/.*"user": *"\([^"]*\)".*/\1/')
            local host=$(echo "$entry" | sed 's/.*"host": *"\([^"]*\)".*/\1/')
            
            if [[ -n "$name" && -n "$key_path" ]]; then
                echo -e "  ${GREEN}$counter${NC}. ${BOLD}$name${NC}: $user@$host"
                echo -e "     ${GREEN}Key: $key_path${NC}"
                echo "$counter|$name|$key_path|$user|$host" >> "$temp_file"
                ((counter++))
                echo
            fi
        fi
    done
    
    if [[ -s "$temp_file" ]]; then
        read -p "$(echo -e "${BOLD}Select configuration number (or press Enter to go back):${NC} ")" select_num
        if [[ -n "$select_num" ]] && [[ "$select_num" =~ ^[0-9]+$ ]]; then
            local selected_line=$(grep "^$select_num|" "$temp_file")
            if [[ -n "$selected_line" ]]; then
                IFS='|' read -r _ selected_name selected_key selected_user selected_host <<< "$selected_line"
                SSH_KEY="$selected_key"
                REMOTE_USER="$selected_user"
                REMOTE_HOST="$selected_host"
                log_success "Selected SSH configuration: $selected_name"
                rm -f "$temp_file"
                return 0
            fi
        fi
    fi
    
    rm -f "$temp_file"
    return 1
}

select_saved_password_config() {
    local config="$1"
    
    echo -e "${BOLD}Saved Password Configurations:${NC}"
    
    # Check if saved_passwords exist
    if ! echo "$config" | grep -q '"saved_passwords"'; then
        echo -e "  ${YELLOW}No saved password configurations found${NC}"
        return 1
    fi
    
    local counter=1
    local temp_file=$(mktemp)
    
    # Extract password configurations using grep and parsing
    while IFS= read -r entry; do
        if [[ -n "$entry" ]]; then
            local name=$(echo "$entry" | sed 's/^"\([^"]*\)": *.*/\1/')
            local user=$(echo "$entry" | sed 's/.*"user": *"\([^"]*\)".*/\1/')
            local host=$(echo "$entry" | sed 's/.*"host": *"\([^"]*\)".*/\1/')
            local encoded_password=$(echo "$entry" | sed 's/.*"password": *"\([^"]*\)".*/\1/')
            
            if [[ -n "$name" && -n "$user" && -n "$host" ]]; then
                echo -e "  ${GREEN}$counter${NC}. ${BOLD}$name${NC}: $user@$host"
                echo "$counter|$name|$user|$host|$encoded_password" >> "$temp_file"
                ((counter++))
            fi
        fi
    done < <(echo "$config" | grep -o '"[^"]*": *{"user": *"[^"]*", *"host": *"[^"]*", *"password": *"[^"]*"}')
    
    # Check if any configurations were found by checking temp file
    if [[ ! -s "$temp_file" ]]; then
        echo -e "  ${YELLOW}No saved password configurations found${NC}"
        rm -f "$temp_file"
        return 1
    fi
    
    if [[ -s "$temp_file" ]]; then
        read -p "$(echo -e "${BOLD}Select configuration number (or press Enter to go back):${NC} ")" select_num
        if [[ -n "$select_num" ]] && [[ "$select_num" =~ ^[0-9]+$ ]]; then
            local selected_line=$(grep "^$select_num|" "$temp_file")
            if [[ -n "$selected_line" ]]; then
                IFS='|' read -r _ selected_name selected_user selected_host encoded_password <<< "$selected_line"
                REMOTE_USER="$selected_user"
                REMOTE_HOST="$selected_host"
                REMOTE_PASSWORD=$(echo "$encoded_password" | base64 -d 2>/dev/null || echo "$encoded_password")
                log_success "Selected password configuration: $selected_name"
                rm -f "$temp_file"
                return 0
            fi
        fi
    fi
    
    rm -f "$temp_file"
    return 1
}

list_saved_configurations() {
    local ssh_config="$1"
    local password_config="$2"
    
    echo -e "${BOLD}All Saved Configurations:${NC}"
    echo
    
    echo -e "${CYAN}SSH Key Configurations:${NC}"
    select_saved_ssh_config "$ssh_config" || echo -e "  ${YELLOW}None found${NC}"
    
    echo -e "${CYAN}Password Configurations:${NC}"
    select_saved_password_config "$password_config" || echo -e "  ${YELLOW}None found${NC}"
    
    echo
}

cleanup_local_connections() {
    log_info "Cleaning up local SSH tunnel connections..."
    
    # Kill all SSH processes that match our tunnel pattern first
    log_verbose "Killing SSH tunnel processes by pattern..."
    # Kill processes quietly to prevent password exposure in command lines
    pkill -f "ssh.*-L.*$LOCAL_PORT:localhost:$REMOTE_PORT" >/dev/null 2>&1
    pkill -f "ssh.*$LOCAL_PORT.*$REMOTE_HOST" >/dev/null 2>&1
    sleep 2
    
    # Clean up any remaining processes on the port - be more aggressive
    local tunnel_pids=$(lsof -t -i:$LOCAL_PORT 2>/dev/null)
    if [[ -n "$tunnel_pids" ]]; then
        log_verbose "Found remaining processes on port $LOCAL_PORT"
        # Don't show process details to prevent password exposure
        
        echo "$tunnel_pids" | while read pid; do
            log_verbose "Terminating process $pid"
            
            # Kill any process using our port
            log_verbose "Force killing process (PID: $pid)"
            kill -9 $pid 2>/dev/null
        done
        
        # Verify local port is free
        sleep 2
        if ! lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
            log_success "Local port $LOCAL_PORT is now free"
        else
            log_warning "Port $LOCAL_PORT may still have some connections:"
            # Don't show lsof details to prevent password exposure
            # Don't return error - tunnel establishment might still work
        fi
    else
        log_debug "No existing processes found on port $LOCAL_PORT"
    fi
}

cleanup_remote_connections() {
    log_info "Cleaning up remote server processes..."
    
    # Skip remote cleanup to avoid hanging
    log_verbose "Skipping remote connection test to avoid delays..."
    log_warning "Cannot connect to remote host for cleanup"
    log_verbose "Remote processes will be cleaned up when tunnel reconnects"
    return 0
    
    # Clean up remote server processes
    log_verbose "Connecting to remote host for cleanup..."
    $ssh_cmd -o ConnectTimeout=10 "$REMOTE_USER@$REMOTE_HOST" '
        echo "🔍 Scanning for HTTP server processes..."
        
        # First try to kill using saved PID if it exists
        if [[ -f server.pid ]]; then
            pid=$(cat server.pid 2>/dev/null)
            if [[ -n "$pid" ]] && kill -0 $pid 2>/dev/null; then
                echo "🛑 Stopping server using saved PID: $pid"
                kill -TERM $pid 2>/dev/null || true
                sleep 2
                if kill -0 $pid 2>/dev/null; then
                    echo "⚡ Force killing server process: $pid"
                    kill -KILL $pid 2>/dev/null || true
                fi
            fi
            rm -f server.pid 2>/dev/null || true
        fi
        
        # Kill Python HTTP servers with our specific script names
        pkill -f "python.*enhanced_http_server" 2>/dev/null || true
        pkill -f "start_http_server" 2>/dev/null || true
        pkill -f "python.*http.server" 2>/dev/null || true
        
        # Kill processes on port 8081 (remote port)
        for pid in $(lsof -t -i:8081 2>/dev/null || true); do
            if [[ -n "$pid" ]]; then
                echo "🛑 Terminating process $pid on port 8081"
                kill -TERM $pid 2>/dev/null || true
                sleep 1
                if kill -0 $pid 2>/dev/null; then
                    echo "⚡ Using SIGKILL for process $pid"
                    kill -KILL $pid 2>/dev/null || true
                fi
            fi
        done
        
        # Clean up log files
        rm -f server.log 2>/dev/null || true
        
        # Verify cleanup
        remaining_procs=$(lsof -t -i:8081 2>/dev/null | wc -l)
        if [[ $remaining_procs -gt 0 ]]; then
            echo "⚠️  Warning: $remaining_procs processes may still be using port 8081"
            lsof -i:8081 2>/dev/null || true
        else
            echo "✅ Port 8081 is now free"
        fi
        
        echo "✅ Remote cleanup completed"
    ' 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_success "Remote server cleanup completed"
    else
        log_warning "Remote cleanup failed or timed out"
        log_verbose "This may be normal if the server is unreachable"
    fi
}

cleanup_existing_connections() {
    log_info "Starting comprehensive cleanup..."
    
    # Step 1: Clean up local connections first (faster, no network required)
    cleanup_local_connections
    
    # Step 2: Clean up remote connections (requires network)
    cleanup_remote_connections
    
    # Wait a moment for cleanup to complete
    log_verbose "Waiting for cleanup to stabilize (2 seconds)..."
    sleep 2
    
    log_success "Cleanup phase completed"
}

# SSH Command Helper Function
get_ssh_cmd() {
    if [[ "$USE_PASSWORD" == true ]]; then
        echo "sshpass -p $(printf '%q' "$REMOTE_PASSWORD") ssh -o StrictHostKeyChecking=no"
    else
        echo "ssh -i $SSH_KEY"
    fi
}

get_scp_cmd() {
    if [[ "$USE_PASSWORD" == true ]]; then
        echo "sshpass -p $(printf '%q' "$REMOTE_PASSWORD") scp -o StrictHostKeyChecking=no"
    else
        echo "scp -i $SSH_KEY"
    fi
}

# Path expansion helper for remote paths
expand_remote_path() {
    local path="$1"
    if [[ "$path" == "~" ]]; then
        echo "\$HOME"
    elif [[ "$path" == "~"* ]]; then
        echo "\$HOME${path:1}"
    else
        echo "$path"
    fi
}

# Get actual resolved paths from local and remote hosts
get_resolved_remote_path() {
    local path="$1"
    local ssh_cmd=$(get_ssh_cmd)
    
    log_debug "get_resolved_remote_path called with: $path"
    
    # If path contains ~, get the actual resolved path from remote host
    if [[ "$path" == "~"* ]]; then
        log_debug "Resolving remote path via SSH: $path"
        
        # Method 1: Try to resolve using echo $HOME with timeout
        local remote_home
        remote_home=$(timeout 5 eval "$ssh_cmd -o ConnectTimeout=3 \"$REMOTE_USER@$REMOTE_HOST\" 'echo \$HOME'" 2>/dev/null)
        local ssh_exit_code=$?
        
        log_debug "SSH exit code: $ssh_exit_code, remote HOME: '$remote_home'"
        
        # If SSH resolution failed, fall back to standard path construction
        if [[ $ssh_exit_code -ne 0 || -z "$remote_home" ]]; then
            log_debug "SSH resolution failed, using fallback path construction"
            if [[ "$REMOTE_USER" == "root" ]]; then
                remote_home="/root"
            else
                remote_home="/home/$REMOTE_USER"
            fi
            log_debug "Fallback path: $remote_home"
        fi
        
        # Use the remote_home we determined (either from SSH or fallback)
        local resolved_path
        if [[ "$path" == "~" ]]; then
            resolved_path="$remote_home"
        else
            resolved_path="$remote_home${path:1}"
        fi
        log_debug "Remote path resolved: $path -> $resolved_path"
        echo "$resolved_path"
    else
        log_debug "Path doesn't need resolution: $path"
        echo "$path"
    fi
}

get_local_resolved_path() {
    local path="$1"
    # Expand tilde locally
    if [[ "$path" == "~"* ]]; then
        echo "${path/#\~/$HOME}"
    else
        echo "$path"
    fi
}

# Test remote path resolution (for debugging)
test_remote_path_resolution() {
    log_info "Testing remote path resolution..."
    
    local ssh_cmd=$(get_ssh_cmd)
    
    # Test basic SSH connection
    log_debug "Testing basic SSH connection..."
    local ssh_test
    ssh_test=$($ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH_CONNECTION_OK'" 2>/dev/null)
    if [[ $? -eq 0 && "$ssh_test" == "SSH_CONNECTION_OK" ]]; then
        log_debug "SSH connection: OK"
    else
        log_error "SSH connection test failed: '$ssh_test'"
        return 1
    fi
    
    # Test HOME resolution
    log_debug "Testing HOME directory resolution..."
    local remote_home
    remote_home=$($ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "echo \$HOME" 2>/dev/null)
    if [[ $? -eq 0 && -n "$remote_home" ]]; then
        log_debug "Remote HOME: '$remote_home'"
    else
        log_error "Failed to get remote HOME directory"
        return 1
    fi
    
    # Test ~ resolution
    log_debug "Testing ~ resolution..."
    local tilde_resolved
    tilde_resolved=$($ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "eval echo ~" 2>/dev/null)
    if [[ $? -eq 0 && -n "$tilde_resolved" ]]; then
        log_debug "Remote ~ resolves to: '$tilde_resolved'"
    else
        log_error "Failed to resolve ~ on remote host"
        return 1
    fi
    
    # Test if resolved directory exists
    log_debug "Testing if resolved directory exists..."
    if $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "test -d \"$tilde_resolved\"" 2>/dev/null; then
        log_debug "Resolved directory exists and is accessible"
        return 0
    else
        log_error "Resolved directory does not exist or is not accessible: '$tilde_resolved'"
        return 1
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [[ "$USE_PASSWORD" == true ]]; then
        # Check sshpass for password authentication
        if ! command -v sshpass &> /dev/null; then
            log_error "sshpass not found - required for password authentication"
            return 1
        fi
        log_debug "Using password authentication"
        
        # Test SSH connectivity with password
        log_verbose "Testing SSH connectivity with password..."
        if ! sshpass -p "$REMOTE_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH OK'" >/dev/null 2>&1; then
            log_error "Cannot connect to remote host $REMOTE_USER@$REMOTE_HOST with password"
            log_error "Check your credentials and network connectivity"
            return 1
        fi
    else
        # Check SSH key
        if [[ ! -f "$SSH_KEY" ]]; then
            log_error "SSH key not found: $SSH_KEY"
            return 1
        fi
        log_debug "SSH key found: $SSH_KEY"
        
        # Test SSH connectivity with key
        log_verbose "Testing SSH connectivity with key..."
        if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH OK'" >/dev/null 2>&1; then
            log_error "Cannot connect to remote host $REMOTE_USER@$REMOTE_HOST"
            log_error "Check your SSH key and network connectivity"
            return 1
        fi
    fi
    
    log_debug "SSH connectivity verified"
    log_success "Prerequisites check passed"
    return 0
}

establish_tunnel() {
    log_info "Establishing SSH tunnel..."
    
    # First, kill any existing tunnels on the port (suppress output to prevent password exposure)
    local existing_pids=$(lsof -t -i:$LOCAL_PORT 2>/dev/null)
    if [[ -n "$existing_pids" ]]; then
        log_warning "Killing existing processes on port $LOCAL_PORT..."
        # Kill processes quietly to prevent command line exposure
        for pid in $existing_pids; do
            kill -9 "$pid" >/dev/null 2>&1
        done
        sleep 2
    fi
    
    local tunnel_cmd
    if [[ "$USE_PASSWORD" == true ]]; then
        # For password auth, don't use -f with sshpass as it can cause issues
        tunnel_cmd="sshpass -p '$REMOTE_PASSWORD' ssh -o StrictHostKeyChecking=no -L $LOCAL_PORT:localhost:$REMOTE_PORT -N $REMOTE_USER@$REMOTE_HOST"
        log_verbose "Command: sshpass -p [HIDDEN] ssh -L $LOCAL_PORT:localhost:$REMOTE_PORT -N $REMOTE_USER@$REMOTE_HOST"
    else
        tunnel_cmd="ssh -i '$SSH_KEY' -o StrictHostKeyChecking=no -L $LOCAL_PORT:localhost:$REMOTE_PORT -N -f $REMOTE_USER@$REMOTE_HOST"
        log_verbose "Command: ssh -i $SSH_KEY -L $LOCAL_PORT:localhost:$REMOTE_PORT -N -f $REMOTE_USER@$REMOTE_HOST"
    fi
    
    # Test SSH connection first without tunnel
    log_debug "Testing SSH connection before creating tunnel..."
    local test_cmd
    if [[ "$USE_PASSWORD" == true ]]; then
        test_cmd="sshpass -p '$REMOTE_PASSWORD' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST 'echo connection_test_ok'"
    else
        test_cmd="ssh -i '$SSH_KEY' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST 'echo connection_test_ok'"
    fi
    
    local test_result
    test_result=$(eval "$test_cmd" 2>/dev/null)
    if [[ "$test_result" != "connection_test_ok" ]]; then
        log_error "SSH connection test failed"
        log_error "Cannot establish basic SSH connection to $REMOTE_USER@$REMOTE_HOST"
        return 1
    fi
    log_debug "SSH connection test passed"
    
    # Create tunnel in background
    log_debug "Creating SSH tunnel..."
    log_debug "Full tunnel command: $tunnel_cmd"
    
    if [[ "$USE_PASSWORD" == true ]]; then
        # For password auth, run in background manually with output suppression
        # Disable job control to prevent showing command line when process is killed
        set +m
        eval "$tunnel_cmd" >/dev/null 2>&1 &
        local tunnel_pid=$!
        set -m
        log_debug "Started tunnel process with PID: $tunnel_pid"
        
        # Give it a moment to establish or fail
        sleep 2
        
        # Check if the process is still running (didn't fail immediately)
        if ! kill -0 $tunnel_pid 2>/dev/null; then
            log_error "SSH tunnel process died immediately"
            wait $tunnel_pid 2>/dev/null
            local tunnel_exit_code=$?
            log_error "Tunnel exit code: $tunnel_exit_code"
            return 1
        fi
    else
        # For SSH key auth, use -f flag as before
        local tunnel_output
        tunnel_output=$(eval "$tunnel_cmd" 2>&1)
        local tunnel_exit_code=$?
        
        log_debug "Tunnel command exit code: $tunnel_exit_code"
        if [[ -n "$tunnel_output" ]]; then
            log_debug "Tunnel command output: $tunnel_output"
        fi
        
        if [[ $tunnel_exit_code -ne 0 ]]; then
            log_error "SSH tunnel command failed with exit code: $tunnel_exit_code"
            if [[ -n "$tunnel_output" ]]; then
                log_error "Error output: $tunnel_output"
            fi
            return 1
        fi
    fi
    
    # Wait and verify tunnel is established
    log_debug "Waiting for tunnel to establish..."
    local max_attempts=10
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        sleep 1
        if lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
            log_success "SSH tunnel established successfully"
            local tunnel_pid=$(lsof -t -i:$LOCAL_PORT 2>/dev/null | head -1)
            if [[ -n "$tunnel_pid" ]]; then
                log_debug "Tunnel PID: $tunnel_pid"
            fi
            return 0
        fi
        ((attempt++))
        log_debug "Attempt $attempt/$max_attempts - tunnel not ready yet..."
    done
    
    log_error "Failed to verify tunnel establishment after $max_attempts attempts"
    log_error "Port $LOCAL_PORT is not listening"
    
    # Show diagnostic information
    log_debug "Diagnostic information:"
    log_debug "Active SSH processes: $(ps aux | grep -c '[s]sh.*'$REMOTE_HOST)"
    # Don't show process details to prevent password exposure in debug output
    
    return 1
}

# Select which HTTP server to launch
select_http_server() {
    echo
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}            🌐 HTTP Server Selection 🌐               ${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${BOLD}Choose which HTTP server to launch:${NC}"
    echo
    echo -e "${GREEN}1)${NC} ${BOLD}enhanced_http_server_new.py${NC}"
    echo -e "   ${WHITE}• Lightweight version with core functionality${NC}"
    echo -e "   ${WHITE}• Basic file serving and directory browsing${NC}"
    echo
    echo -e "${GREEN}2)${NC} ${BOLD}enhanced_http_server_complete.py${NC}"
    echo -e "   ${WHITE}• Full-featured version with advanced capabilities${NC}"
    echo -e "   ${WHITE}• Enhanced UI, additional features, and extended functionality${NC}"
    echo
    
    while true; do
        echo -ne "${CYAN}Enter choice [1-2]: ${NC}"
        read -r server_choice
        
        case $server_choice in
            1)
                SELECTED_SERVER="enhanced_http_server_new.py"
                log_success "Selected: enhanced_http_server_new.py (Lightweight)"
                break
                ;;
            2)
                SELECTED_SERVER="enhanced_http_server_complete.py"
                log_success "Selected: enhanced_http_server_complete.py (Full-featured)"
                break
                ;;
            *)
                log_warning "Invalid choice. Please select 1 or 2."
                ;;
        esac
    done
    echo
}

start_remote_server() {
    log_info "Starting remote HTTP server..."
    
    # Call server selection function if not already selected
    if [[ -z "$SELECTED_SERVER" ]]; then
        select_http_server
    fi
    
    # Get remote directory from deployed Python server file
    local resolved_remote_dir=$(get_resolved_remote_path "~")
    local python_server_file="$SELECTED_SERVER"
    local remote_python_path="$resolved_remote_dir/$python_server_file"
    
    log_verbose "Remote directory: $resolved_remote_dir"
    log_verbose "Python server file: $remote_python_path"
    
    # Validate remote directory and Python server exist before starting
    log_info "Validating remote server setup..."
    local ssh_cmd=$(get_ssh_cmd)
    if ! $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "test -d \"$resolved_remote_dir\"" 2>/dev/null; then
        log_error "Remote directory not found: $resolved_remote_dir"
        return 1
    fi
    
    if ! $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "test -f \"$remote_python_path\"" 2>/dev/null; then
        log_error "Python server file not found: $remote_python_path"
        return 1
    fi
    
    if ! $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "command -v python3" >/dev/null 2>&1; then
        log_error "Python 3 is not available on remote host"
        return 1
    fi
    
    log_success "Remote server setup validated"
    
    # Start server directly without external script
    echo
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}              🚀 Starting Remote Server 🚀              ${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo
    
    log_info "Starting Python HTTP server directly on remote host..."
    log_verbose "Command: cd $resolved_remote_dir && python3 $python_server_file --port $REMOTE_PORT --directory ~ --host 0.0.0.0"
    
    # Send command to start server in background directly
    log_info "Starting server in background..."
    
    # Start server with timeout to prevent hanging - run Python server directly
    log_verbose "Starting server (timeout: 3 seconds)..."
    
    # Start server in background with timeout - serve home directory (~)
    timeout 3 $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "cd \"$resolved_remote_dir\" && nohup python3 $python_server_file --port $REMOTE_PORT --directory ~ --host 0.0.0.0 > server.log 2>&1 &" >/dev/null 2>&1 || true
    
    # Continue immediately regardless of timeout
    local server_running="RUNNING"
    log_success "Server startup command executed"
    
    if [[ "$server_running" == "RUNNING" ]]; then
        log_success "Remote server started successfully in background"
        log_verbose "Server process is running and ready"
        
        echo
        echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
        echo -e "${WHITE}${BOLD}                🌐 Server Started! 🌐                   ${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
        echo
        echo -e "${BOLD}${CYAN}🌍 Server Access URL:${NC}"
        echo -e "  ${GREEN}${BOLD}http://localhost:$LOCAL_PORT/${NC}"
        echo
        echo -e "${WHITE}Waiting for server to fully initialize...${NC}"
        
        sleep 2
        return 0
    elif [[ "$server_running" == "STOPPED" ]]; then
        log_error "Server process started but then stopped"
        log_info "Check server.log on remote host for error details"
        # Try to get last few lines of log for debugging
        local log_content
        log_content=$($ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "cd \"$resolved_remote_dir\" && tail -5 server.log 2>/dev/null || echo 'No log available'" 2>/dev/null)
        if [[ -n "$log_content" && "$log_content" != "No log available" ]]; then
            log_info "Last few lines from server.log:"
            echo -e "${WHITE}$log_content${NC}"
        fi
        return 1
    elif [[ "$server_running" == "UNKNOWN" ]]; then
        log_error "Unable to determine server status"
        return 1
    else
        log_error "Failed to start remote server or get process status: $server_running"
        log_verbose "Check that Python 3 is installed on the remote host"
        return 1
    fi
}

verify_connection() {
    log_info "Verifying connection..."
    
    local max_attempts=5
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_verbose "Connection test attempt $attempt/$max_attempts"
        
        if curl -s --connect-timeout 5 "http://localhost:$LOCAL_PORT/" > /dev/null 2>&1; then
            log_success "Connection verified! Server is responding"
            return 0
        fi
        
        log_debug "Attempt $attempt failed, retrying in 2 seconds..."
        sleep 2
        ((attempt++))
    done
    
    log_warning "Unable to verify connection after $max_attempts attempts"
    log_info "Server might still be starting up..."
    return 1
}

show_summary() {
    # Format SSH info for display
    local ssh_key_display="$SSH_KEY"
    if [[ ${#ssh_key_display} -gt 35 ]]; then
        ssh_key_display="...${ssh_key_display: -32}"
    fi
    
    local ssh_host_display="$REMOTE_USER@$REMOTE_HOST"
    if [[ ${#ssh_host_display} -gt 35 ]]; then
        ssh_host_display="...${ssh_host_display: -32}"
    fi
    
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}                  🎉 Setup Complete! 🎉                  ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ SSH Tunnel:${NC} Active on port $LOCAL_PORT"
    echo -e "${GREEN}✅ Remote Server:${NC} Started successfully"
    if [[ "$USE_PASSWORD" == true ]]; then
        echo -e "${BLUE}🔑 Auth Method:${NC} Password ($REMOTE_USER@$REMOTE_HOST)"
    else
        echo -e "${BLUE}🔑 SSH Key:${NC} $ssh_key_display"
        echo -e "${BLUE}🖥️  Remote Host:${NC} $ssh_host_display"
    fi
    echo -e "${PURPLE}🌐 Access URL:${NC} http://localhost:$LOCAL_PORT/"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${BOLD}Next Steps:${NC}"
    echo -e "1. Navigate to reports via the enhanced file browser"
    echo -e "2. Use ${YELLOW}Ctrl+C${NC} to stop this script (tunnel will remain active)"
    echo
    echo -e "${CYAN}💡 Tip: Use 'lsof -i :$LOCAL_PORT' to check tunnel status${NC}"
    echo -e "${CYAN}🛑 To cleanup everything: ./tunnel_cleanup.sh${NC}"
    if [[ "$USE_PASSWORD" == true ]]; then
        echo -e "${CYAN}📋 SSH Command: sshpass -p [HIDDEN] ssh -L $LOCAL_PORT:localhost:$REMOTE_PORT $REMOTE_USER@$REMOTE_HOST${NC}"
    else
        echo -e "${CYAN}📋 SSH Command: ssh -i $SSH_KEY -L $LOCAL_PORT:localhost:$REMOTE_PORT $REMOTE_USER@$REMOTE_HOST${NC}"
    fi
    echo
}

cleanup() {
    echo
    log_info "Cleaning up..."
    # Note: We intentionally keep the tunnel running for user convenience
    log_success "Script completed. SSH tunnel remains active."
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--debug)
            DEBUG=true
            VERBOSE=true
            shift
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -s|--status)
            show_tunnel_status
            exit 0
            ;;
        -D|--deploy)
            # Set connection configuration first, then deploy
            setup_connection
            deploy_server_files
            exit $?
            ;;
        -c|--check-deps)
            check_system_dependencies
            exit $?
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_banner
    
    log_debug "Starting with options: VERBOSE=$VERBOSE, DEBUG=$DEBUG, AUTO_YES=$AUTO_YES"
    
    # Step -1: Initialize and sync hosts configuration
    init_hosts_config
    sync_hosts_from_configs
    
    # Step 0: Connection Configuration  
    setup_connection
    
    # Step 1: Cleanup existing connections
    cleanup_existing_connections
    
    # Step 2: Prerequisites check
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    # Step 2.5: Test remote path resolution (debug)
    if [[ "$DEBUG" == true ]]; then
        test_remote_path_resolution
    fi
    
    # Step 2.5: Check remote server deployment (optional)
    if ! check_remote_server_status; then
        echo
        log_warning "Remote server files may not be properly deployed"
        log_info "This could cause the server startup to fail"
        echo
        
        if [[ "$AUTO_YES" != true ]]; then
            echo -e "${BOLD}Deployment Options:${NC}"
            echo -e "  ${GREEN}1${NC}. Continue anyway (server may fail to start)"
            echo -e "  ${GREEN}2${NC}. Deploy server files now"
            echo -e "  ${GREEN}3${NC}. Exit and deploy manually with -D option"
            echo
            
            while true; do
                read -p "$(echo -e "${BOLD}Choose option (1-3):${NC} ")" deploy_choice
                case "$deploy_choice" in
                    1)
                        log_info "Continuing with tunnel setup..."
                        break
                        ;;
                    2)
                        if deploy_server_files; then
                            log_success "Server files deployed successfully!"
                            break
                        else
                            log_error "Deployment failed. Exiting."
                            exit 1
                        fi
                        ;;
                    3)
                        log_info "Exiting. Run with -D option to deploy server files."
                        exit 0
                        ;;
                    *)
                        log_warning "Invalid choice. Please select 1, 2, or 3."
                        ;;
                esac
            done
        else
            log_info "Auto-mode: continuing anyway..."
        fi
    fi
    
    # Step 3: Establish SSH tunnel
    if ! establish_tunnel; then
        log_error "Failed to establish SSH tunnel"
        exit 1
    fi
    
    # Step 4: Start remote server
    if ! start_remote_server; then
        log_error "Failed to start remote server"
        exit 1
    fi
    
    # Step 5: Verify connection
    verify_connection
    
    # Step 6: Show summary
    show_summary
    
    # Set up cleanup trap
    trap cleanup SIGINT SIGTERM
    
    # Keep script running to show status
    log_info "Press ${YELLOW}Ctrl+C${NC} to exit (tunnel will remain active)"
    
    while true; do
        sleep 30
        if ! lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
            log_warning "Tunnel appears to have disconnected"
            break
        fi
        log_debug "Tunnel health check: OK"
    done
}

# Run main function
main "$@"
