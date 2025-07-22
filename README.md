                                                                                  
# Program developed by Gustavo Wydler Azuaga - 2025-07-22

# Remote Enhanced File Server

- A comprehensive bash script that automates SSH tunnel creation
- Remote HTTP server deployment with advanced authentication management.

## Features

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
```

## Files

### Core Files
- `tunnel_launcher.sh` - **Main script** - Primary executable that handles all functionality
- `enhanced_http_server_new.py` - Python HTTP server with advanced file browsing capabilities
- `start_http_server.sh` - Server launcher script deployed to remote hosts

### Configuration Files (Auto-created)
- `~/.tunnel_configs/ssh_configs.json` - Saved SSH key configurations
- `~/.tunnel_configs/password_configs.json` - Saved password configurations

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

### Basic Usage
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
1. **Use SSH Key Authentication** - Connect with existing SSH keys
2. **Use Password Authentication** - Connect with username/password
3. **Save new SSH key configuration** - Store SSH connection details
4. **Save new password configuration** - Store password connection details
5. **List and select saved configurations** - Choose from saved connections
6. **Remove saved configuration** - Delete unwanted configurations

### Configuration Storage
- SSH configurations: `~/.tunnel_configs/ssh_configs.json`
- Password configurations: `~/.tunnel_configs/password_configs.json`
- Files are created automatically with proper permissions (600)

## Connection Flow

1. **Configuration Selection** - Choose or create connection settings
2. **System Cleanup** - Clear any existing tunnel connections
3. **Prerequisites Check** - Verify SSH connectivity and credentials
4. **File Deployment** - Transfer server files to remote host (if needed)
5. **Tunnel Establishment** - Create SSH tunnel (local port 8081 → remote port 8081)
6. **Server Startup** - Launch HTTP server on remote host
7. **Access Ready** - Connect via `http://localhost:8081/`

## Server Features

The deployed HTTP server provides:
- **File Browser Interface** - Navigate remote file system
- **Download Capabilities** - Download files and directories
- **Upload Support** - Upload files to remote host
- **Search Functionality** - Find files by name or content
- **Directory Operations** - Create, delete, rename directories

## Example Workflows

### First Time Setup
```bash
# 1. Clone and navigate to repository
git clone https://github.com/your-username/remote_enhanced_file_server.git
cd remote_enhanced_file_server

# 2. Run the script
./tunnel_launcher.sh

# 3. Choose option 4 to save new password configuration
# 4. Enter connection details and credentials
# 5. Configuration is saved for future use
```

### Using Saved Configuration
```bash
# 1. Navigate to repository directory
cd remote_enhanced_file_server

# 2. Run the script with verbose output
./tunnel_launcher.sh -v

# 3. Choose option 5 to select saved configuration
# 4. Pick your saved connection
# 5. Script automatically connects and deploys
```

### Removing Old Configurations
```bash
# 1. Navigate to repository directory
cd remote_enhanced_file_server

# 2. Run the script
./tunnel_launcher.sh

# 3. Choose option 6 to remove configuration
# 4. Select configuration to delete
# 5. Confirm deletion with 'yes'
```

## Troubleshooting

### Common Issues
- **Permission denied**: Ensure SSH keys have correct permissions (600)
- **sshpass not found**: Install sshpass package for password authentication
- **Connection timeout**: Check network connectivity and firewall settings
- **Port already in use**: Kill existing tunnels with `lsof -ti :8081 | xargs kill`

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

# Remove configuration files
rm -rf ~/.tunnel_configs/
```

## Security Notes

- SSH keys should have 600 permissions
- Password configurations are stored in plain text in local files with 600 permissions
- Configuration directory `~/.tunnel_configs/` is created with 700 permissions
- Always use strong passwords and keep configuration files secure

## Access

Once tunnel is established, access the remote file browser at:
```
http://localhost:8081/
```

The tunnel remains active even after the script exits, allowing continued access to the remote server.

## Directory Structure

```
remote_enhanced_file_server/
├── tunnel_launcher.sh              # Main executable script
├── enhanced_http_server_new.py     # HTTP server implementation
├── start_http_server.sh            # Remote server launcher
├── tunnel_cleanup.sh               # Cleanup utility
└── README.md                       # This file
```
                                                                                        

