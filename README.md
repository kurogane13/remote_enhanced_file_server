# Program developed by Gustavo Wydler Azuaga - 2025-07-22

# Remote Enhanced File Server

- A comprehensive bash script that automates SSH tunnel creation
- Remote HTTP server deployment with advanced authentication management.

## Features

### 🆕 **Latest Updates (2025)**
- **🧹 Integrated Cleanup System**: Complete tunnel and remote server cleanup directly from main menu (Option 2)
- **🏠 Dynamic Host Management**: Automatic IP synchronization from configurations with plain text storage
- **🎨 Enhanced UI**: Bright, high-contrast colors for improved readability across all interfaces
- **⚡ Improved Menu Structure**: Reorganized authentication options for better workflow
- **🔧 Robust Error Handling**: Better connection testing and step-by-step cleanup processes

### Core Functionality
- **Dual Authentication Support**: SSH keys and password authentication
- **Configuration Management**: Save, select, and delete connection configurations
- **SSH Tunnel Management**: Establishes and manages SSH tunnels automatically
- **Remote Server Control**: Starts HTTP file browser on remote systems
- **Cross-Platform Support**: Works on any Linux distribution

## Installation

### Clone Repository
```bash
git clone https://github.com/your-username/remote_enhanced_file_server.git
cd remote_enhanced_file_server
```

### Make Script Executable
```bash
chmod +x tunnel_launcher.sh
chmod +x remote_python_servers_selector.sh
```

## Files

### Core Files
- `tunnel_launcher.sh` - **Main script** - Primary executable that handles all functionality including integrated cleanup system and direct server startup
- `enhanced_http_server_complete.py` - **Complete HTTP server** - Full-featured server with video previews, system information, and enhanced UI
- `enhanced_http_server_new.py` - **Enhanced HTTP server** - Modern server with advanced file browsing capabilities  
- `remote_python_servers_selector.sh` - **Local server selector** - Interactive menu to launch either server locally

### Configuration Files (Auto-created)
- `~/.tunnel_configs/ssh_keys.json` - Saved SSH key configurations
- `~/.tunnel_configs/passwords.json` - Saved password configurations
- `~/.tunnel_configs/remote_hosts.conf` - Dynamic host management file

## HTTP Server Variants

### Enhanced HTTP Server Complete (`enhanced_http_server_complete.py`)

The **complete** server is a full-featured HTTP file browser with advanced capabilities:

#### 🎥 **Video Features**
- **60-second hover previews** - Preview videos by hovering over thumbnails
- **Click-to-play** - Full video playback in new tabs
- **Video metadata display** - File size, modification date, permissions
- **Dedicated download system** - Recursive file search for reliable downloads

#### 🖥️ **System Information Dashboard**
- **6 color-coded categories**:
  - 🏷️ **System Identity** - Hostname, FQDN, OS details
  - ⚙️ **Kernel Information** - Version, release, architecture
  - 🌐 **Network Details** - IP address, MAC address, interface info
  - 🔧 **CPU Details** - Cores, threads, cache size, model
  - 💾 **Memory Information** - Total, used, available, cached, buffers
  - ⏰ **Time & Status** - Current time, boot time, uptime, load average

#### 📊 **Enhanced Directory Statistics**
- **Colorful card-based layout** with hover effects
- **Individual statistics cards** for each file type:
  - 📁 Directories (green theme)
  - 🎥 Videos (red theme)
  - 🖼️ Images (blue theme)
  - 📄 Other Files (purple theme)
  - 💾 Total Size (yellow theme)
- **Interactive elements** with smooth animations
- **Permission indicators** and access status

#### 📁 **Advanced Directory Listing**
- **Enhanced directory cards** with detailed information
- **File count per directory** (when accessible)
- **Age-based color coding** (recent files in green, old files in red)
- **Permission badges** (Read/Write indicators)
- **Responsive grid layout** that adapts to screen size

