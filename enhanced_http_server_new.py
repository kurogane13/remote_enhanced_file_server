#!/usr/bin/env python3

"""
Remote Advanced File Browser
A comprehensive HTTP server for browsing, filtering, and downloading files
"""

import http.server
import socketserver
import os
import sys
import json
from urllib.parse import unquote, urlparse, quote
import mimetypes
import time
from collections import defaultdict
import platform
import socket
import subprocess
import uuid
import datetime
import threading
import hashlib
from http.server import ThreadingHTTPServer

class RemoteFileServerHandler(http.server.SimpleHTTPRequestHandler):
    """Enhanced HTTP handler with complete navigation and file information"""
    
    video_extensions = ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.mpeg', '.mpg', '.m4v', '.3gp', '.ogv']
    image_extensions = ['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.svg', '.webp', '.ico']
    
    def __init__(self, *args, **kwargs):
        # Setup comprehensive MIME types
        mimetypes.add_type('text/html', '.html')
        mimetypes.add_type('text/html', '.htm')
        mimetypes.add_type('text/css', '.css')
        mimetypes.add_type('application/javascript', '.js')
        mimetypes.add_type('application/json', '.json')
        
        # Video MIME types
        for ext in self.video_extensions:
            if ext == '.mp4' or ext == '.m4v':
                mimetypes.add_type('video/mp4', ext)
            elif ext == '.webm':
                mimetypes.add_type('video/webm', ext)
            elif ext == '.ogg' or ext == '.ogv':
                mimetypes.add_type('video/ogg', ext)
            elif ext == '.avi':
                mimetypes.add_type('video/x-msvideo', ext)
            elif ext == '.mov':
                mimetypes.add_type('video/quicktime', ext)
            elif ext == '.wmv':
                mimetypes.add_type('video/x-ms-wmv', ext)
            elif ext == '.flv':
                mimetypes.add_type('video/x-flv', ext)
            elif ext == '.mkv':
                mimetypes.add_type('video/x-matroska', ext)
            elif ext == '.3gp':
                mimetypes.add_type('video/3gpp', ext)
            elif ext in ['.mpeg', '.mpg']:
                mimetypes.add_type('video/mpeg', ext)
        
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        """Handle GET requests with enhanced navigation"""
        try:
            # Handle API requests
            if self.path.startswith('/api/'):
                self.handle_api_request()
                return
            
            # Handle download requests
            if self.path.startswith('/download/'):
                self.handle_dedicated_download()
                return
            
            # Handle video play requests
            if self.path.startswith('/play/'):
                self.handle_video_play()
                return
            
            # Parse path for navigation
            parsed_path = urlparse(self.path)
            path = unquote(parsed_path.path)
            
            # Handle directory navigation
            if path == '/' or path.endswith('/'):
                self.generate_enhanced_directory_listing(path)
            else:
                # Handle file requests
                super().do_GET()
                
        except Exception as e:
            print(f"❌ Error in do_GET: {e}")
            try:
                self.send_error(500, "Internal server error")
            except:
                pass
    
    def end_headers(self):
        # Set proper content types and headers
        if self.path.endswith(('.html', '.htm')):
            self.send_header('Content-Type', 'text/html; charset=utf-8')
        elif self.path.endswith('.css'):
            self.send_header('Content-Type', 'text/css; charset=utf-8')
        elif self.path.endswith('.js'):
            self.send_header('Content-Type', 'application/javascript; charset=utf-8')
        elif self.path.endswith('.json'):
            self.send_header('Content-Type', 'application/json; charset=utf-8')
        elif self.path.endswith(('.mp4', '.m4v')):
            self.send_header('Content-Type', 'video/mp4')
        elif self.path.endswith('.webm'):
            self.send_header('Content-Type', 'video/webm')
        elif self.path.endswith(('.ogg', '.ogv')):
            self.send_header('Content-Type', 'video/ogg')
        elif self.path.endswith('.avi'):
            self.send_header('Content-Type', 'video/x-msvideo')
        elif self.path.endswith('.mov'):
            self.send_header('Content-Type', 'video/quicktime')
        elif self.path.endswith('.wmv'):
            self.send_header('Content-Type', 'video/x-ms-wmv')
        elif self.path.endswith('.flv'):
            self.send_header('Content-Type', 'video/x-flv')
        elif self.path.endswith('.mkv'):
            self.send_header('Content-Type', 'video/x-matroska')
        elif self.path.endswith('.3gp'):
            self.send_header('Content-Type', 'video/3gpp')
        elif self.path.endswith(('.mpeg', '.mpg')):
            self.send_header('Content-Type', 'video/mpeg')
        
        # Add range request support for video files
        if self.path.endswith(('.mp4', '.webm', '.ogg', '.ogv', '.avi', '.mov', '.wmv', '.flv', '.mkv', '.3gp', '.mpeg', '.mpg', '.m4v')):
            self.send_header('Accept-Ranges', 'bytes')
        
        # Prevent aggressive caching for HTML, but allow video caching
        if not self.path.endswith(('.mp4', '.webm', '.ogg', '.ogv', '.avi', '.mov', '.wmv', '.flv', '.mkv', '.3gp', '.mpeg', '.mpg', '.m4v')):
            self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Expires', '0')
        
        super().end_headers()
    
    def log_message(self, format, *args):
        """Custom logging"""
        timestamp = time.strftime('%H:%M:%S')
        print(f"[{timestamp}] {format % args}")

    def find_file_by_name(self, filename):
        """Find a file by name starting from the current directory tree"""
        try:
            current_dir = os.getcwd()
            print(f"🔍 Searching for '{filename}' starting from: {current_dir}")
            
            # First check the current directory directly
            direct_path = os.path.join(current_dir, filename)
            if os.path.exists(direct_path):
                return direct_path
            
            # Then search all subdirectories recursively
            for root, dirs, files in os.walk(current_dir):
                if filename in files:
                    found_path = os.path.join(root, filename)
                    return found_path
        except Exception as e:
            print(f"❌ Error in file search for '{filename}': {e}")
            return None
        
        print(f"❌ File '{filename}' not found anywhere")
        return None

    def handle_api_request(self):
        """Handle API requests"""
        try:
            if self.path == '/api/system':
                system_info = self.get_system_info()
                response = json.dumps(system_info, indent=2)
                
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(response.encode('utf-8'))))
                self.end_headers()
                self.wfile.write(response.encode('utf-8'))
            else:
                self.send_error(404, "API endpoint not found")
        except Exception as e:
            print(f"❌ API request error: {e}")
            self.send_error(500, "Internal server error")

    def handle_dedicated_download(self):
        """Handle dedicated download requests using file search"""
        try:
            # Extract filename from /download/filename
            filename = unquote(self.path[10:])  # Remove '/download/' prefix
            print(f"🔍 Download request for: '{filename}'")
            
            # Find the file using recursive search
            file_path = self.find_file_by_name(filename)
            
            if not file_path or not os.path.exists(file_path):
                print(f"❌ File not found: {filename}")
                self.send_error(404, f"File '{filename}' not found")
                return
            
            print(f"✅ Found file: {file_path}")
            
            # Get file info
            file_size = os.path.getsize(file_path)
            
            # Send file
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
            self.send_header('Content-Length', str(file_size))
            self.end_headers()
            
            # Stream file in chunks
            with open(file_path, 'rb') as f:
                while True:
                    chunk = f.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    
        except Exception as e:
            print(f"❌ Download error: {e}")
            self.send_error(500, "Download failed")

    def handle_video_play(self):
        """Handle video play requests"""
        try:
            # Extract filename from /play/filename
            filename = unquote(self.path[6:])  # Remove '/play/' prefix
            print(f"🎥 Video play request for: '{filename}'")
            
            # Find the file using recursive search
            file_path = self.find_file_by_name(filename)
            
            if not file_path or not os.path.exists(file_path):
                print(f"❌ Video file not found: {filename}")
                self.send_error(404, f"Video '{filename}' not found")
                return
            
            print(f"✅ Found video: {file_path}")
            
            # Serve the video file
            super().do_GET()
                    
        except Exception as e:
            print(f"❌ Video play error: {e}")
            self.send_error(500, "Video play failed")

    def generate_enhanced_directory_listing(self, path):
        """Generate enhanced directory listing"""
        try:
            # Use the existing list_directory method
            return self.list_directory('.' if path == '/' else path.lstrip('/'))
        except Exception as e:
            print(f"❌ Directory listing error: {e}")
            self.send_error(500, "Directory listing failed")
    
    def get_file_category_and_extensions(self):
        """Define file categories with comprehensive extension mapping"""
        return {
            'Python Scripts': ['.py', '.pyw', '.pyx'],
            'Shell Scripts': ['.sh', '.bash', '.zsh', '.fish'],
            'Log Files': ['.log', '.logs'],
            'CSV Data': ['.csv'],
            'JSON Files': ['.json', '.jsonl'],
            'HTML Files': ['.html', '.htm'],
            'Documents': ['.docx', '.doc', '.pdf', '.odt', '.rtf'],
            'Text Files': ['.txt', '.md', '.readme'],
            'Spreadsheets': ['.xlsx', '.xls', '.ods'],
            'Stylesheets': ['.css', '.scss', '.sass', '.less'],
            'JavaScript': ['.js', '.jsx', '.ts', '.tsx'],
            'Images': ['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.svg', '.webp', '.ico'],
            'Videos': ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm'],
            'Audio': ['.mp3', '.wav', '.flac', '.ogg', '.m4a', '.wma'],
            'Archives': ['.zip', '.tar', '.gz', '.bz2', '.xz', '.rar', '.7z'],
            'Configuration': ['.conf', '.config', '.cfg', '.ini', '.yaml', '.yml', '.toml'],
            'Database': ['.db', '.sqlite', '.sqlite3', '.sql'],
            'XML Files': ['.xml', '.xsl', '.xsd'],
            'Binary': ['.bin', '.exe', '.dll', '.so', '.deb', '.rpm'],
            'Certificates': ['.pem', '.key', '.crt', '.cert', '.p12', '.pfx'],
            'Data Files': ['.dat', '.data', '.dump'],
            'Templates': ['.tpl', '.template', '.tmpl'],
            'Backup Files': ['.bak', '.backup', '.old'],
            'Temporary Files': ['.tmp', '.temp', '.cache'],
            'System Files': ['.service', '.socket', '.timer'],
            'Other Files': []
        }
    
    def format_file_size(self, size_bytes):
        """Convert bytes to human-readable format"""
        if size_bytes == 0:
            return "0 B"
        
        size_names = ["B", "KB", "MB", "GB", "TB"]
        i = 0
        size = float(size_bytes)
        
        while size >= 1024.0 and i < len(size_names) - 1:
            size /= 1024.0
            i += 1
        
        if i == 0:
            return f"{int(size)} {size_names[i]}"
        else:
            return f"{size:.1f} {size_names[i]}"
    
    def get_system_info(self):
        """Gather comprehensive Linux system information"""
        system_info = {}
        
        try:
            # Basic system information
            system_info['hostname'] = socket.gethostname()
            system_info['fqdn'] = socket.getfqdn()
            system_info['platform'] = platform.system()
            system_info['machine'] = platform.machine()
            system_info['processor'] = platform.processor()
            system_info['architecture'] = platform.architecture()[0]
            
            # Operating system details
            try:
                # Try to get detailed OS info from /etc/os-release
                with open('/etc/os-release', 'r') as f:
                    os_release = {}
                    for line in f:
                        if '=' in line:
                            key, value = line.strip().split('=', 1)
                            os_release[key] = value.strip('"')
                    
                    system_info['os_name'] = os_release.get('PRETTY_NAME', platform.system())
                    system_info['os_id'] = os_release.get('ID', 'unknown')
                    system_info['os_version'] = os_release.get('VERSION', 'unknown')
                    system_info['os_version_id'] = os_release.get('VERSION_ID', 'unknown')
            except:
                system_info['os_name'] = platform.system()
                system_info['os_id'] = 'unknown'
                system_info['os_version'] = platform.release()
                system_info['os_version_id'] = 'unknown'
            
            # Kernel information
            system_info['kernel_name'] = platform.system()
            system_info['kernel_release'] = platform.release()
            system_info['kernel_version'] = platform.version()
            
            # Network information
            try:
                # Get primary IP address
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                s.connect(("8.8.8.8", 80))
                system_info['ip_address'] = s.getsockname()[0]
                s.close()
            except:
                system_info['ip_address'] = 'unavailable'
            
            # MAC address
            try:
                mac = ':'.join(['{:02x}'.format((uuid.getnode() >> elements) & 0xff) 
                               for elements in range(0,2*6,2)][::-1])
                system_info['mac_address'] = mac
            except:
                system_info['mac_address'] = 'unavailable'
            
            # System UUID
            try:
                result = subprocess.run(['dmidecode', '-s', 'system-uuid'], 
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    system_info['system_uuid'] = result.stdout.strip()
                else:
                    system_info['system_uuid'] = str(uuid.uuid4())
            except:
                system_info['system_uuid'] = str(uuid.uuid4())
            
            # Boot time and uptime
            try:
                with open('/proc/uptime', 'r') as f:
                    uptime_seconds = float(f.readline().split()[0])
                    uptime_str = str(datetime.timedelta(seconds=int(uptime_seconds)))
                    system_info['uptime'] = uptime_str
                    
                    boot_time = datetime.datetime.now() - datetime.timedelta(seconds=uptime_seconds)
                    system_info['boot_time'] = boot_time.strftime('%Y-%m-%d %H:%M:%S')
            except:
                system_info['uptime'] = 'unavailable'
                system_info['boot_time'] = 'unavailable'
            
            # Memory information
            try:
                with open('/proc/meminfo', 'r') as f:
                    meminfo = {}
                    for line in f:
                        parts = line.split(':')
                        if len(parts) == 2:
                            key = parts[0].strip()
                            value = parts[1].strip().split()[0]
                            meminfo[key] = int(value) * 1024  # Convert from KB to bytes
                    
                    total_mem = meminfo.get('MemTotal', 0)
                    available_mem = meminfo.get('MemAvailable', 0)
                    system_info['memory_total'] = self.format_file_size(total_mem)
                    system_info['memory_available'] = self.format_file_size(available_mem)
                    system_info['memory_used'] = self.format_file_size(total_mem - available_mem)
            except:
                system_info['memory_total'] = 'unavailable'
                system_info['memory_available'] = 'unavailable'
                system_info['memory_used'] = 'unavailable'
            
            # Enhanced CPU information
            try:
                with open('/proc/cpuinfo', 'r') as f:
                    cpu_info = {}
                    processors = []
                    current_proc = {}
                    
                    for line in f:
                        if line.strip() == '':
                            if current_proc:
                                processors.append(current_proc)
                                current_proc = {}
                        elif ':' in line:
                            key, value = line.split(':', 1)
                            key = key.strip()
                            value = value.strip()
                            current_proc[key] = value
                    
                    if current_proc:
                        processors.append(current_proc)
                    
                    # Get CPU details
                    system_info['cpu_count'] = len(processors)
                    system_info['cpu_model'] = processors[0].get('model name', 'unknown') if processors else 'unknown'
                    system_info['cpu_cores'] = processors[0].get('cpu cores', 'unknown') if processors else 'unknown' 
                    system_info['cpu_threads'] = len(processors)
                    system_info['cpu_cache_size'] = processors[0].get('cache size', 'unknown') if processors else 'unknown'
                    system_info['cpu_flags'] = processors[0].get('flags', 'unknown')[:100] + '...' if processors and processors[0].get('flags') else 'unknown'
            except:
                system_info['cpu_count'] = 'unavailable'
                system_info['cpu_model'] = 'unavailable'
                system_info['cpu_cores'] = 'unavailable'
                system_info['cpu_threads'] = 'unavailable'
                system_info['cpu_cache_size'] = 'unavailable'
                system_info['cpu_flags'] = 'unavailable'
            
            # Load average
            try:
                with open('/proc/loadavg', 'r') as f:
                    loadavg = f.readline().strip().split()[:3]
                    system_info['load_average'] = f"{loadavg[0]} {loadavg[1]} {loadavg[2]}"
            except:
                system_info['load_average'] = 'unavailable'
            
            # Current time
            system_info['current_time'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S %Z')
            
        except Exception as e:
            print(f"Error gathering system info: {e}")
        
        return system_info
    
    def generate_system_info_html(self):
        """Generate system information HTML section with ENDS styling"""
        system_info = self.get_system_info()
        
        html = f"""
        <div class="category-section" style="border-left-color: #e91e63; margin-bottom: 20px;">
            <div class="category-header" style="border-left-color: #e91e63; background: linear-gradient(135deg, #1a202c 0%, #2d3748 100%);">
                <span>🖥️ System Information</span>
            </div>
            <div class="category-content active">
                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 16px; margin-bottom: 16px;">
                    
                    <!-- Operating System Info -->
                    <div style="background: #2d3748; border: 1px solid #4a5568; border-radius: 8px; padding: 16px;">
                        <h4 style="color: #e91e63; margin: 0 0 12px 0; font-size: 1.1em; display: flex; align-items: center; gap: 8px;">
                            <span>🐧</span> Operating System
                        </h4>
                        <div style="display: grid; grid-template-columns: 1fr 2fr; gap: 8px; font-size: 0.9em;">
                            <span style="color: #a0a0a0;">Distribution:</span>
                            <span style="color: #e6e6e6; font-weight: 500;">{system_info.get('os_name', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">Version:</span>
                            <span style="color: #e6e6e6;">{system_info.get('os_version', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">ID:</span>
                            <span style="color: #e6e6e6;">{system_info.get('os_id', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">Architecture:</span>
                            <span style="color: #e6e6e6;">{system_info.get('architecture', 'Unknown')}</span>
                        </div>
                    </div>
                    
                    <!-- Kernel Info -->
                    <div style="background: #2d3748; border: 1px solid #4a5568; border-radius: 8px; padding: 16px;">
                        <h4 style="color: #4fc3f7; margin: 0 0 12px 0; font-size: 1.1em; display: flex; align-items: center; gap: 8px;">
                            <span>⚙️</span> Kernel
                        </h4>
                        <div style="display: grid; grid-template-columns: 1fr 2fr; gap: 8px; font-size: 0.9em;">
                            <span style="color: #a0a0a0;">Name:</span>
                            <span style="color: #e6e6e6; font-weight: 500;">{system_info.get('kernel_name', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">Release:</span>
                            <span style="color: #e6e6e6;">{system_info.get('kernel_release', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">Version:</span>
                            <span style="color: #e6e6e6; font-size: 0.8em;">{system_info.get('kernel_version', 'Unknown')[:60]}{'...' if len(system_info.get('kernel_version', '')) > 60 else ''}</span>
                        </div>
                    </div>
                    
                    <!-- Network Info -->
                    <div style="background: #2d3748; border: 1px solid #4a5568; border-radius: 8px; padding: 16px;">
                        <h4 style="color: #81c784; margin: 0 0 12px 0; font-size: 1.1em; display: flex; align-items: center; gap: 8px;">
                            <span>🌐</span> Network
                        </h4>
                        <div style="display: grid; grid-template-columns: 1fr 2fr; gap: 8px; font-size: 0.9em;">
                            <span style="color: #a0a0a0;">Hostname:</span>
                            <span style="color: #e6e6e6; font-weight: 500;">{system_info.get('hostname', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">FQDN:</span>
                            <span style="color: #e6e6e6;">{system_info.get('fqdn', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">IP Address:</span>
                            <span style="color: #e6e6e6; font-family: monospace; background: #1a202c; padding: 2px 6px; border-radius: 4px;">{system_info.get('ip_address', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">MAC Address:</span>
                            <span style="color: #e6e6e6; font-family: monospace; background: #1a202c; padding: 2px 6px; border-radius: 4px;">{system_info.get('mac_address', 'Unknown')}</span>
                        </div>
                    </div>
                    
                    <!-- Enhanced CPU Info -->
                    <div style="background: #2d3748; border: 1px solid #4a5568; border-radius: 8px; padding: 16px;">
                        <h4 style="color: #ff8a65; margin: 0 0 12px 0; font-size: 1.1em; display: flex; align-items: center; gap: 8px;">
                            <span>🔧</span> CPU Details
                        </h4>
                        <div style="display: grid; grid-template-columns: 1fr 2fr; gap: 8px; font-size: 0.9em;">
                            <span style="color: #a0a0a0;">Model:</span>
                            <span style="color: #e6e6e6; font-weight: 500; font-size: 0.8em;">{system_info.get('cpu_model', 'Unknown')[:60]}{'...' if len(system_info.get('cpu_model', '')) > 60 else ''}</span>
                            <span style="color: #a0a0a0;">Physical Cores:</span>
                            <span style="color: #e6e6e6;">{system_info.get('cpu_cores', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">Logical Threads:</span>
                            <span style="color: #e6e6e6;">{system_info.get('cpu_threads', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">Cache Size:</span>
                            <span style="color: #e6e6e6; font-family: monospace; background: #1a202c; padding: 2px 6px; border-radius: 4px;">{system_info.get('cpu_cache_size', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">Architecture:</span>
                            <span style="color: #e6e6e6;">{system_info.get('machine', 'Unknown')}</span>
                        </div>
                    </div>
                    
                    <!-- System UUID -->
                    <div style="background: #2d3748; border: 1px solid #4a5568; border-radius: 8px; padding: 16px;">
                        <h4 style="color: #90caf9; margin: 0 0 12px 0; font-size: 1.1em; display: flex; align-items: center; gap: 8px;">
                            <span>🆔</span> System Identity
                        </h4>
                        <div style="display: grid; grid-template-columns: 1fr 2fr; gap: 8px; font-size: 0.9em;">
                            <span style="color: #a0a0a0;">Hostname:</span>
                            <span style="color: #e6e6e6; font-weight: 500;">{system_info.get('hostname', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">FQDN:</span>
                            <span style="color: #e6e6e6;">{system_info.get('fqdn', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">System UUID:</span>
                            <span style="color: #e6e6e6; font-family: monospace; font-size: 0.8em; background: #1a202c; padding: 2px 6px; border-radius: 4px;">{system_info.get('system_uuid', 'Unknown')}</span>
                        </div>
                    </div>
                    
                    <!-- Memory Info -->
                    <div style="background: #2d3748; border: 1px solid #4a5568; border-radius: 8px; padding: 16px;">
                        <h4 style="color: #ba68c8; margin: 0 0 12px 0; font-size: 1.1em; display: flex; align-items: center; gap: 8px;">
                            <span>🧠</span> Memory
                        </h4>
                        <div style="display: grid; grid-template-columns: 1fr 2fr; gap: 8px; font-size: 0.9em;">
                            <span style="color: #a0a0a0;">Total:</span>
                            <span style="color: #e6e6e6; font-weight: 500;">{system_info.get('memory_total', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">Used:</span>
                            <span style="color: #ff8a65;">{system_info.get('memory_used', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">Available:</span>
                            <span style="color: #81c784;">{system_info.get('memory_available', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">Load Average:</span>
                            <span style="color: #e6e6e6; font-family: monospace; background: #1a202c; padding: 2px 6px; border-radius: 4px;">{system_info.get('load_average', 'Unknown')}</span>
                        </div>
                    </div>
                    
                    <!-- System Status -->
                    <div style="background: #2d3748; border: 1px solid #4a5568; border-radius: 8px; padding: 16px;">
                        <h4 style="color: #ffb74d; margin: 0 0 12px 0; font-size: 1.1em; display: flex; align-items: center; gap: 8px;">
                            <span>⏰</span> System Status
                        </h4>
                        <div style="display: grid; grid-template-columns: 1fr 2fr; gap: 8px; font-size: 0.9em;">
                            <span style="color: #a0a0a0;">Current Time:</span>
                            <span style="color: #e6e6e6; font-weight: 500;">{system_info.get('current_time', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">Boot Time:</span>
                            <span style="color: #e6e6e6;">{system_info.get('boot_time', 'Unknown')}</span>
                            <span style="color: #a0a0a0;">Uptime:</span>
                            <span style="color: #81c784; font-weight: 500;">{system_info.get('uptime', 'Unknown')}</span>
                        </div>
                    </div>
                    
                </div>
            </div>
        </div>
        """
        
        return html
    
    def get_absolute_display_path(self, relative_path):
        """Convert relative HTTP path to absolute filesystem path for display"""
        try:
            # Get the actual absolute path where the server is running
            server_root = os.getcwd()
            
            # Decode the URL path
            decoded_path = unquote(relative_path)
            
            # If it's just root path, return the server root directory
            if decoded_path == '/' or decoded_path == '':
                return server_root
            
            # Otherwise, join the server root with the relative path
            # Remove leading slash since os.path.join handles it
            relative_part = decoded_path.lstrip('/')
            absolute_path = os.path.join(server_root, relative_part)
            
            # Normalize the path to resolve any .. or . components
            normalized_path = os.path.normpath(absolute_path)
            
            return normalized_path
            
        except Exception as e:
            print(f"Error resolving display path: {e}")
            # Fallback to basic path resolution
            return os.path.abspath(unquote(relative_path) if relative_path != '/' else '.')
    
    def list_directory(self, path):
        """ENDS-style directory listing with navigation and categorization"""
        try:
            file_list = os.listdir(path)
        except OSError as e:
            print(f"❌ Directory access error: {path} ({e})")
            self.send_error(404, "No permission to list directory")
            return None
        except Exception as e:
            print(f"❌ Unexpected error accessing directory: {path} ({e})")
            self.send_error(500, "Internal server error")
            return None
        
        categories = self.get_file_category_and_extensions()
        categorized_files = defaultdict(list)
        
        # Process files
        for name in file_list:
            fullname = os.path.join(path, name)
            
            try:
                stat = os.stat(fullname)
                file_size = stat.st_size
                mod_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stat.st_mtime))
                
                file_info = {
                    'name': name,
                    'size': self.format_file_size(file_size),
                    'size_bytes': file_size,
                    'modified': mod_time,
                    'is_dir': os.path.isdir(fullname)
                }
                
                # Categorize files
                if file_info['is_dir']:
                    categorized_files['Directories'].append(file_info)
                else:
                    _, ext = os.path.splitext(name.lower())
                    categorized = False
                    
                    for category, extensions in categories.items():
                        if ext in extensions:
                            categorized_files[category].append(file_info)
                            categorized = True
                            break
                    
                    if not categorized:
                        categorized_files['Other Files'].append(file_info)
                        
            except (OSError, ValueError):
                continue
        
        # Sort files within categories by modification time
        for category in categorized_files:
            categorized_files[category].sort(key=lambda x: x['modified'], reverse=True)
        
        # Generate HTML
        html_content = self.generate_ends_style_html(path, categorized_files)
        
        # Send response
        try:
            encoded = html_content.encode('utf-8')
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
        except Exception as e:
            print(f"❌ Error sending response: {e}")
            try:
                self.send_error(500, "Internal server error")
            except:
                pass
        return None
    
    def generate_ends_style_html(self, path, categorized_files):
        """Generate HTML with ENDS styling and layout"""
        
        # Get absolute display path for breadcrumb
        display_path = self.get_absolute_display_path(self.path)
        
        # Calculate statistics
        total_files = sum(len(files) for category, files in categorized_files.items() if category != 'Directories')
        total_dirs = len(categorized_files.get('Directories', []))
        total_size = sum(f['size_bytes'] for files in categorized_files.values() for f in files if not f['is_dir'])
        total_size_str = self.format_file_size(total_size)
        
        # Generate stats HTML
        stats_html = f"""
        <div class="stats-grid">
            <div class="stat-item">
                <div class="stat-number">{total_dirs}</div>
                <div class="stat-label">Directories</div>
            </div>
            <div class="stat-item">
                <div class="stat-number">{total_files}</div>
                <div class="stat-label">Files</div>
            </div>
            <div class="stat-item">
                <div class="stat-number">{total_size_str}</div>
                <div class="stat-label">Total Size</div>
            </div>
        </div>
"""
        
        # Generate system information HTML
        system_info_html = self.generate_system_info_html()
        
        # Generate navigation HTML
        navigation_html = self.generate_navigation_html(path)
        
        # Generate category sections
        categories_html = self.generate_category_sections_html(categorized_files)
        
        html = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Remote Advanced File Browser - {display_path}</title>
    <style>
        body {{
            font-family: 'Segoe UI', 'Monaco', 'Consolas', monospace;
            background: linear-gradient(135deg, #0f1419 0%, #1a1f2e 100%);
            color: #e6e6e6;
            margin: 0;
            padding: 20px;
            line-height: 1.6;
        }}
        .container {{
            max-width: 1600px;
            margin: 0 auto;
            background: #1e2329;
            border-radius: 12px;
            padding: 30px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.3);
        }}
        
        .header {{
            text-align: center;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 2px solid #4fc3f7;
        }}
        .header h1 {{
            color: #4fc3f7;
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
        }}
        .header p {{
            color: #aaa;
            font-size: 1.1em;
            margin: 0;
        }}
        .breadcrumb {{
            background: #2d3748;
            padding: 12px 20px;
            border-radius: 8px;
            font-family: monospace;
            font-size: 14px;
            color: #4fc3f7;
            margin-bottom: 20px;
            border-left: 4px solid #4fc3f7;
        }}
        
        .stats-container {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 12px;
            padding: 25px;
            margin-bottom: 30px;
            box-shadow: 0 8px 25px rgba(0, 0, 0, 0.2);
        }}
        .stats-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 20px;
        }}
        .stat-item {{
            text-align: center;
            color: white;
        }}
        .stat-number {{
            font-size: 2.2em;
            font-weight: bold;
            display: block;
        }}
        .stat-label {{
            font-size: 0.9em;
            opacity: 0.9;
            margin-top: 5px;
        }}
        
        .category-section {{
            background: #252932;
            border-radius: 12px;
            margin-bottom: 25px;
            overflow: hidden;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.2);
            border-left: 4px solid #4fc3f7;
        }}
        .category-header {{
            background: #2d3748;
            color: #4fc3f7;
            padding: 18px 25px;
            font-weight: 600;
            font-size: 1.2em;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-left: 4px solid #4fc3f7;
            transition: all 0.3s ease;
        }}
        .category-header:hover {{
            background: #3c4556;
        }}
        .category-content {{
            display: none;
        }}
        .category-content.active {{
            display: block;
        }}
        
        .file-grid {{
            display: flex;
            flex-direction: column;
            gap: 15px;
            padding: 20px;
        }}
        .file-grid.non-video {{
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
        }}
        
        .file-item {{
            background: #1a1f2e;
            border: 1px solid #3c4556;
            border-radius: 8px;
            padding: 20px;
            transition: all 0.3s ease;
            position: relative;
        }}
        .file-item:hover {{
            background: #252932;
            transform: translateY(-2px);
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.3);
        }}
        .file-item[data-hidden="true"] {{
            display: none;
        }}
        
        .file-header {{
            display: flex;
            align-items: flex-start;
            gap: 12px;
            margin-bottom: 12px;
        }}
        .file-icon {{
            font-size: 1.8em;
            min-width: 35px;
            line-height: 1;
        }}
        .file-name {{
            font-weight: 600;
            font-size: 1.1em;
            color: #e6e6e6;
            margin-bottom: 4px;
            overflow-wrap: break-word;
            word-break: break-word;
            line-height: 1.3;
            max-width: 100%;
            flex: 1;
            min-width: 0;
        }}
        
        /* Action Buttons */
        .file-actions {{
            display: flex;
            gap: 8px;
            margin: 12px 0;
        }}
        .action-btn {{
            padding: 8px 16px;
            border: 1px solid #4a5568;
            border-radius: 6px;
            background: #2d3748;
            color: #e6e6e6;
            text-decoration: none;
            font-size: 0.9em;
            font-weight: 500;
            transition: all 0.3s ease;
            text-align: center;
            min-width: 70px;
        }}
        .action-btn:hover {{
            background: #4a5568;
            color: #4fc3f7;
            text-decoration: none;
        }}
        .action-btn.view-btn:hover {{
            background: #81c784;
            color: #000;
        }}
        .action-btn.download-btn:hover {{
            background: #ff8a65;
            color: #000;
        }}
        
        .file-details {{
            margin-top: 12px;
            font-size: 0.9em;
            color: #aaa;
        }}
        .file-info-row {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 4px;
        }}
        .file-size {{
            font-weight: 600;
            color: #4fc3f7;
        }}
        .file-path {{
            background: #1a202c;
            padding: 6px 10px;
            border-radius: 4px;
            font-family: monospace;
            font-size: 1.0em;
            margin-top: 6px;
            word-break: break-all;
            color: #81c784;
            border-left: 2px solid #4fc3f7;
            overflow-wrap: break-word;
            white-space: pre-wrap;
            font-weight: 500;
        }}
        
        /* Image Thumbnail Styles */
        .thumbnail-container {{
            margin: 8px 0;
            text-align: center;
            background: #2d3748;
            border-radius: 4px;
            padding: 4px;
            border: 1px solid #4a5568;
        }}
        .thumbnail-image, .thumbnail-video {{
            max-width: 300px;
            max-height: 240px;
            width: auto;
            height: auto;
            border-radius: 3px;
            object-fit: cover;
            background: #1a202c;
            transition: transform 0.3s ease;
        }}
        .thumbnail-image:hover {{
            transform: scale(2.1);
            cursor: pointer;
            z-index: 10;
            position: relative;
        }}
        .video-static-thumb:hover {{
            transform: scale(1.05);
            box-shadow: 0 4px 15px rgba(255, 107, 107, 0.4);
            background: linear-gradient(135deg, #3d4758 0%, #2a303d 100%);
        }}
        
        /* Floating video preview overlay */
        .video-preview-overlay {{
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            width: 400px;
            height: 300px;
            background: #000;
            border: 3px solid #ff6b6b;
            border-radius: 8px;
            z-index: 9999;
            display: none;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.8);
        }}
        
        .video-preview-overlay video {{
            width: 100%;
            height: 100%;
            border-radius: 5px;
        }}
        .video-overlay {{
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            font-size: 2em;
            color: #ff6b6b;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.8);
            pointer-events: none;
            transition: opacity 0.3s ease;
        }}
        .thumbnail-container:hover .video-overlay {{
            opacity: 0.7;
        }}
        .thumbnail-container {{
            position: relative;
        }}
        .has-thumbnail {{
            min-height: 300px;
        }}
        .has-thumbnail .file-header {{
            margin-bottom: 4px;
        }}
        
        /* Responsive Design */
        @media (max-width: 768px) {{
            .file-grid {{
                grid-template-columns: 1fr;
            }}
            .stats-grid {{
                grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌐 Remote Advanced File Browser</h1>
            <p>Universal file browsing, filtering, and download system</p>
            <div class="breadcrumb">📁 Current Path: {display_path}</div>
        </div>
        
        {system_info_html}
        
        <div class="stats-container">
            {stats_html}
        </div>
        
        {navigation_html}
        
        {categories_html}
    </div>
    
    <script>
        // Toggle category sections
        document.querySelectorAll('.category-header').forEach(header => {{
            header.addEventListener('click', function() {{
                const content = this.nextElementSibling;
                const isActive = content.classList.contains('active');
                
                if (isActive) {{
                    content.classList.remove('active');
                    this.style.transform = 'none';
                }} else {{
                    content.classList.add('active');
                    this.style.transform = 'translateX(5px)';
                }}
            }});
        }});
        
        // Initialize - show navigation and directories by default
        document.querySelectorAll('.category-section').forEach((section, index) => {{
            if (index < 2) {{ // Show first 2 categories by default
                section.querySelector('.category-content').classList.add('active');
                section.querySelector('.category-header').style.transform = 'translateX(5px)';
            }}
        }});
        
        // Add click handlers for thumbnail images to open in new tab
        document.addEventListener('click', function(e) {{
            if (e.target.classList.contains('thumbnail-image')) {{
                e.preventDefault();
                window.open(e.target.src, '_blank');
            }}
        }});
        
        // SIMPLE video setup - no complex activation
        function setupVideos() {{
            console.log('=== SIMPLE VIDEO SETUP ===');
            
            const allVideos = document.querySelectorAll('.video-preview-player');
            console.log('Found', allVideos.length, 'videos');
            
            // Simple preload for all videos
            allVideos.forEach((video, index) => {{
                console.log('Setting up video', index);
                
                video.preload = 'metadata';
                video.load();
                
                // Set source directly for better compatibility
                const source = video.querySelector('source');
                if (source && source.src) {{
                    video.src = source.src;
                }}
                
                // Simple metadata handler
                video.addEventListener('loadedmetadata', function() {{
                    console.log('Video', index, 'metadata loaded');
                    this.currentTime = 0.5;
                }}, {{ once: true }});
            }});
            
            // ONE-TIME activation on first user interaction anywhere on page
            let activated = false;
            const activateAllVideos = () => {{
                if (activated) return;
                activated = true;
                
                console.log('=== ACTIVATING ALL VIDEOS ON FIRST INTERACTION ===');
                
                allVideos.forEach((video, index) => {{
                    setTimeout(() => {{
                        video.play().then(() => {{
                            console.log('Video', index, 'activated');
                            video.pause();
                            video.currentTime = 0.5;
                        }}).catch(e => {{
                            console.log('Video', index, 'activation failed:', e);
                        }});
                    }}, index * 50);
                }});
            }};
            
            // Listen for ANY user interaction to activate videos
            ['click', 'mousedown', 'touchstart', 'keydown'].forEach(eventType => {{
                document.addEventListener(eventType, activateAllVideos, {{ once: true }});
            }});
        }}
            
        // Setup interactions
        function setupInteractions() {{
            // Preview interactions
            document.querySelectorAll('.video-static-thumb').forEach((thumb, index) => {{
                const container = thumb.closest('.video-row-container');
                const previewArea = container.querySelector('.video-preview-area');
                const videoPlayer = container.querySelector('.video-preview-player');
                
                if (!previewArea || !videoPlayer) return;
                
                let previewTimeout = null;
                
                thumb.addEventListener('mouseenter', function() {{
                    console.log('Hover video', index);
                    
                    if (previewTimeout) clearTimeout(previewTimeout);
                    
                    previewArea.style.display = 'block';
                    videoPlayer.currentTime = 0;
                    
                    videoPlayer.play().catch(e => {{
                        console.log('Video play failed:', e);
                    }});
                    
                    previewTimeout = setTimeout(() => {{
                        previewArea.style.display = 'none';
                        videoPlayer.pause();
                    }}, 60000);
                }});
                
                thumb.addEventListener('mouseleave', function() {{
                    setTimeout(() => {{
                        if (!previewArea.matches(':hover')) {{
                            previewArea.style.display = 'none';
                            videoPlayer.pause();
                            if (previewTimeout) clearTimeout(previewTimeout);
                        }}
                    }}, 100);
                }});
                
                previewArea.addEventListener('mouseleave', function() {{
                    this.style.display = 'none';
                    videoPlayer.pause();
                    if (previewTimeout) clearTimeout(previewTimeout);
                }});
            }});
            
            // Download buttons - SIMPLE approach
            document.querySelectorAll('.download-btn').forEach(btn => {{
                btn.addEventListener('click', function(e) {{
                    console.log('Download clicked:', this.href);
                    
                    // Pause videos to free bandwidth
                    document.querySelectorAll('.video-preview-player').forEach(video => {{
                        video.pause();
                    }});
                    
                    // Let browser handle download naturally
                }});
            }});
            
            // Play video buttons
            document.querySelectorAll('.play-video-btn').forEach(btn => {{
                btn.addEventListener('click', function(e) {{
                    console.log('Play video clicked:', this.href);
                    
                    // Pause previews
                    document.querySelectorAll('.video-preview-player').forEach(video => {{
                        video.pause();
                    }});
                }});
            }});
        }}
        
        // Simple initialization
        function initializeEverything() {{
            setupVideos();
            setupInteractions();
        }}
        
        // Initialize
        if (document.readyState === 'loading') {{
            document.addEventListener('DOMContentLoaded', initializeEverything);
        }} else {{
            initializeEverything();
        }}
        
        setTimeout(initializeEverything, 300);
    </script>
</body>
</html>'''
        
        return html
    
    def generate_navigation_html(self, path):
        # Get both the URL path and absolute display path
        url_path = unquote(self.path)
        display_path = self.get_absolute_display_path(self.path)
        navigation_html = '''
        <div class="category-section" style="border-left-color: #4fc3f7;">
            <div class="category-header" style="border-left-color: #4fc3f7;">
                <span>🧭 Directory Navigation</span>
            </div>
            <div class="category-content">
                <div class="file-grid">
'''
        
        # Add parent directory if not at root
        if url_path != '/' and url_path != '':
            # For URL navigation, use the URL path
            parent_url_path = os.path.dirname(url_path.rstrip('/'))
            if parent_url_path == '':
                parent_url_path = '/'
            
            # For display, use the absolute path
            parent_absolute_path = os.path.dirname(display_path.rstrip('/'))
            parent_name = os.path.basename(parent_absolute_path) if parent_absolute_path else 'Parent'
            
            navigation_html += f'''
                    <div class="file-item" data-filename="parent" data-original-name=".." data-extension="" data-size-bytes="0" data-modified="2000-01-01 00:00:00" data-hidden="false">
                        <div class="file-header">
                            <span class="file-icon">📁</span>
                            <div class="file-name">⬆️ {parent_name} (Parent Directory)</div>
                        </div>
                        <div class="file-actions">
                            <a href="../" class="action-btn view-btn">Go Up</a>
                        </div>
                        <div class="file-details">
                            <div class="file-info-row">
                                <span class="file-size">Directory</span>
                                <span>Parent</span>
                            </div>
                            <div class="file-path">{parent_absolute_path}</div>
                        </div>
                    </div>
'''
        
        # Add current directory info
        current_dir_name = os.path.basename(display_path) if display_path not in ['/', ''] else 'Root'
        navigation_html += f'''
                    <div class="file-item" data-filename="current" data-original-name="{current_dir_name}" data-extension="" data-size-bytes="0" data-modified="2000-01-01 00:00:00" data-hidden="false" style="background: #2d3748; border: 2px solid #4fc3f7;">
                        <div class="file-header">
                            <span class="file-icon">📂</span>
                            <div class="file-name">📍 {current_dir_name} (Current Directory)</div>
                        </div>
                        <div class="file-actions">
                            <span class="action-btn" style="background: #4fc3f7; color: #000;">Current</span>
                        </div>
                        <div class="file-details">
                            <div class="file-info-row">
                                <span class="file-size">Directory</span>
                                <span>Current</span>
                            </div>
                            <div class="file-path">{display_path}</div>
                        </div>
                    </div>
'''
        
        # Find and add child directories with quick access
        child_dirs = []
        try:
            for item in os.listdir(path):
                item_path = os.path.join(path, item)
                if os.path.isdir(item_path) and not item.startswith('.'):
                    try:
                        # Count files in subdirectory
                        subdir_files = len([f for f in os.listdir(item_path) if not f.startswith('.')])
                        child_dirs.append((item, subdir_files))
                    except:
                        child_dirs.append((item, 0))
        except:
            pass
        
        if child_dirs:
            # Sort by number of files (most important directories first)
            child_dirs.sort(key=lambda x: x[1], reverse=True)
            for dir_name, file_count in child_dirs[:5]:  # Show top 5 subdirectories
                navigation_html += f'''
                    <div class="file-item" data-filename="{dir_name.lower()}" data-original-name="{dir_name}" data-extension="" data-size-bytes="0" data-modified="2000-01-01 00:00:00" data-hidden="false">
                        <div class="file-header">
                            <span class="file-icon">📁</span>
                            <div class="file-name">⬇️ {dir_name}</div>
                        </div>
                        <div class="file-actions">
                            <a href="{dir_name}/" class="action-btn view-btn">Enter</a>
                        </div>
                        <div class="file-details">
                            <div class="file-info-row">
                                <span class="file-size">{file_count} files</span>
                                <span>Subdirectory</span>
                            </div>
                        </div>
                    </div>
'''
        
        navigation_html += '''
                </div>
            </div>
        </div>
'''
        
        return navigation_html
    
    def generate_category_sections_html(self, categorized_files):
        """Generate category sections with ENDS styling"""
        category_icons = {
            'Directories': '📁',
            'Python Scripts': '🐍',
            'Shell Scripts': '⚡',
            'Log Files': '📋',
            'CSV Data': '📊',
            'JSON Files': '🔧',
            'HTML Files': '🌐',
            'Documents': '📄',
            'Text Files': '📝',
            'Spreadsheets': '📈',
            'Stylesheets': '🎨',
            'JavaScript': '⚡',
            'Images': '🖼️',
            'Videos': '🎥',
            'Audio': '🎵',
            'Archives': '📦',
            'Configuration': '⚙️',
            'Database': '🗄️',
            'XML Files': '📋',
            'Binary': '⚙️',
            'Certificates': '🔐',
            'Data Files': '💾',
            'Templates': '📋',
            'Backup Files': '💾',
            'Temporary Files': '🗑️',
            'System Files': '⚙️',
            'Other Files': '📄'
        }
        
        sections_html = []
        
        # Sort categories: Directories first, then by file count
        sorted_categories = []
        if 'Directories' in categorized_files and categorized_files['Directories']:
            sorted_categories.append(('Directories', len(categorized_files['Directories'])))
        
        other_categories = [(cat, len(files)) for cat, files in categorized_files.items() 
                           if cat != 'Directories' and files]
        other_categories.sort(key=lambda x: x[1], reverse=True)
        sorted_categories.extend(other_categories)
        
        for category, count in sorted_categories:
            files = categorized_files[category]
            if not files:
                continue
                
            category_icon = category_icons.get(category, '📄')
            
            files_html = []
            for file_info in files:
                if file_info['is_dir']:
                    file_icon = '📁'
                    actions = f'<a href="{file_info["name"]}/" class="action-btn view-btn">Enter</a>'
                    details = f'''
                        <div class="file-info-row">
                            <span class="file-size">Directory</span>
                            <span>Subdirectory</span>
                        </div>'''
                else:
                    _, ext = os.path.splitext(file_info['name'].lower())
                    file_icon = self.get_file_icon(ext)
                    
                    # Special handling for video files - no actions needed (handled in video gallery)
                    video_extensions = ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.mpeg', '.mpg', '.m4v', '.3gp', '.ogv']
                    if ext in video_extensions:
                        actions = ''  # No separate actions - handled in video gallery layout
                    else:
                        actions = f'<a href="{file_info["name"]}" class="action-btn view-btn">View</a><a href="{file_info["name"]}" download class="action-btn download-btn">Download</a>'
                    details = f'''
                        <div class="file-info-row">
                            <span class="file-size">{file_info["size"]}</span>
                            <span>{file_info["modified"]}</span>
                        </div>'''
                    
                    # Check if this is an image file for thumbnail display
                    image_extensions = ['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.ico', '.svg']
                    is_image = ext in image_extensions
                    file_info['is_image'] = is_image
                    
                    # Check if this is a video file for thumbnail display
                    video_extensions = ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.mpeg', '.mpg', '.m4v', '.3gp', '.ogv']
                    is_video = ext in video_extensions
                    file_info['is_video'] = is_video
                
                # Generate thumbnail HTML for image and video files
                thumbnail_html = ""
                if not file_info['is_dir']:
                    if file_info.get('is_image', False):
                        thumbnail_html = f'''
                            <div class="thumbnail-container">
                                <img src="{file_info['name']}" alt="Thumbnail of {file_info['name']}" class="thumbnail-image" loading="lazy" onerror="this.parentElement.style.display='none'">
                            </div>'''
                    elif file_info.get('is_video', False):
                        thumbnail_html = f'''
                            <div class="video-row-container" style="display: flex; align-items: flex-start; gap: 20px; width: 100%; background: #1a1f2e; border: 1px solid #4a5568; border-radius: 8px; padding: 20px; margin-bottom: 15px;">
                                <!-- Static Video Thumbnail -->
                                <div class="video-static-thumb" data-video-url="{file_info['name']}" style="width: 200px; height: 150px; background: linear-gradient(135deg, #2d3748 0%, #1a202c 100%); border: 2px solid #ff6b6b; border-radius: 4px; display: flex; flex-direction: column; align-items: center; justify-content: center; color: #ff6b6b; font-size: 1.5em; cursor: pointer; flex-shrink: 0;">
                                    🎬
                                    <div style="font-size: 0.4em; margin-top: 5px; color: #aaa; text-align: center;">Hover for Preview</div>
                                </div>
                                
                                <!-- Video Preview Area -->
                                <div class="video-preview-area" style="width: 300px; height: 225px; background: #000; border: 2px solid #ff6b6b; border-radius: 4px; display: none; flex-shrink: 0;">
                                    <video class="video-preview-player" muted loop preload="metadata" style="width: 100%; height: 100%; border-radius: 2px;">
                                        <source src="{file_info['name']}" type="video/mp4">
                                    </video>
                                </div>
                                
                                <!-- Video Information -->
                                <div class="video-info" style="flex: 1; color: #e6e6e6;">
                                    <h3 style="color: #81c784; font-weight: bold; margin: 0 0 10px 0; font-size: 1.2em; word-break: break-word;">{file_info['name']}</h3>
                                    <div style="display: grid; grid-template-columns: auto 1fr; gap: 8px 15px; font-size: 0.9em; margin-bottom: 15px;">
                                        <span style="color: #aaa;">Size:</span>
                                        <span style="color: #4fc3f7; font-weight: 500;">{file_info['size']}</span>
                                        <span style="color: #aaa;">Modified:</span>
                                        <span style="color: #81c784;">{file_info['modified']}</span>
                                        <span style="color: #aaa;">Type:</span>
                                        <span style="color: #ff8a65;">Video File ({ext.upper()})</span>
                                    </div>
                                    <div class="video-actions" style="display: flex; gap: 10px;">
                                        <a href="{file_info['name']}" class="action-btn play-video-btn" target="_blank" rel="noopener noreferrer" style="background: #ff6b6b; color: white; padding: 10px 20px; border-radius: 6px; text-decoration: none; font-weight: 500; transition: background 0.3s;">▶️ Play Video</a>
                                        <a href="{file_info['name']}" download class="action-btn download-btn" style="background: #2d3748; color: #e6e6e6; padding: 10px 20px; border-radius: 6px; text-decoration: none; font-weight: 500; transition: background 0.3s;">⬇️ Download</a>
                                    </div>
                                </div>
                            </div>'''
                
                has_media_thumbnail = (file_info.get('is_image', False) or file_info.get('is_video', False)) and not file_info['is_dir']
                files_html.append(f'''
                    <div class="file-item {('has-thumbnail' if has_media_thumbnail else '')}" data-filename="{file_info['name'].lower()}" data-original-name="{file_info['name']}" data-extension="{ext if not file_info['is_dir'] else ''}" data-size-bytes="{file_info['size_bytes']}" data-modified="{file_info['modified']}" data-hidden="false">
                        <div class="file-header">
                            <span class="file-icon">{file_icon}</span>
                            <div class="file-name">{file_info['name']}</div>
                        </div>
                        {thumbnail_html}
                        <div class="file-actions">
                            {actions}
                        </div>
                        <div class="file-details">
                            {details}
                        </div>
                    </div>
                ''')
            
            # Use different grid class for videos vs other files
            grid_class = "file-grid" if category == 'Videos' else "file-grid non-video"
            sections_html.append(f'''
                <div class="category-section">
                    <div class="category-header">
                        <span>{category_icon} {category} ({count})</span>
                    </div>
                    <div class="category-content">
                        <div class="{grid_class}">
                            {''.join(files_html)}
                        </div>
                    </div>
                </div>
            ''')
        
        return '\n'.join(sections_html)
    
    def get_file_icon(self, ext):
        """Get appropriate icon for file extension"""
        icon_map = {
            '.py': '🐍', '.sh': '⚡', '.log': '📋', '.csv': '📊', '.json': '🔧',
            '.html': '🌐', '.htm': '🌐', '.docx': '📄', '.txt': '📝', '.xlsx': '📈',
            '.css': '🎨', '.js': '⚡', '.png': '🖼️', '.jpg': '🖼️', '.pdf': '📄',
            '.mp4': '🎥', '.mp3': '🎵', '.zip': '📦', '.conf': '⚙️', '.sql': '🗄️'
        }
        return icon_map.get(ext, '📄')


def run_server(port=8081, directory=None):
    """Run the enhanced file server"""
    if directory:
        os.chdir(directory)
    
    print(f"🌐 Remote Advanced File Browser")
    print(f"📁 Serving directory: {os.getcwd()}")
    print(f"🌍 Server running at: http://localhost:{port}/")
    print(f"🔗 Network access: http://<your-ip>:{port}/")
    print(f"⏹️  Press Ctrl+C to stop the server")
    print("=" * 60)
    
    try:
        with socketserver.TCPServer(("", port), RemoteFileServerHandler) as httpd:
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Server stopped by user")
    except Exception as e:
        print(f"❌ Error: {e}")

def get_network_interface_ip():
    """Get the IP address of the primary network interface (standalone function)"""
    try:
        import netifaces
        
        # Get list of interfaces
        interfaces = netifaces.interfaces()
        
        # Priority order for interface types
        interface_priorities = ['wlp', 'ens', 'enp', 'eth', 'wlan', 'em']
        
        for priority in interface_priorities:
            for interface in interfaces:
                if interface.startswith(priority):
                    addresses = netifaces.ifaddresses(interface)
                    if netifaces.AF_INET in addresses:
                        ip = addresses[netifaces.AF_INET][0]['addr']
                        if ip != '127.0.0.1':
                            return ip, interface
        
        # Fallback to any non-loopback interface
        for interface in interfaces:
            if interface != 'lo':
                try:
                    addresses = netifaces.ifaddresses(interface)
                    if netifaces.AF_INET in addresses:
                        ip = addresses[netifaces.AF_INET][0]['addr']
                        if ip != '127.0.0.1':
                            return ip, interface
                except:
                    continue
        
    except ImportError:
        # Fallback method without netifaces
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip, 'unknown'
        except:
            pass
    
    return 'unavailable', 'unknown'

def main():
    """Main server function"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Enhanced HTTP File Server with Complete Navigation')
    parser.add_argument('--port', '-p', type=int, default=8081, help='Server port (default: 8081)')
    parser.add_argument('--host', default='auto', help='Server host (default: auto-detect)')
    parser.add_argument('--directory', '-d', default='.', help='Directory to serve (default: current)')
    
    args = parser.parse_args()
    
    # Change to serving directory
    if args.directory != '.':
        os.chdir(args.directory)
    
    # Auto-detect network interface and IP address
    if args.host == 'auto':
        detected_ip, interface = get_network_interface_ip()
        if detected_ip != 'unavailable':
            bind_host = '0.0.0.0'  # Bind to all interfaces
            display_host = detected_ip
        else:
            bind_host = 'localhost'
            display_host = 'localhost'
    else:
        bind_host = args.host
        display_host = args.host
    
    print("🌐 Enhanced HTTP File Server with Complete Navigation")
    print(f"📁 Serving directory: {os.getcwd()}")
    print(f"🖥️  Local access: http://localhost:{args.port}/")
    if bind_host == '0.0.0.0':
        print(f"🌍 Network access: http://{display_host}:{args.port}/")
        print(f"🔗 Interface: {interface if 'interface' in locals() else 'auto-detected'}")
    print("⏹️  Press Ctrl+C to stop the server")
    print("✨ Features: Directory Navigation, Video Previews, System Info, File Management")
    print("=" * 80)
    
    try:
        # Use ThreadingHTTPServer for better concurrency
        with ThreadingHTTPServer((bind_host, args.port), RemoteFileServerHandler) as httpd:
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Server stopped by user")
    except Exception as e:
        print(f"❌ Error starting server: {e}")

if __name__ == "__main__":
    main()