#### 📄 **Smart File Management**
- **Extension-based color coding** for different file types
- **Size category indicators** with color-coded file sizes
- **Interactive file cards** with hover effects and shadows
- **Action buttons** for view and download operations

### Enhanced HTTP Server New (`enhanced_http_server_new.py`)

The **new** server provides modern file browsing with:
- **Clean, modern interface** with responsive design
- **Advanced file categorization** by type and extension
- **Network interface detection** for local and network access
- **Comprehensive system information** display
- **Enhanced styling** with color-coded sections

## Local Server Usage (Without Tunnel)

Both HTTP servers can be run **locally** without the tunnel launcher for direct access to your local file system.

### Interactive Menu Selector

Use the colorful menu selector to choose between servers:

```bash
# Run the interactive server selector
./remote_python_servers_selector.sh
```

#### Menu Features:
- 🎨 **Colorful interface** with cyan, green, yellow themes
- 📊 **Server status indicators** (Ready/Not Available)
- 🔍 **Verbose logging** and debugging output
- 🌐 **Network information** display (IP address, port checking)
- ⚠️ **Error handling** with graceful exits
- 🛡️ **Ctrl+C handling** - Returns to menu instead of exiting

### Direct Server Launch

#### Launch Complete Server Directly:
```bash
# Default (serves current directory on port 8081)
python3 enhanced_http_server_complete.py

# Custom directory and port
python3 enhanced_http_server_complete.py --directory /path/to/serve --port 8080

# Network access (binds to all interfaces)
python3 enhanced_http_server_complete.py --host auto
```

#### Launch New Server Directly:
```bash
# Default configuration
python3 enhanced_http_server_new.py

# Custom port
python3 enhanced_http_server_new.py --port 8080

# Custom directory
python3 enhanced_http_server_new.py --directory /home/user/Documents
```

### Local Access URLs

Once running locally, access the servers at:
- **Local access**: `http://localhost:8081/`
- **Network access**: `http://[your-ip]:8081/` (when using --host auto)

### Desktop Launcher

A desktop launcher is also available for easy access:
- **Location**: `~/Desktop/Desktop-Launchers/python_remote_servers.desktop`
- **System menu**: Available in application launcher
- **Right-click actions**: Direct access to each server

## Requirements

### System Dependencies
```bash
# Required packages (install via package manager)
ssh                 # SSH client
scp                 # Secure copy
sshpass             # Password-based SSH authentication
curl                # HTTP client for testing
lsof                # Network port monitoring
python3             # Python interpreter
```

### Installation Commands

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install openssh-client sshpass curl lsof python3
```

**CentOS/RHEL/Fedora:**
```bash
sudo yum install openssh-clients sshpass curl lsof python3
# OR (newer versions)
sudo dnf install openssh-clients sshpass curl lsof python3
```

**Alpine Linux:**
```bash
sudo apk add openssh-client sshpass curl lsof python3
```

## Usage

### Remote Tunnel Usage
```bash
# Navigate to cloned directory
cd remote_enhanced_file_server

# Run with default options
./tunnel_launcher.sh

# Run with verbose output
./tunnel_launcher.sh -v

# Run with debug information
./tunnel_launcher.sh -d

# Deploy server files only
./tunnel_launcher.sh -D

# Check system dependencies
./tunnel_launcher.sh -c
```

### Command Line Options
```
-v, --verbose     Enable verbose output
-d, --debug       Enable debug mode
-y, --yes         Auto-confirm all prompts
-s, --status      Show tunnel status and exit
-D, --deploy      Deploy server files to remote host
-c, --check-deps  Check system dependencies
-h, --help        Show help message
```

## Configuration Management

### Authentication Options
1. **List/Run tunnel launcher with saved ssh keys/password configurations** - Connect using previously saved configurations
2. **Run created tunnels and used ports cleanup** - Integrated cleanup system for tunnels and remote servers
3. **Save new SSH key configuration** - Store SSH connection details for reuse
4. **Save new password configuration** - Store password connection details for reuse
5. **Remove ssh keys/ssh passwords saved configurations** - Delete unwanted configurations
6. **Saved ssh keys/ssh password IPs configurations** - Manage host configurations and view saved IPs

## 🧹 Integrated Cleanup System

The tunnel launcher now includes a comprehensive cleanup system accessible via **Option 2** in the main menu. This eliminates the need for a separate cleanup script.

### Cleanup Features
- **Local Tunnel Cleanup** - Terminates SSH tunnel processes on port 8081
- **Remote Server Cleanup** - Kills HTTP server processes on remote hosts
- **Individual Host Cleanup** - Select specific hosts for targeted cleanup
- **Bulk Cleanup** - Clean all configured hosts simultaneously
- **Multi-Authentication Support** - Works with both SSH keys and password authentication

### Cleanup Options
- **[0] Clean up ALL configured hosts** - Comprehensive cleanup across all saved configurations
- **[1-N] Individual Host Selection** - Target specific hosts for cleanup
- **[b] Back to main menu** - Return without performing cleanup

### Cleanup Process
1. **Local SSH Tunnel Termination** - Kills processes using local port 8081
2. **Remote Process Detection** - Identifies Python HTTP servers and port-bound processes
3. **Graceful Termination** - Uses SIGTERM followed by SIGKILL if necessary
4. **Verification** - Confirms successful cleanup and reports results
5. **Status Reporting** - Provides summary of cleanup operations

### Cleanup Commands Executed
- Kill Python HTTP servers: `pkill -f python.*enhanced_http_server`
- Kill server launchers: `pkill -f start_http_server`
- Kill generic HTTP servers: `pkill -f "python.*http.server"`
- Kill processes on port 8081: Uses `lsof` or `netstat` for process identification

## 🏠 Dynamic Host Management System

The tunnel launcher includes an advanced host management system that automatically syncs IP addresses from saved configurations.

### Host Management Features
- **Automatic IP Synchronization** - Extracts unique IPs from SSH key and password configurations
- **Plain Text Storage** - Hosts stored in `remote_hosts.conf` for easy management
- **Bidirectional Sync** - JSON configurations and hosts file stay synchronized
- **Configuration Validation** - Ensures only IPs with valid authentication configs are shown
- **Duplicate Prevention** - Automatic deduplication of IP addresses
- **Section Organization** - Groups hosts by authentication type (SSH KEY/SSH PASSWORD)

### Host File Structure
```
# SSH KEY saved connections IPS

52.89.199.207

# SSH PASSWORD saved connections IPS

192.168.0.123
192.168.0.144
192.168.0.65
```

### Host Management Options
- **Add New Configurations** - Create SSH key or password configurations for new hosts
- **Remove Configurations** - Delete specific configurations without affecting other configs for the same IP
- **List Configurations** - View all saved configurations with authentication details
- **Automatic Cleanup** - Remove hosts without valid configurations from the hosts file

## 🎨 Enhanced User Interface

### Color-Coded Display
- **Bright Green** - SSH key paths and important file locations
- **White** - User information and configuration details
- **Cyan** - Tips, commands, and helpful information
- **Yellow** - Warning messages and "no configuration found" alerts
- **Red** - Error messages and critical alerts

### Improved Visibility
- **Eliminated Dark Colors** - All gray and dark colors replaced with bright, readable alternatives
- **High Contrast** - Enhanced readability in all terminal environments
- **Consistent Theming** - Unified color scheme across all functions and menus

### Configuration Storage
- SSH configurations: `~/.tunnel_configs/ssh_keys.json`
- Password configurations: `~/.tunnel_configs/passwords.json`
- Host management: `~/.tunnel_configs/remote_hosts.conf`
- Files are created automatically with proper permissions (600 for JSON files, 700 for directory)

## Connection Flow

1. **Configuration Selection** - Choose or create connection settings
2. **System Cleanup** - Clear any existing tunnel connections
3. **Prerequisites Check** - Verify SSH connectivity and credentials
4. **File Deployment** - Transfer server files to remote host (if needed)
5. **Tunnel Establishment** - Create SSH tunnel (local port 8081 → remote port 8081)
6. **Server Startup** - Launch HTTP server on remote host
7. **Access Ready** - Connect via `http://localhost:8081/`

## Server Features

The deployed HTTP servers provide:
- **File Browser Interface** - Navigate remote or local file system
- **Video Preview Capabilities** - Hover previews and full playback (complete server)
- **System Information Dashboard** - Comprehensive system details display
- **Download Capabilities** - Download files and directories
- **Enhanced Directory Statistics** - Visual file type breakdowns
- **Search Functionality** - Find files by name or content
- **Directory Operations** - Create, delete, rename directories

## Example Workflows

### Local Server Usage
```bash
# 1. Navigate to repository directory
cd remote_enhanced_file_server

# 2. Use interactive menu
./remote_python_servers_selector.sh

# 3. Choose option 1 or 2 to launch desired server
# 4. Access via http://localhost:8081/

# OR run directly:
python3 enhanced_http_server_complete.py --directory ~/Videos
```

### First Time Remote Setup
```bash
# 1. Clone and navigate to repository
git clone https://github.com/your-username/remote_enhanced_file_server.git
cd remote_enhanced_file_server

# 2. Run the tunnel script
./tunnel_launcher.sh

# 3. Choose option 4 to save new password configuration
# 4. Enter connection details and credentials
# 5. Configuration is saved for future use
```

### Using Saved Remote Configuration
```bash
# 1. Navigate to repository directory
cd remote_enhanced_file_server

# 2. Run the script with verbose output
./tunnel_launcher.sh -v

# 3. Choose option 1 to use saved configuration
# 4. Pick your saved connection
# 5. Script automatically connects and deploys
```

## Troubleshooting

### Common Issues
- **Permission denied**: Ensure SSH keys have correct permissions (600)
- **sshpass not found**: Install sshpass package for password authentication
- **Connection timeout**: Check network connectivity and firewall settings
- **Port already in use**: Kill existing tunnels with `lsof -ti :8081 | xargs kill`
- **Firewall blocking**: Ensure port 8081 is open: `sudo ufw allow 8081`

### Debug Information
Run with `-d` flag for detailed debug output:
```bash
cd remote_enhanced_file_server
./tunnel_launcher.sh -d
```

### Manual Cleanup
```bash
# Kill SSH tunnels
pkill -f "ssh.*-L.*8081"

# Check active tunnels
lsof -i :8081

# Remove configuration files (if needed)
rm -rf ~/.tunnel_configs/

# Use integrated cleanup (recommended)
./tunnel_launcher.sh
# Then select option 2 for cleanup
```

## Security Notes

- SSH keys should have 600 permissions
- Password configurations are stored in plain text in local files with 600 permissions
- Configuration directory `~/.tunnel_configs/` is created with 700 permissions
- Always use strong passwords and keep configuration files secure
- Local servers bind to all interfaces when using `--host auto` - ensure firewall is configured

## Access

### Remote Access (via tunnel)
Once tunnel is established, access the remote file browser at:
```
http://localhost:8081/
```

### Local Access
When running servers locally:
- **Local only**: `http://localhost:8081/`
- **Network access**: `http://[your-ip]:8081/` (with --host auto)

The tunnel remains active even after the script exits, allowing continued access to the remote server.

## Directory Structure

```
remote_enhanced_file_server/
├── tunnel_launcher.sh                    # Main tunnel executable script with integrated cleanup and direct server startup
├── enhanced_http_server_complete.py     # Complete HTTP server with video previews
├── enhanced_http_server_new.py          # Enhanced HTTP server implementation
├── remote_python_servers_selector.sh    # Local server selection menu
├── python_remote_servers.desktop        # Desktop launcher file
└── README.md                            # This file

~/.tunnel_configs/                       # Auto-created configuration directory
├── ssh_keys.json                        # SSH key configurations
├── passwords.json                       # Password configurations
└── remote_hosts.conf                    # Dynamic host management file
```
