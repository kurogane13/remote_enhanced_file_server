#!/usr/bin/env python3

"""
Enhanced HTTP File Server with Complete Navigation
Implements socket-based architecture with full directory navigation and file information
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

class EnhancedNavigationHandler(http.server.SimpleHTTPRequestHandler):
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
    
    def handle_api_request(self):
        """Handle API requests with JSON responses"""
        try:
            if self.path == '/api/videos':
                self.send_video_list()
            elif self.path.startswith('/api/video/'):
                video_name = unquote(self.path[11:])
                self.send_video_info(video_name)
            elif self.path.startswith('/api/directory/'):
                dir_path = unquote(self.path[15:]) or '.'
                self.send_directory_info(dir_path)
            elif self.path == '/api/system':
                self.send_system_info()
            elif self.path == '/api/status':
                self.send_server_status()
            else:
                self.send_error(404, "API endpoint not found")
        except Exception as e:
            print(f"❌ API error: {e}")
            self.send_error(500, "API error")
    
    def send_video_list(self):
        """Send list of videos in current directory as JSON"""
        try:
            videos = []
            current_dir = os.getcwd()
            
            for filename in os.listdir(current_dir):
                if any(filename.lower().endswith(ext) for ext in self.video_extensions):
                    try:
                        file_path = os.path.join(current_dir, filename)
                        stat = os.stat(file_path)
                        videos.append({
                            'name': filename,
                            'size': stat.st_size,
                            'size_formatted': self.format_file_size(stat.st_size),
                            'modified': stat.st_mtime,
                            'modified_formatted': time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stat.st_mtime)),
                            'url': f'/play/{quote(filename)}',
                            'download_url': f'/download/{quote(filename)}',
                            'direct_url': f'/{quote(filename)}'
                        })
                    except:
                        continue
            
            response = json.dumps(videos, indent=2)
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response.encode())
            
        except Exception as e:
            print(f"❌ Video list error: {e}")
            self.send_error(500, "Failed to list videos")
    
    def send_directory_info(self, dir_path):
        """Send directory information as JSON"""
        try:
            if not os.path.exists(dir_path) or not os.path.isdir(dir_path):
                self.send_error(404, "Directory not found")
                return
            
            files = []
            directories = []
            total_size = 0
            
            for item in os.listdir(dir_path):
                item_path = os.path.join(dir_path, item)
                try:
                    stat = os.stat(item_path)
                    is_dir = os.path.isdir(item_path)
                    
                    item_info = {
                        'name': item,
                        'size': 0 if is_dir else stat.st_size,
                        'size_formatted': 'Directory' if is_dir else self.format_file_size(stat.st_size),
                        'modified': stat.st_mtime,
                        'modified_formatted': time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stat.st_mtime)),
                        'is_directory': is_dir,
                        'is_video': any(item.lower().endswith(ext) for ext in self.video_extensions),
                        'is_image': any(item.lower().endswith(ext) for ext in self.image_extensions),
                        'permissions': oct(stat.st_mode)[-3:],
                        'owner': stat.st_uid,
                        'group': stat.st_gid
                    }
                    
                    if is_dir:
                        directories.append(item_info)
                    else:
                        files.append(item_info)
                        total_size += stat.st_size
                except:
                    continue
            
            directory_info = {
                'path': dir_path,
                'absolute_path': os.path.abspath(dir_path),
                'directories': directories,
                'files': files,
                'total_files': len(files),
                'total_directories': len(directories),
                'total_size': total_size,
                'total_size_formatted': self.format_file_size(total_size),
                'parent_directory': os.path.dirname(dir_path) if dir_path != '/' else None
            }
            
            response = json.dumps(directory_info, indent=2)
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response.encode())
            
        except Exception as e:
            print(f"❌ Directory info error: {e}")
            self.send_error(500, "Failed to get directory info")
    
    def send_system_info(self):
        """Send comprehensive system information as JSON"""
        try:
            system_info = self.get_system_info()
            response = json.dumps(system_info, indent=2)
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response.encode())
            
        except Exception as e:
            print(f"❌ System info error: {e}")
            self.send_error(500, "Failed to get system info")
    
    def get_network_interface_ip(self):
        """Get the IP address of the primary network interface"""
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

    def get_system_info(self):
        """Gather comprehensive system information"""
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
                    system_info['os_build_id'] = os_release.get('BUILD_ID', 'unknown')
            except:
                system_info['os_name'] = platform.system()
                system_info['os_id'] = 'unknown'
                system_info['os_version'] = platform.release()
                system_info['os_version_id'] = 'unknown'
                system_info['os_build_id'] = 'unknown'
            
            # Detailed kernel information
            system_info['kernel_name'] = platform.system()
            system_info['kernel_release'] = platform.release()
            system_info['kernel_version'] = platform.version()
            
            try:
                with open('/proc/version', 'r') as f:
                    kernel_full = f.read().strip()
                    system_info['kernel_full'] = kernel_full
            except:
                system_info['kernel_full'] = 'unavailable'
            
            # Network information
            ip_address, interface = self.get_network_interface_ip()
            system_info['ip_address'] = ip_address
            system_info['network_interface'] = interface
            
            # Get MAC address
            try:
                mac = ':'.join(['{:02x}'.format((uuid.getnode() >> elements) & 0xff) 
                               for elements in range(0,2*6,2)][::-1])
                system_info['mac_address'] = mac
            except:
                system_info['mac_address'] = 'unavailable'
            
            # Detailed CPU information
            try:
                with open('/proc/cpuinfo', 'r') as f:
                    cpuinfo = {}
                    cpu_count = 0
                    cpu_cores = 0
                    cpu_threads = 0
                    cpu_model = 'unknown'
                    cpu_mhz = 'unknown'
                    cpu_cache = 'unknown'
                    cpu_flags = []
                    
                    for line in f:
                        if ':' in line:
                            key, value = line.split(':', 1)
                            key = key.strip()
                            value = value.strip()
                            
                            if key == 'processor':
                                cpu_count += 1
                            elif key == 'model name':
                                cpu_model = value
                            elif key == 'cpu MHz':
                                cpu_mhz = value
                            elif key == 'cache size':
                                cpu_cache = value
                            elif key == 'cpu cores':
                                cpu_cores = int(value)
                            elif key == 'siblings':
                                cpu_threads = int(value)
                            elif key == 'flags' and not cpu_flags:
                                cpu_flags = value.split()[:10]  # First 10 flags
                    
                    system_info['cpu_count'] = cpu_count
                    system_info['cpu_cores'] = cpu_cores if cpu_cores > 0 else cpu_count
                    system_info['cpu_threads'] = cpu_threads if cpu_threads > 0 else cpu_count
                    system_info['cpu_model'] = cpu_model
                    system_info['cpu_mhz'] = cpu_mhz
                    system_info['cpu_cache'] = cpu_cache
                    system_info['cpu_flags'] = ' '.join(cpu_flags) if cpu_flags else 'unavailable'
            except:
                system_info['cpu_count'] = 'unavailable'
                system_info['cpu_cores'] = 'unavailable'
                system_info['cpu_threads'] = 'unavailable'
                system_info['cpu_model'] = 'unavailable'
                system_info['cpu_mhz'] = 'unavailable'
                system_info['cpu_cache'] = 'unavailable'
                system_info['cpu_flags'] = 'unavailable'
            
            # Load average
            try:
                with open('/proc/loadavg', 'r') as f:
                    loadavg = f.readline().strip().split()[:3]
                    system_info['load_average'] = f"{loadavg[0]} {loadavg[1]} {loadavg[2]}"
            except:
                system_info['load_average'] = 'unavailable'
            
            # Memory information with more details
            try:
                with open('/proc/meminfo', 'r') as f:
                    meminfo = {}
                    for line in f:
                        parts = line.split(':')
                        if len(parts) == 2:
                            key = parts[0].strip()
                            value = parts[1].strip().split()[0]
                            meminfo[key] = int(value) * 1024
                    
                    total_mem = meminfo.get('MemTotal', 0)
                    available_mem = meminfo.get('MemAvailable', 0)
                    free_mem = meminfo.get('MemFree', 0)
                    cached_mem = meminfo.get('Cached', 0)
                    buffer_mem = meminfo.get('Buffers', 0)
                    
                    system_info['memory_total'] = self.format_file_size(total_mem)
                    system_info['memory_available'] = self.format_file_size(available_mem)
                    system_info['memory_used'] = self.format_file_size(total_mem - available_mem)
                    system_info['memory_free'] = self.format_file_size(free_mem)
                    system_info['memory_cached'] = self.format_file_size(cached_mem)
                    system_info['memory_buffers'] = self.format_file_size(buffer_mem)
            except:
                system_info['memory_total'] = 'unavailable'
                system_info['memory_available'] = 'unavailable'
                system_info['memory_used'] = 'unavailable'
                system_info['memory_free'] = 'unavailable'
                system_info['memory_cached'] = 'unavailable'
                system_info['memory_buffers'] = 'unavailable'
            
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
            
            # Current time
            system_info['current_time'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S %Z')
            
        except Exception as e:
            print(f"Error gathering system info: {e}")
        
        return system_info
    
    def send_video_info(self, video_name):
        """Send video information as JSON"""
        try:
            video_path = os.path.join('.', video_name)
            
            if not os.path.exists(video_path):
                self.send_error(404, "Video not found")
                return
            
            stat = os.stat(video_path)
            video_info = {
                'name': video_name,
                'size': stat.st_size,
                'size_formatted': self.format_file_size(stat.st_size),
                'modified': stat.st_mtime,
                'modified_formatted': time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stat.st_mtime)),
                'play_url': f'/play/{quote(video_name)}',
                'download_url': f'/download/{quote(video_name)}',
                'direct_url': f'/{quote(video_name)}',
                'permissions': oct(stat.st_mode)[-3:],
                'is_readable': os.access(video_path, os.R_OK),
                'is_writable': os.access(video_path, os.W_OK)
            }
            
            response = json.dumps(video_info, indent=2)
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response.encode())
            
        except Exception as e:
            print(f"❌ Video info error: {e}")
            self.send_error(500, "Failed to get video info")
    
    def send_server_status(self):
        """Send server status as JSON"""
        try:
            current_dir = os.getcwd()
            
            # Count files by type
            video_count = 0
            image_count = 0
            total_files = 0
            total_dirs = 0
            
            for item in os.listdir(current_dir):
                item_path = os.path.join(current_dir, item)
                if os.path.isdir(item_path):
                    total_dirs += 1
                else:
                    total_files += 1
                    if any(item.lower().endswith(ext) for ext in self.video_extensions):
                        video_count += 1
                    elif any(item.lower().endswith(ext) for ext in self.image_extensions):
                        image_count += 1
            
            status = {
                'status': 'running',
                'directory': current_dir,
                'timestamp': time.time(),
                'timestamp_formatted': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                'total_files': total_files,
                'total_directories': total_dirs,
                'videos_count': video_count,
                'images_count': image_count,
                'server_version': '2.0.0-enhanced',
                'features': ['directory_navigation', 'video_preview', 'download_management', 'system_info']
            }
            
            response = json.dumps(status, indent=2)
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response.encode())
            
        except Exception as e:
            print(f"❌ Status error: {e}")
            self.send_error(500, "Failed to get status")
    
    def handle_dedicated_download(self):
        """Handle downloads with dedicated connection"""
        try:
            # Get filename from path, handling URL encoding
            filename = unquote(self.path[10:])  # Remove '/download/' prefix
            
            # Log the download request
            print(f"📥 Download request for: '{filename}'")
            
            # Check if this is a full path or just a filename
            if filename.startswith('/'):
                # This is already a full path
                filepath = filename
                display_name = os.path.basename(filename)
                print(f"🔍 Using full path: '{filepath}'")
            else:
                # This is just a filename, need to find the actual file location
                print(f"🔍 Searching for file: '{filename}'")
                filepath = self.find_file_by_name(filename)
                display_name = filename
                
                if not filepath:
                    print(f"❌ File not found anywhere: '{filename}'")
                    self.send_error(404, f"File not found: {filename}")
                    return
                
                print(f"📍 Found file at: '{filepath}'")
            
            # Normalize the path
            filepath = os.path.normpath(filepath)
            
            if not os.path.exists(filepath):
                print(f"❌ File does not exist: '{filepath}'")
                self.send_error(404, f"File not found: {display_name}")
                return
            
            if not os.path.isfile(filepath):
                print(f"❌ Not a file: {filepath}")
                self.send_error(400, "Not a file")
                return
            
            # Get file size
            file_size = os.path.getsize(filepath)
            
            # Determine content type
            content_type, _ = mimetypes.guess_type(filepath)
            if not content_type:
                content_type = 'application/octet-stream'
            
            print(f"📤 Starting download: {filename} ({self.format_file_size(file_size)})")
            
            # Send headers
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Disposition', f'attachment; filename="{display_name}"')
            self.send_header('Content-Length', str(file_size))
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            
            # Stream file content in chunks
            chunk_size = 64 * 1024  # 64KB chunks
            bytes_sent = 0
            
            with open(filepath, 'rb') as f:
                while True:
                    chunk = f.read(chunk_size)
                    if not chunk:
                        break
                    try:
                        self.wfile.write(chunk)
                        self.wfile.flush()
                        bytes_sent += len(chunk)
                    except BrokenPipeError:
                        print(f"⚠️  Client disconnected during download: {filename}")
                        break
                    except Exception as write_error:
                        print(f"❌ Write error during download: {write_error}")
                        break
            
            if bytes_sent == file_size:
                print(f"✅ Download completed successfully: {filename} ({self.format_file_size(bytes_sent)})")
            else:
                print(f"⚠️  Download incomplete: {filename} ({self.format_file_size(bytes_sent)}/{self.format_file_size(file_size)})")
            
        except Exception as e:
            print(f"❌ Download error for {self.path}: {e}")
            try:
                self.send_error(500, f"Download failed: {str(e)}")
            except:
                pass
    
    def handle_video_play(self):
        """Handle video play requests"""
        try:
            filename = unquote(self.path[6:])  # Remove '/play/' prefix
            filepath = os.path.join('.', filename)
            
            if not os.path.exists(filepath):
                self.send_error(404, "Video not found")
                return
            
            # Redirect to direct file URL
            self.send_response(302)
            self.send_header('Location', f'/{quote(filename)}')
            self.end_headers()
            
        except Exception as e:
            print(f"❌ Video play error: {e}")
            self.send_error(500, "Video play failed")
    
    def generate_enhanced_directory_listing(self, request_path):
        """Generate enhanced directory listing with full navigation"""
        try:
            # Handle root path
            if request_path == '/':
                current_dir = '.'
                display_path = os.getcwd()
            else:
                # Remove leading/trailing slashes and decode
                clean_path = request_path.strip('/')
                current_dir = os.path.join('.', clean_path) if clean_path else '.'
                display_path = os.path.abspath(current_dir)
            
            # Security check - ensure we stay within allowed bounds
            abs_current = os.path.abspath(current_dir)
            abs_start = os.path.abspath('.')
            
            if not abs_current.startswith(abs_start):
                self.send_error(403, "Access denied")
                return
            
            if not os.path.exists(current_dir) or not os.path.isdir(current_dir):
                self.send_error(404, "Directory not found")
                return
            
            # Change to the requested directory temporarily
            original_cwd = os.getcwd()
            os.chdir(current_dir)
            
            try:
                # Get directory contents
                files = []
                for filename in os.listdir('.'):
                    filepath = os.path.join('.', filename)
                    try:
                        stat = os.stat(filepath)
                        is_dir = os.path.isdir(filepath)
                        
                        file_info = {
                            'name': filename,
                            'size': 0 if is_dir else stat.st_size,
                            'modified': stat.st_mtime,
                            'is_directory': is_dir,
                            'is_video': any(filename.lower().endswith(ext) for ext in self.video_extensions),
                            'is_image': any(filename.lower().endswith(ext) for ext in self.image_extensions),
                            'permissions': oct(stat.st_mode)[-3:],
                            'is_readable': os.access(filepath, os.R_OK),
                            'is_writable': os.access(filepath, os.W_OK)
                        }
                        files.append(file_info)
                    except:
                        continue
                
                # Sort files
                files.sort(key=lambda x: (not x['is_directory'], x['name'].lower()))
                
                # Generate HTML
                html = self.generate_complete_html(files, display_path, request_path)
                
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Content-Length', str(len(html.encode('utf-8'))))
                self.end_headers()
                self.wfile.write(html.encode('utf-8'))
                
            finally:
                # Always restore original directory
                os.chdir(original_cwd)
            
        except Exception as e:
            print(f"❌ Directory listing error: {e}")
            try:
                os.chdir(original_cwd)
            except:
                pass
            self.send_error(500, "Failed to generate directory listing")
    
    def generate_complete_html(self, files, display_path, request_path):
        """Generate complete HTML with enhanced navigation and information"""
        
        # Generate breadcrumb navigation with proper URL encoding
        # Get relative path from current working directory
        abs_start = os.path.abspath('.')
        rel_path = os.path.relpath(display_path, abs_start)
        
        if rel_path == '.':
            path_parts = []
        else:
            path_parts = rel_path.split('/')
        
        breadcrumbs = []
        # Add root/home breadcrumb
        breadcrumbs.append({
            'name': 'Root',
            'path': '/'
        })
        
        # Build breadcrumbs for nested paths
        current_path = ""
        for i, part in enumerate(path_parts):
            if part and part != '.':
                current_path += f"/{part}"
                breadcrumbs.append({
                    'name': part,
                    'path': current_path + '/'
                })
        
        # Add parent directory link if not at root
        parent_link = ""
        if request_path != '/' and '/' in request_path.rstrip('/'):
            parent_path = '/'.join(request_path.rstrip('/').split('/')[:-1]) + '/'
            if parent_path == '/':
                parent_link = f'<a href="/" class="parent-link">📁 ← Parent Directory</a>'
            else:
                parent_link = f'<a href="{parent_path}" class="parent-link">📁 ← Parent Directory</a>'
        elif request_path != '/':
            parent_link = f'<a href="/" class="parent-link">📁 ← Root Directory</a>'
        
        # Separate file types
        directories = [f for f in files if f['is_directory']]
        videos = [f for f in files if f['is_video'] and not f['is_directory']]
        images = [f for f in files if f['is_image'] and not f['is_directory']]
        other_files = [f for f in files if not f['is_directory'] and not f['is_video'] and not f['is_image']]
        
        # Calculate statistics
        total_size = sum(f['size'] for f in files if not f['is_directory'])
        
        # Generate system info section with comprehensive details
        system_info = self.get_system_info()
        system_info_html = f"""
        <div class="system-info-section" style="background: linear-gradient(135deg, #1a202c 0%, #2d3748 100%); border: 2px solid #4a5568; border-radius: 10px; padding: 25px; margin: 20px 0;">
            <h3 style="color: #e91e63; margin: 0 0 20px 0; font-size: 1.4em; text-align: center; border-bottom: 2px solid #e91e63; padding-bottom: 10px;">🖥️ System Information</h3>
            
            <!-- System Identity Category -->
            <div style="margin-bottom: 20px;">
                <h4 style="color: #4ade80; margin: 0 0 12px 0; font-size: 1.1em; border-left: 4px solid #4ade80; padding-left: 10px; background: rgba(74, 222, 128, 0.05); padding: 8px 10px; border-radius: 4px;">🏷️ System Identity</h4>
                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 12px; padding-left: 15px;">
                    <div style="background: rgba(74, 222, 128, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #4ade80;">
                        <strong style="color: #4ade80;">Hostname:</strong> <span style="color: #e6e6e6;">{system_info.get('hostname', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(74, 222, 128, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #4ade80;">
                        <strong style="color: #4ade80;">FQDN:</strong> <span style="color: #e6e6e6;">{system_info.get('fqdn', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(74, 222, 128, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #4ade80;">
                        <strong style="color: #4ade80;">OS:</strong> <span style="color: #e6e6e6;">{system_info.get('os_name', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(74, 222, 128, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #4ade80;">
                        <strong style="color: #4ade80;">OS Version:</strong> <span style="color: #e6e6e6;">{system_info.get('os_version', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(74, 222, 128, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #4ade80;">
                        <strong style="color: #4ade80;">Architecture:</strong> <span style="color: #e6e6e6;">{system_info.get('architecture', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(74, 222, 128, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #4ade80;">
                        <strong style="color: #4ade80;">Platform:</strong> <span style="color: #e6e6e6;">{system_info.get('platform', 'N/A')}</span>
                    </div>
                </div>
            </div>
            
            <!-- Kernel Information Category -->
            <div style="margin-bottom: 20px;">
                <h4 style="color: #ff6b6b; margin: 0 0 12px 0; font-size: 1.1em; border-left: 4px solid #ff6b6b; padding-left: 10px; background: rgba(255, 107, 107, 0.05); padding: 8px 10px; border-radius: 4px;">🔧 Kernel Information</h4>
                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 12px; padding-left: 15px;">
                    <div style="background: rgba(255, 107, 107, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #ff6b6b;">
                        <strong style="color: #ff6b6b;">Kernel Name:</strong> <span style="color: #e6e6e6;">{system_info.get('kernel_name', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(255, 107, 107, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #ff6b6b;">
                        <strong style="color: #ff6b6b;">Kernel Release:</strong> <span style="color: #e6e6e6;">{system_info.get('kernel_release', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(255, 107, 107, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #ff6b6b; grid-column: span 2;">
                        <strong style="color: #ff6b6b;">Kernel Version:</strong><br>
                        <span style="color: #e6e6e6; font-size: 0.9em;">{system_info.get('kernel_version', 'N/A')[:100]}{'...' if len(system_info.get('kernel_version', '')) > 100 else ''}</span>
                    </div>
                </div>
            </div>
            
            <!-- Network Category -->
            <div style="margin-bottom: 20px;">
                <h4 style="color: #60a5fa; margin: 0 0 12px 0; font-size: 1.1em; border-left: 4px solid #60a5fa; padding-left: 10px; background: rgba(96, 165, 250, 0.05); padding: 8px 10px; border-radius: 4px;">🌐 Network Information</h4>
                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 12px; padding-left: 15px;">
                    <div style="background: rgba(96, 165, 250, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #60a5fa;">
                        <strong style="color: #60a5fa;">IP Address:</strong> <span style="color: #e6e6e6; font-family: monospace; background: rgba(0,0,0,0.3); padding: 2px 6px; border-radius: 3px;">{system_info.get('ip_address', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(96, 165, 250, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #60a5fa;">
                        <strong style="color: #60a5fa;">Interface:</strong> <span style="color: #e6e6e6; font-family: monospace; background: rgba(0,0,0,0.3); padding: 2px 6px; border-radius: 3px;">{system_info.get('network_interface', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(96, 165, 250, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #60a5fa; grid-column: span 2;">
                        <strong style="color: #60a5fa;">MAC Address:</strong> <span style="color: #e6e6e6; font-family: monospace; background: rgba(0,0,0,0.3); padding: 2px 6px; border-radius: 3px;">{system_info.get('mac_address', 'N/A')}</span>
                    </div>
                </div>
            </div>
            
            <!-- CPU Information Category -->
            <div style="margin-bottom: 20px;">
                <h4 style="color: #fbbf24; margin: 0 0 12px 0; font-size: 1.1em; border-left: 4px solid #fbbf24; padding-left: 10px; background: rgba(251, 191, 36, 0.05); padding: 8px 10px; border-radius: 4px;">🔥 CPU Information</h4>
                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 12px; padding-left: 15px;">
                    <div style="background: rgba(251, 191, 36, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #fbbf24;">
                        <strong style="color: #fbbf24;">Logical CPUs:</strong> <span style="color: #e6e6e6;">{system_info.get('cpu_count', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(251, 191, 36, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #fbbf24;">
                        <strong style="color: #fbbf24;">Physical Cores:</strong> <span style="color: #e6e6e6;">{system_info.get('cpu_cores', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(251, 191, 36, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #fbbf24;">
                        <strong style="color: #fbbf24;">Threads:</strong> <span style="color: #e6e6e6;">{system_info.get('cpu_threads', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(251, 191, 36, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #fbbf24;">
                        <strong style="color: #fbbf24;">CPU Speed:</strong> <span style="color: #e6e6e6;">{system_info.get('cpu_mhz', 'N/A')} MHz</span>
                    </div>
                    <div style="background: rgba(251, 191, 36, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #fbbf24;">
                        <strong style="color: #fbbf24;">Cache Size:</strong> <span style="color: #e6e6e6;">{system_info.get('cpu_cache', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(251, 191, 36, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #fbbf24;">
                        <strong style="color: #fbbf24;">Load Average:</strong> <span style="color: #e6e6e6; font-family: monospace; background: rgba(0,0,0,0.3); padding: 2px 6px; border-radius: 3px;">{system_info.get('load_average', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(251, 191, 36, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #fbbf24; grid-column: span 2;">
                        <strong style="color: #fbbf24;">Model:</strong><br>
                        <span style="color: #e6e6e6; font-size: 0.9em;">{system_info.get('cpu_model', 'N/A')}</span>
                    </div>
                </div>
            </div>
            
            <!-- Memory Information Category -->
            <div style="margin-bottom: 20px;">
                <h4 style="color: #f59e0b; margin: 0 0 12px 0; font-size: 1.1em; border-left: 4px solid #f59e0b; padding-left: 10px; background: rgba(245, 158, 11, 0.05); padding: 8px 10px; border-radius: 4px;">💾 Memory Information</h4>
                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 12px; padding-left: 15px;">
                    <div style="background: rgba(245, 158, 11, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #f59e0b;">
                        <strong style="color: #f59e0b;">Total:</strong> <span style="color: #e6e6e6; font-weight: bold;">{system_info.get('memory_total', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(245, 158, 11, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #f59e0b;">
                        <strong style="color: #f59e0b;">Available:</strong> <span style="color: #4ade80; font-weight: bold;">{system_info.get('memory_available', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(245, 158, 11, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #f59e0b;">
                        <strong style="color: #f59e0b;">Used:</strong> <span style="color: #ff6b6b; font-weight: bold;">{system_info.get('memory_used', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(245, 158, 11, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #f59e0b;">
                        <strong style="color: #f59e0b;">Free:</strong> <span style="color: #e6e6e6;">{system_info.get('memory_free', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(245, 158, 11, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #f59e0b;">
                        <strong style="color: #f59e0b;">Cached:</strong> <span style="color: #e6e6e6;">{system_info.get('memory_cached', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(245, 158, 11, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #f59e0b;">
                        <strong style="color: #f59e0b;">Buffers:</strong> <span style="color: #e6e6e6;">{system_info.get('memory_buffers', 'N/A')}</span>
                    </div>
                </div>
            </div>
            
            <!-- Time & Uptime Category -->
            <div>
                <h4 style="color: #8b5cf6; margin: 0 0 12px 0; font-size: 1.1em; border-left: 4px solid #8b5cf6; padding-left: 10px; background: rgba(139, 92, 246, 0.05); padding: 8px 10px; border-radius: 4px;">⏰ Time & System Status</h4>
                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 12px; padding-left: 15px;">
                    <div style="background: rgba(139, 92, 246, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #8b5cf6;">
                        <strong style="color: #8b5cf6;">Current Time:</strong> <span style="color: #e6e6e6; font-family: monospace; background: rgba(0,0,0,0.3); padding: 2px 6px; border-radius: 3px;">{system_info.get('current_time', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(139, 92, 246, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #8b5cf6;">
                        <strong style="color: #8b5cf6;">Boot Time:</strong> <span style="color: #e6e6e6; font-family: monospace; background: rgba(0,0,0,0.3); padding: 2px 6px; border-radius: 3px;">{system_info.get('boot_time', 'N/A')}</span>
                    </div>
                    <div style="background: rgba(139, 92, 246, 0.1); padding: 10px 14px; border-radius: 6px; border-left: 3px solid #8b5cf6; grid-column: span 2;">
                        <strong style="color: #8b5cf6;">Uptime:</strong> <span style="color: #4ade80; font-weight: bold; font-size: 1.1em;">{system_info.get('uptime', 'N/A')}</span>
                    </div>
                </div>
            </div>
        </div>
        """
        
        # Generate enhanced directory statistics with cool styling
        stats_html = f"""
        <div class="directory-stats-enhanced" style="background: linear-gradient(135deg, #1a202c 0%, #2d3748 100%); border: 2px solid #4a5568; border-radius: 12px; padding: 25px; margin: 20px 0; border-left: 6px solid #81c784;">
            <div class="stats-header" style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 2px solid #81c784; padding-bottom: 15px;">
                <h3 style="color: #81c784; margin: 0; font-size: 1.6em; display: flex; align-items: center; gap: 10px;">
                    📊 Directory Overview
                    <span style="background: #81c784; color: #1a202c; padding: 4px 12px; border-radius: 20px; font-size: 0.6em; font-weight: bold;">STATS</span>
                </h3>
                <div style="background: rgba(129, 199, 132, 0.2); padding: 8px 16px; border-radius: 20px; border: 1px solid #81c784;">
                    <span style="color: #81c784; font-weight: bold;">📂 Total Items: {len(directories) + len(videos) + len(images) + len(other_files)}</span>
                </div>
            </div>
            
            <div class="stats-grid" style="display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 15px;">
                <!-- Directories Card -->
                <div class="stat-card" style="
                    background: linear-gradient(135deg, #2d3748 0%, #1a202c 100%); 
                    border: 2px solid #4a5568; 
                    border-radius: 10px; 
                    padding: 18px; 
                    border-left: 5px solid #81c784;
                    transition: all 0.3s ease;
                    position: relative;
                    overflow: hidden;
                " onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 10px 30px rgba(129, 199, 132, 0.3)';" 
                   onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='none';">
                    <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 8px;">
                        <div style="
                            width: 45px; 
                            height: 45px; 
                            background: linear-gradient(135deg, #81c784 0%, #4ade80 100%); 
                            border-radius: 8px; 
                            display: flex; 
                            align-items: center; 
                            justify-content: center; 
                            font-size: 1.3em;
                            box-shadow: 0 4px 12px rgba(129, 199, 132, 0.4);
                        ">📁</div>
                        <div>
                            <div style="color: #81c784; font-weight: bold; font-size: 1.1em;">Directories</div>
                            <div style="color: #e6e6e6; font-size: 1.4em; font-weight: bold;">{len(directories)}</div>
                        </div>
                    </div>
                    <div style="
                        position: absolute;
                        top: 0;
                        right: 0;
                        background: linear-gradient(45deg, transparent 0%, rgba(129, 199, 132, 0.1) 100%);
                        width: 50px;
                        height: 50px;
                        pointer-events: none;
                    "></div>
                </div>
                
                <!-- Videos Card -->
                <div class="stat-card" style="
                    background: linear-gradient(135deg, #2d3748 0%, #1a202c 100%); 
                    border: 2px solid #4a5568; 
                    border-radius: 10px; 
                    padding: 18px; 
                    border-left: 5px solid #ff6b6b;
                    transition: all 0.3s ease;
                    position: relative;
                    overflow: hidden;
                " onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 10px 30px rgba(255, 107, 107, 0.3)';" 
                   onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='none';">
                    <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 8px;">
                        <div style="
                            width: 45px; 
                            height: 45px; 
                            background: linear-gradient(135deg, #ff6b6b 0%, #ee5a52 100%); 
                            border-radius: 8px; 
                            display: flex; 
                            align-items: center; 
                            justify-content: center; 
                            font-size: 1.3em;
                            box-shadow: 0 4px 12px rgba(255, 107, 107, 0.4);
                        ">🎥</div>
                        <div>
                            <div style="color: #ff6b6b; font-weight: bold; font-size: 1.1em;">Videos</div>
                            <div style="color: #e6e6e6; font-size: 1.4em; font-weight: bold;">{len(videos)}</div>
                        </div>
                    </div>
                    <div style="
                        position: absolute;
                        top: 0;
                        right: 0;
                        background: linear-gradient(45deg, transparent 0%, rgba(255, 107, 107, 0.1) 100%);
                        width: 50px;
                        height: 50px;
                        pointer-events: none;
                    "></div>
                </div>
                
                <!-- Images Card -->
                <div class="stat-card" style="
                    background: linear-gradient(135deg, #2d3748 0%, #1a202c 100%); 
                    border: 2px solid #4a5568; 
                    border-radius: 10px; 
                    padding: 18px; 
                    border-left: 5px solid #60a5fa;
                    transition: all 0.3s ease;
                    position: relative;
                    overflow: hidden;
                " onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 10px 30px rgba(96, 165, 250, 0.3)';" 
                   onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='none';">
                    <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 8px;">
                        <div style="
                            width: 45px; 
                            height: 45px; 
                            background: linear-gradient(135deg, #60a5fa 0%, #3b82f6 100%); 
                            border-radius: 8px; 
                            display: flex; 
                            align-items: center; 
                            justify-content: center; 
                            font-size: 1.3em;
                            box-shadow: 0 4px 12px rgba(96, 165, 250, 0.4);
                        ">🖼️</div>
                        <div>
                            <div style="color: #60a5fa; font-weight: bold; font-size: 1.1em;">Images</div>
                            <div style="color: #e6e6e6; font-size: 1.4em; font-weight: bold;">{len(images)}</div>
                        </div>
                    </div>
                    <div style="
                        position: absolute;
                        top: 0;
                        right: 0;
                        background: linear-gradient(45deg, transparent 0%, rgba(96, 165, 250, 0.1) 100%);
                        width: 50px;
                        height: 50px;
                        pointer-events: none;
                    "></div>
                </div>
                
                <!-- Other Files Card -->
                <div class="stat-card" style="
                    background: linear-gradient(135deg, #2d3748 0%, #1a202c 100%); 
                    border: 2px solid #4a5568; 
                    border-radius: 10px; 
                    padding: 18px; 
                    border-left: 5px solid #a78bfa;
                    transition: all 0.3s ease;
                    position: relative;
                    overflow: hidden;
                " onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 10px 30px rgba(167, 139, 250, 0.3)';" 
                   onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='none';">
                    <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 8px;">
                        <div style="
                            width: 45px; 
                            height: 45px; 
                            background: linear-gradient(135deg, #a78bfa 0%, #8b5cf6 100%); 
                            border-radius: 8px; 
                            display: flex; 
                            align-items: center; 
                            justify-content: center; 
                            font-size: 1.3em;
                            box-shadow: 0 4px 12px rgba(167, 139, 250, 0.4);
                        ">📄</div>
                        <div>
                            <div style="color: #a78bfa; font-weight: bold; font-size: 1.1em;">Other Files</div>
                            <div style="color: #e6e6e6; font-size: 1.4em; font-weight: bold;">{len(other_files)}</div>
                        </div>
                    </div>
                    <div style="
                        position: absolute;
                        top: 0;
                        right: 0;
                        background: linear-gradient(45deg, transparent 0%, rgba(167, 139, 250, 0.1) 100%);
                        width: 50px;
                        height: 50px;
                        pointer-events: none;
                    "></div>
                </div>
                
                <!-- Total Size Card -->
                <div class="stat-card" style="
                    background: linear-gradient(135deg, #2d3748 0%, #1a202c 100%); 
                    border: 2px solid #4a5568; 
                    border-radius: 10px; 
                    padding: 18px; 
                    border-left: 5px solid #fbbf24;
                    transition: all 0.3s ease;
                    position: relative;
                    overflow: hidden;
                    grid-column: span 1;
                " onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 10px 30px rgba(251, 191, 36, 0.3)';" 
                   onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='none';">
                    <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 8px;">
                        <div style="
                            width: 45px; 
                            height: 45px; 
                            background: linear-gradient(135deg, #fbbf24 0%, #f59e0b 100%); 
                            border-radius: 8px; 
                            display: flex; 
                            align-items: center; 
                            justify-content: center; 
                            font-size: 1.3em;
                            box-shadow: 0 4px 12px rgba(251, 191, 36, 0.4);
                        ">💾</div>
                        <div>
                            <div style="color: #fbbf24; font-weight: bold; font-size: 1.1em;">Total Size</div>
                            <div style="color: #e6e6e6; font-size: 1.2em; font-weight: bold;">{self.format_file_size(total_size)}</div>
                        </div>
                    </div>
                    <div style="
                        position: absolute;
                        top: 0;
                        right: 0;
                        background: linear-gradient(45deg, transparent 0%, rgba(251, 191, 36, 0.1) 100%);
                        width: 50px;
                        height: 50px;
                        pointer-events: none;
                    "></div>
                </div>
            </div>
        </div>
        """
        
        # Generate breadcrumb navigation
        breadcrumb_html = ""
        if breadcrumbs:
            breadcrumb_items = []
            for i, crumb in enumerate(breadcrumbs):
                if i == len(breadcrumbs) - 1:
                    breadcrumb_items.append(f'<span style="color: #4ade80; font-weight: bold;">{crumb["name"]}</span>')
                else:
                    breadcrumb_items.append(f'<a href="{crumb["path"]}" style="color: #60a5fa; text-decoration: none;">{crumb["name"]}</a>')
            
            breadcrumb_html = f"""
            <div class="breadcrumb-nav" style="background: #2d3748; padding: 15px; border-radius: 5px; margin: 15px 0; border-left: 4px solid #4ade80;">
                <div style="font-size: 0.9em; color: #aaa; margin-bottom: 5px;">📍 Current Location:</div>
                <div style="font-size: 1.1em;">{' → '.join(breadcrumb_items)}</div>
                {f'<div style="margin-top: 10px;">{parent_link}</div>' if parent_link else ''}
            </div>
            """
        
        # Generate enhanced directories section with detailed statistics
        directories_html = ""
        if directories:
            # Calculate directory statistics
            readable_dirs = sum(1 for d in directories if d['is_readable'])
            writable_dirs = sum(1 for d in directories if d['is_writable'])
            recent_dirs = [d for d in directories if (time.time() - d['modified']) < 86400]  # Last 24 hours
            
            directories_html = f"""
            <div class="directory-section" style="background: linear-gradient(135deg, #1a202c 0%, #2d3748 100%); border: 2px solid #4a5568; border-radius: 12px; padding: 25px; margin: 25px 0; border-left: 6px solid #81c784;">
                <div class="section-header" style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 2px solid #81c784; padding-bottom: 15px;">
                    <h2 style="color: #81c784; margin: 0; font-size: 1.8em; display: flex; align-items: center; gap: 10px;">
                        📁 Directories
                        <span style="background: #81c784; color: #1a202c; padding: 4px 12px; border-radius: 20px; font-size: 0.7em; font-weight: bold;">{len(directories)}</span>
                    </h2>
                    <div class="dir-quick-stats" style="display: flex; gap: 15px; font-size: 0.9em;">
                        <div style="background: rgba(129, 199, 132, 0.2); padding: 6px 12px; border-radius: 20px; border: 1px solid #81c784;">
                            <span style="color: #81c784;">✅ Readable: {readable_dirs}</span>
                        </div>
                        <div style="background: rgba(255, 107, 107, 0.2); padding: 6px 12px; border-radius: 20px; border: 1px solid #ff6b6b;">
                            <span style="color: #ff6b6b;">📝 Writable: {writable_dirs}</span>
                        </div>
                        <div style="background: rgba(251, 191, 36, 0.2); padding: 6px 12px; border-radius: 20px; border: 1px solid #fbbf24;">
                            <span style="color: #fbbf24;">🆕 Recent: {len(recent_dirs)}</span>
                        </div>
                    </div>
                </div>
                
                <div class="directories-grid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(400px, 1fr)); gap: 15px;">
            """
            
            for dir_info in directories:
                dir_path = f"{request_path.rstrip('/')}/{dir_info['name']}/" if request_path != '/' else f"/{dir_info['name']}/"
                
                # Calculate directory age
                age_seconds = time.time() - dir_info['modified']
                if age_seconds < 3600:
                    age_display = f"{int(age_seconds // 60)}m ago"
                    age_color = "#4ade80"
                elif age_seconds < 86400:
                    age_display = f"{int(age_seconds // 3600)}h ago"
                    age_color = "#fbbf24"
                elif age_seconds < 2592000:
                    age_display = f"{int(age_seconds // 86400)}d ago"
                    age_color = "#f59e0b"
                else:
                    age_display = f"{int(age_seconds // 2592000)}mo ago"
                    age_color = "#ef4444"
                
                # Permission indicators
                perm_indicators = []
                if dir_info['is_readable']:
                    perm_indicators.append('<span style="color: #4ade80; background: rgba(74, 222, 128, 0.2); padding: 2px 6px; border-radius: 10px; font-size: 0.8em;">👁️ Read</span>')
                if dir_info['is_writable']:
                    perm_indicators.append('<span style="color: #ff6b6b; background: rgba(255, 107, 107, 0.2); padding: 2px 6px; border-radius: 10px; font-size: 0.8em;">✏️ Write</span>')
                
                # Count files in directory (if accessible)
                file_count = "Unknown"
                try:
                    if dir_info['is_readable']:
                        subdir_path = os.path.join('.', dir_info['name']) if request_path == '/' else os.path.join(current_dir, dir_info['name'])
                        if os.path.exists(subdir_path):
                            file_count = len([f for f in os.listdir(subdir_path) if os.path.isfile(os.path.join(subdir_path, f))])
                except:
                    file_count = "N/A"
                
                directories_html += f"""
                <div class="directory-card" style="
                    background: linear-gradient(135deg, #2d3748 0%, #1a202c 100%); 
                    border: 2px solid #4a5568; 
                    border-radius: 8px; 
                    padding: 18px; 
                    transition: all 0.3s ease;
                    border-left: 4px solid #81c784;
                    position: relative;
                    overflow: hidden;
                " onmouseover="this.style.transform='translateY(-2px)'; this.style.boxShadow='0 8px 25px rgba(129, 199, 132, 0.2)'; this.style.borderColor='#81c784';" 
                   onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='none'; this.style.borderColor='#4a5568';">
                    
                    <!-- Directory Icon and Name -->
                    <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 12px;">
                        <div style="
                            width: 50px; 
                            height: 50px; 
                            background: linear-gradient(135deg, #81c784 0%, #4ade80 100%); 
                            border-radius: 8px; 
                            display: flex; 
                            align-items: center; 
                            justify-content: center; 
                            font-size: 1.5em;
                            box-shadow: 0 4px 12px rgba(129, 199, 132, 0.3);
                        ">📁</div>
                        <div style="flex: 1;">
                            <a href="{dir_path}" style="color: #81c784; text-decoration: none; font-weight: bold; font-size: 1.3em; display: block; line-height: 1.2;">
                                {dir_info['name']}/
                            </a>
                            <div style="display: flex; gap: 8px; margin-top: 4px;">
                                {' '.join(perm_indicators)}
                            </div>
                        </div>
                    </div>
                    
                    <!-- Directory Details Grid -->
                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px; font-size: 0.85em; background: rgba(0,0,0,0.2); padding: 12px; border-radius: 6px; margin-top: 10px;">
                        <div style="display: flex; justify-content: space-between;">
                            <span style="color: #a0a0a0;">Modified:</span>
                            <span style="color: {age_color}; font-weight: bold;">{age_display}</span>
                        </div>
                        <div style="display: flex; justify-content: space-between;">
                            <span style="color: #a0a0a0;">Permissions:</span>
                            <span style="color: #e6e6e6; font-family: monospace; background: rgba(255,255,255,0.1); padding: 1px 4px; border-radius: 3px;">{dir_info['permissions']}</span>
                        </div>
                        <div style="display: flex; justify-content: space-between;">
                            <span style="color: #a0a0a0;">Files:</span>
                            <span style="color: #60a5fa; font-weight: bold;">{file_count}</span>
                        </div>
                        <div style="display: flex; justify-content: space-between;">
                            <span style="color: #a0a0a0;">Access:</span>
                            <span style="color: {'#4ade80' if dir_info['is_readable'] else '#ef4444'};">{'Available' if dir_info['is_readable'] else 'Restricted'}</span>
                        </div>
                    </div>
                    
                    <!-- Hover Effect Overlay -->
                    <div style="
                        position: absolute;
                        top: 0;
                        right: 0;
                        background: linear-gradient(45deg, transparent 0%, rgba(129, 199, 132, 0.1) 100%);
                        width: 60px;
                        height: 60px;
                        pointer-events: none;
                    "></div>
                </div>
                """
            
            directories_html += """
                </div>
            </div>
            """
        
        # Generate videos section with hover preview
        videos_html = ""
        if videos:
            videos_html = f"""
            <h2 style="color: #ff6b6b; margin: 25px 0 15px 0; font-size: 1.6em;">🎥 Videos ({len(videos)})</h2>
            """
            for video in videos:
                videos_html += f"""
                <div class="video-container" data-video="{video['name']}" style="
                    display: flex; 
                    align-items: center; 
                    gap: 20px; 
                    width: 100%; 
                    background: linear-gradient(135deg, #1a1f2e 0%, #2d3748 100%); 
                    border: 2px solid #4a5568; 
                    border-radius: 8px; 
                    padding: 20px; 
                    margin-bottom: 15px;
                    min-height: 180px;
                ">
                    <!-- Video Thumbnail/Icon -->
                    <div class="video-thumbnail" data-video="{video['name']}" style="
                        width: 180px; 
                        height: 135px; 
                        background: linear-gradient(135deg, #2d3748 0%, #1a202c 100%); 
                        border: 2px solid #ff6b6b; 
                        border-radius: 4px; 
                        display: flex; 
                        flex-direction: column; 
                        align-items: center; 
                        justify-content: center; 
                        color: #ff6b6b; 
                        font-size: 2em; 
                        cursor: pointer; 
                        flex-shrink: 0;
                        position: relative;
                        transition: all 0.3s ease;
                    ">
                        🎬
                        <div style="font-size: 0.3em; margin-top: 5px; color: #aaa; text-align: center;">Hover for Preview</div>
                        <div class="play-overlay" style="
                            position: absolute;
                            top: 50%;
                            left: 50%;
                            transform: translate(-50%, -50%);
                            background: rgba(0,0,0,0.7);
                            border-radius: 50%;
                            width: 50px;
                            height: 50px;
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            color: white;
                            font-size: 1.2em;
                            transition: all 0.3s ease;
                        ">▶</div>
                    </div>
                    
                    <!-- Video Preview Area (hidden by default) -->
                    <div class="video-preview-area" data-video="{video['name']}" style="
                        width: 300px; 
                        height: 225px; 
                        background: #000; 
                        border: 2px solid #ff6b6b; 
                        border-radius: 4px; 
                        display: none; 
                        flex-shrink: 0;
                        position: relative;
                        overflow: hidden;
                    ">
                        <video class="video-preview-player" muted loop preload="metadata" style="
                            width: 100%; 
                            height: 100%; 
                            object-fit: cover;
                            border-radius: 2px;
                        ">
                            <source src="{quote(video['name'])}" type="video/mp4">
                        </video>
                        <div class="preview-controls" style="
                            position: absolute;
                            bottom: 5px;
                            left: 5px;
                            right: 5px;
                            background: rgba(0,0,0,0.7);
                            color: white;
                            padding: 5px;
                            border-radius: 3px;
                            font-size: 0.8em;
                            text-align: center;
                        ">60s Preview - Click to Play Full Video</div>
                    </div>
                    
                    <!-- Video Info -->
                    <div class="video-info" style="flex: 1; color: #e6e6e6;">
                        <h3 style="color: #81c784; font-weight: bold; margin: 0 0 10px 0; font-size: 1.3em; word-break: break-word;">{video['name']}</h3>
                        <p style="color: #aaa; margin: 5px 0; font-size: 0.9em;">Size: {self.format_file_size(video['size'])}</p>
                        <p style="color: #aaa; margin: 5px 0; font-size: 0.9em;">Modified: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(video['modified']))}</p>
                        <p style="color: #aaa; margin: 5px 0; font-size: 0.9em;">Permissions: {video['permissions']} | {'✅ Readable' if video['is_readable'] else '❌ Not Readable'}</p>
                        <div style="margin-top: 10px; padding: 8px 12px; background: rgba(74, 222, 128, 0.1); border-radius: 5px; border-left: 3px solid #4ade80;">
                            <span style="color: #4ade80; font-size: 0.9em;">💡 Hover thumbnail for 60s preview • Click preview to play full video</span>
                        </div>
                    </div>
                    
                    <!-- Download Control -->
                    <div class="video-controls" style="display: flex; flex-direction: column; gap: 10px; flex-shrink: 0;">
                        <button class="download-btn" data-file="{video['name']}" style="
                            background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); 
                            color: white; 
                            border: none; 
                            padding: 12px 24px; 
                            border-radius: 5px; 
                            cursor: pointer; 
                            font-weight: bold;
                            font-size: 1em;
                            transition: all 0.3s ease;
                        ">⬇ Download</button>
                    </div>
                </div>
                """
        
        # Generate images section
        images_html = ""
        if images:
            images_html = f"""
            <h2 style="color: #60a5fa; margin: 25px 0 15px 0; font-size: 1.6em;">🖼️ Images ({len(images)})</h2>
            <div class="images-grid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 15px; margin-bottom: 20px;">
            """
            for image in images:
                images_html += f"""
                <div class="image-item" style="background: #2d3748; border-radius: 8px; padding: 15px; border-left: 4px solid #60a5fa;">
                    <div style="text-align: center; margin-bottom: 10px;">
                        <img src="{quote(image['name'])}" style="max-width: 100%; height: 150px; object-fit: cover; border-radius: 4px; cursor: pointer;" 
                             onerror="this.style.display='none'" loading="lazy" 
                             onclick="window.open('{quote(image['name'])}', '_blank')">
                    </div>
                    <h4 style="color: #60a5fa; margin: 0 0 5px 0; font-size: 1em; word-break: break-word;">{image['name']}</h4>
                    <div style="color: #aaa; font-size: 0.8em;">
                        <div>Size: {self.format_file_size(image['size'])}</div>
                        <div>Modified: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(image['modified']))}</div>
                        <div>Permissions: {image['permissions']}</div>
                    </div>
                    <div style="margin-top: 10px; display: flex; gap: 5px;">
                        <button onclick="window.open('{quote(image['name'])}', '_blank')" style="
                            background: #60a5fa; color: white; border: none; padding: 5px 10px; 
                            border-radius: 3px; cursor: pointer; font-size: 0.8em; flex: 1;
                        ">👁️ View</button>
                        <button class="download-btn" data-file="{image['name']}" style="
                            background: #3b82f6; color: white; border: none; padding: 5px 10px; 
                            border-radius: 3px; cursor: pointer; font-size: 0.8em; flex: 1;
                        ">⬇ Download</button>
                    </div>
                </div>
                """
            images_html += "</div>"
        
        # Generate enhanced other files section
        other_files_html = ""
        if other_files:
            # Calculate file statistics
            total_other_size = sum(f['size'] for f in other_files)
            readable_files = sum(1 for f in other_files if f['is_readable'])
            writable_files = sum(1 for f in other_files if f['is_writable'])
            large_files = [f for f in other_files if f['size'] > 10*1024*1024]  # > 10MB
            
            # Categorize files by extension
            file_categories = {}
            for file_info in other_files:
                _, ext = os.path.splitext(file_info['name'].lower())
                ext = ext or 'no extension'
                if ext not in file_categories:
                    file_categories[ext] = []
                file_categories[ext].append(file_info)
            
            other_files_html = f"""
            <div class="files-section" style="background: linear-gradient(135deg, #1a202c 0%, #2d3748 100%); border: 2px solid #4a5568; border-radius: 12px; padding: 25px; margin: 25px 0; border-left: 6px solid #6b7280;">
                <div class="section-header" style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 2px solid #6b7280; padding-bottom: 15px;">
                    <h2 style="color: #6b7280; margin: 0; font-size: 1.8em; display: flex; align-items: center; gap: 10px;">
                        📄 Files
                        <span style="background: #6b7280; color: #1a202c; padding: 4px 12px; border-radius: 20px; font-size: 0.7em; font-weight: bold;">{len(other_files)}</span>
                    </h2>
                    <div class="files-quick-stats" style="display: flex; gap: 15px; font-size: 0.9em;">
                        <div style="background: rgba(107, 114, 128, 0.2); padding: 6px 12px; border-radius: 20px; border: 1px solid #6b7280;">
                            <span style="color: #6b7280;">📊 Size: {self.format_file_size(total_other_size)}</span>
                        </div>
                        <div style="background: rgba(96, 165, 250, 0.2); padding: 6px 12px; border-radius: 20px; border: 1px solid #60a5fa;">
                            <span style="color: #60a5fa;">📖 Readable: {readable_files}</span>
                        </div>
                        <div style="background: rgba(251, 191, 36, 0.2); padding: 6px 12px; border-radius: 20px; border: 1px solid #fbbf24;">
                            <span style="color: #fbbf24;">🗂️ Types: {len(file_categories)}</span>
                        </div>
                    </div>
                </div>
                
                <div class="files-grid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(380px, 1fr)); gap: 15px;">
            """
            
            for file_info in other_files:
                file_icon = self.get_file_icon(file_info['name'])
                _, ext = os.path.splitext(file_info['name'].lower())
                
                # Calculate file age and size category
                age_seconds = time.time() - file_info['modified']
                if age_seconds < 3600:
                    age_display = f"{int(age_seconds // 60)}m ago"
                    age_color = "#4ade80"
                elif age_seconds < 86400:
                    age_display = f"{int(age_seconds // 3600)}h ago"
                    age_color = "#fbbf24"
                elif age_seconds < 2592000:
                    age_display = f"{int(age_seconds // 86400)}d ago"
                    age_color = "#f59e0b"
                else:
                    age_display = f"{int(age_seconds // 2592000)}mo ago"
                    age_color = "#ef4444"
                
                # Size categories
                if file_info['size'] < 1024:
                    size_color = "#9ca3af"
                elif file_info['size'] < 1024*1024:
                    size_color = "#60a5fa"
                elif file_info['size'] < 10*1024*1024:
                    size_color = "#fbbf24"
                else:
                    size_color = "#f59e0b"
                
                # File type color based on extension
                ext_colors = {
                    '.txt': '#9ca3af', '.md': '#60a5fa', '.log': '#ef4444',
                    '.py': '#fbbf24', '.js': '#10b981', '.html': '#f59e0b',
                    '.css': '#8b5cf6', '.json': '#06b6d4', '.xml': '#ec4899',
                    '.pdf': '#dc2626', '.doc': '#2563eb', '.docx': '#2563eb',
                    '.zip': '#7c3aed', '.tar': '#7c3aed', '.gz': '#7c3aed'
                }
                ext_color = ext_colors.get(ext, '#6b7280')
                
                # Permission indicators
                perm_indicators = []
                if file_info['is_readable']:
                    perm_indicators.append('<span style="color: #4ade80; background: rgba(74, 222, 128, 0.2); padding: 2px 6px; border-radius: 10px; font-size: 0.75em;">👁️ R</span>')
                if file_info['is_writable']:
                    perm_indicators.append('<span style="color: #ff6b6b; background: rgba(255, 107, 107, 0.2); padding: 2px 6px; border-radius: 10px; font-size: 0.75em;">✏️ W</span>')
                
                other_files_html += f"""
                <div class="file-card" style="
                    background: linear-gradient(135deg, #2d3748 0%, #1a202c 100%); 
                    border: 2px solid #4a5568; 
                    border-radius: 8px; 
                    padding: 18px; 
                    transition: all 0.3s ease;
                    border-left: 4px solid {ext_color};
                    position: relative;
                    overflow: hidden;
                " onmouseover="this.style.transform='translateY(-2px)'; this.style.boxShadow='0 8px 25px rgba(107, 114, 128, 0.2)'; this.style.borderColor='{ext_color}';" 
                   onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='none'; this.style.borderColor='#4a5568';">
                    
                    <!-- File Icon and Name -->
                    <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 12px;">
                        <div style="
                            width: 50px; 
                            height: 50px; 
                            background: linear-gradient(135deg, {ext_color} 0%, {ext_color}cc 100%); 
                            border-radius: 8px; 
                            display: flex; 
                            align-items: center; 
                            justify-content: center; 
                            font-size: 1.4em;
                            box-shadow: 0 4px 12px rgba(107, 114, 128, 0.3);
                        ">{file_icon}</div>
                        <div style="flex: 1; min-width: 0;">
                            <a href="{quote(file_info['name'])}" style="color: #e6e6e6; text-decoration: none; font-weight: bold; font-size: 1.1em; display: block; line-height: 1.2; word-break: break-word;">
                                {file_info['name']}
                            </a>
                            <div style="display: flex; gap: 8px; margin-top: 4px; flex-wrap: wrap;">
                                {' '.join(perm_indicators)}
                                <span style="color: {ext_color}; background: rgba(107, 114, 128, 0.2); padding: 2px 6px; border-radius: 10px; font-size: 0.75em; font-family: monospace;">{ext.upper() if ext else 'FILE'}</span>
                            </div>
                        </div>
                    </div>
                    
                    <!-- File Details Grid -->
                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px; font-size: 0.85em; background: rgba(0,0,0,0.2); padding: 12px; border-radius: 6px; margin-top: 10px;">
                        <div style="display: flex; justify-content: space-between;">
                            <span style="color: #a0a0a0;">Size:</span>
                            <span style="color: {size_color}; font-weight: bold;">{self.format_file_size(file_info['size'])}</span>
                        </div>
                        <div style="display: flex; justify-content: space-between;">
                            <span style="color: #a0a0a0;">Modified:</span>
                            <span style="color: {age_color}; font-weight: bold;">{age_display}</span>
                        </div>
                        <div style="display: flex; justify-content: space-between;">
                            <span style="color: #a0a0a0;">Permissions:</span>
                            <span style="color: #e6e6e6; font-family: monospace; background: rgba(255,255,255,0.1); padding: 1px 4px; border-radius: 3px;">{file_info['permissions']}</span>
                        </div>
                        <div style="display: flex; justify-content: space-between;">
                            <span style="color: #a0a0a0;">Access:</span>
                            <span style="color: {'#4ade80' if file_info['is_readable'] else '#ef4444'};">{'Available' if file_info['is_readable'] else 'Restricted'}</span>
                        </div>
                    </div>
                    
                    <!-- Action Buttons -->
                    <div style="display: flex; gap: 8px; margin-top: 12px;">
                        <button onclick="window.open('{quote(file_info['name'])}', '_blank')" style="
                            background: linear-gradient(135deg, #60a5fa 0%, #3b82f6 100%); 
                            color: white; border: none; padding: 8px 16px; border-radius: 5px; 
                            cursor: pointer; font-size: 0.85em; flex: 1; font-weight: bold;
                            transition: all 0.3s ease;
                        " onmouseover="this.style.transform='scale(1.05)'" onmouseout="this.style.transform='scale(1)'">
                            👁️ View
                        </button>
                        <button class="download-btn" data-file="{file_info['name']}" style="
                            background: linear-gradient(135deg, #10b981 0%, #059669 100%); 
                            color: white; border: none; padding: 8px 16px; border-radius: 5px; 
                            cursor: pointer; font-size: 0.85em; flex: 1; font-weight: bold;
                            transition: all 0.3s ease;
                        " onmouseover="this.style.transform='scale(1.05)'" onmouseout="this.style.transform='scale(1)'">
                            ⬇ Download
                        </button>
                    </div>
                    
                    <!-- Hover Effect Overlay -->
                    <div style="
                        position: absolute;
                        top: 0;
                        right: 0;
                        background: linear-gradient(45deg, transparent 0%, rgba(107, 114, 128, 0.1) 100%);
                        width: 60px;
                        height: 60px;
                        pointer-events: none;
                    "></div>
                </div>
                """
            
            other_files_html += """
                </div>
            </div>
            """
        
        # Complete HTML
        html = f'''
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>🎬 Enhanced File Server - {os.path.basename(display_path) or 'Root'}</title>
            <style>
                body {{
                    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                    background: linear-gradient(135deg, #0f1419 0%, #1a202c 100%);
                    color: #e6e6e6;
                    margin: 0;
                    padding: 20px;
                    min-height: 100vh;
                }}
                .container {{
                    max-width: 1400px;
                    margin: 0 auto;
                }}
                .header {{
                    text-align: center;
                    margin-bottom: 30px;
                    padding: 30px;
                    background: linear-gradient(135deg, #1a202c 0%, #2d3748 100%);
                    border-radius: 10px;
                    border: 2px solid #4a5568;
                }}
                .server-status {{
                    position: fixed;
                    top: 15px;
                    right: 15px;
                    padding: 8px 15px;
                    border-radius: 5px;
                    font-size: 0.9em;
                    font-weight: bold;
                    z-index: 1000;
                    background: #22c55e;
                    color: white;
                    border: 2px solid #16a34a;
                }}
                .parent-link {{
                    color: #4ade80;
                    text-decoration: none;
                    font-weight: bold;
                    padding: 8px 15px;
                    background: #2d3748;
                    border-radius: 5px;
                    border: 1px solid #4ade80;
                    display: inline-block;
                    transition: all 0.3s ease;
                }}
                .parent-link:hover {{
                    background: #4ade80;
                    color: #1a202c;
                    transform: scale(1.05);
                }}
                .video-thumbnail:hover {{
                    transform: scale(1.05);
                    border-color: #4ade80;
                    box-shadow: 0 8px 25px rgba(74, 222, 128, 0.3);
                }}
                button:hover {{
                    transform: scale(1.05);
                    box-shadow: 0 6px 20px rgba(0,0,0,0.4);
                }}
                button:active {{
                    transform: scale(0.95);
                }}
                .video-preview-overlay {{
                    position: fixed;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    background: rgba(0,0,0,0.95);
                    display: none;
                    justify-content: center;
                    align-items: center;
                    z-index: 10000;
                }}
                .video-preview-container {{
                    position: relative;
                    max-width: 90%;
                    max-height: 90%;
                    background: #1a202c;
                    border-radius: 10px;
                    padding: 20px;
                    border: 2px solid #4a5568;
                }}
                .video-preview-player {{
                    width: 100%;
                    height: auto;
                    max-height: 70vh;
                    border-radius: 8px;
                }}
                .close-preview {{
                    position: absolute;
                    top: -15px;
                    right: -15px;
                    background: #ef4444;
                    color: white;
                    border: none;
                    width: 40px;
                    height: 40px;
                    border-radius: 50%;
                    cursor: pointer;
                    font-weight: bold;
                    font-size: 1.2em;
                }}
                .notification {{
                    position: fixed;
                    bottom: 20px;
                    right: 20px;
                    padding: 15px 25px;
                    border-radius: 8px;
                    font-weight: bold;
                    z-index: 10001;
                    transform: translateX(400px);
                    transition: transform 0.3s ease;
                }}
                .notification.show {{
                    transform: translateX(0);
                }}
                .notification.success {{
                    background: #22c55e;
                    color: white;
                    border: 2px solid #16a34a;
                }}
                .notification.error {{
                    background: #ef4444;
                    color: white;
                    border: 2px solid #dc2626;
                }}
            </style>
        </head>
        <body>
            <div class="server-status" id="serverStatus">
                🟢 Enhanced Server Active
            </div>
            
            <div class="container">
                <div class="header">
                    <h1 style="color: #4ade80; margin: 0; font-size: 2.8em;">🎬 Enhanced File Server</h1>
                    <p style="color: #aaa; margin: 15px 0 0 0; font-size: 1.2em;">📂 {display_path}</p>
                </div>
                
                {breadcrumb_html}
                {stats_html}
                {system_info_html}
                {directories_html}
                {videos_html}
                {images_html}
                {other_files_html}
            </div>
            
            <!-- Video Preview Overlay -->
            <div class="video-preview-overlay" id="videoPreviewOverlay">
                <div class="video-preview-container">
                    <button class="close-preview" onclick="closeVideoPreview()">✕</button>
                    <video class="video-preview-player" id="videoPreviewPlayer" controls muted preload="metadata">
                        <source src="" type="video/mp4">
                    </video>
                </div>
            </div>
            
            <!-- Notification System -->
            <div class="notification" id="notification"></div>
            
            <script>
                function showNotification(message, type = 'success') {{
                    const notification = document.getElementById('notification');
                    notification.textContent = message;
                    notification.className = `notification ${{type}}`;
                    notification.classList.add('show');
                    
                    setTimeout(() => {{
                        notification.classList.remove('show');
                    }}, 3000);
                }}
                
                async function showVideoPreview(videoName) {{
                    try {{
                        showNotification('Loading video preview...', 'success');
                        
                        const overlay = document.getElementById('videoPreviewOverlay');
                        const player = document.getElementById('videoPreviewPlayer');
                        const source = player.querySelector('source');
                        
                        source.src = videoName;
                        player.load();
                        overlay.style.display = 'flex';
                        
                        player.addEventListener('loadedmetadata', function() {{
                            player.currentTime = 2;
                            showNotification('Video preview ready!', 'success');
                        }}, {{ once: true }});
                        
                    }} catch (error) {{
                        showNotification('Failed to load video preview', 'error');
                    }}
                }}
                
                function closeVideoPreview() {{
                    const overlay = document.getElementById('videoPreviewOverlay');
                    const player = document.getElementById('videoPreviewPlayer');
                    
                    player.pause();
                    player.currentTime = 0;
                    overlay.style.display = 'none';
                }}
                
                async function playVideo(videoName) {{
                    try {{
                        showNotification('Opening video...', 'success');
                        window.open(`/play/${{encodeURIComponent(videoName)}}`, '_blank');
                    }} catch (error) {{
                        showNotification('Failed to play video', 'error');
                    }}
                }}
                
                async function downloadFile(fileName) {{
                    try {{
                        console.log('Download requested for:', fileName);
                        showNotification(`Starting download: ${{fileName}}`, 'success');
                        
                        // Create download link directly - let server handle validation
                        const downloadUrl = `/download/${{encodeURIComponent(fileName)}}`;
                        console.log('Download URL:', downloadUrl);
                        
                        const a = document.createElement('a');
                        a.href = downloadUrl;
                        a.download = fileName;
                        a.style.display = 'none';
                        document.body.appendChild(a);
                        a.click();
                        document.body.removeChild(a);
                        
                        showNotification(`Download initiated: ${{fileName}}`, 'success');
                        
                    }} catch (error) {{
                        console.error('Download error:', error);
                        showNotification(`Download failed: ${{error.message}}`, 'error');
                    }}
                }}
                
                document.addEventListener('DOMContentLoaded', function() {{
                    // Initialize video hover previews
                    initializeVideoHoverPreviews();
                    
                    // Download buttons
                    document.querySelectorAll('.download-btn').forEach(btn => {{
                        btn.addEventListener('click', function() {{
                            const fileName = this.dataset.file;
                            downloadFile(fileName);
                        }});
                    }});
                    
                    // Keyboard shortcuts
                    document.addEventListener('keydown', function(e) {{
                        if (e.key === 'Escape') {{
                            closeVideoPreview();
                        }}
                    }});
                    
                    // Update server status
                    updateServerStatus();
                }});
                
                function initializeVideoHoverPreviews() {{
                    document.querySelectorAll('.video-container').forEach(container => {{
                        const videoName = container.dataset.video;
                        const thumbnail = container.querySelector('.video-thumbnail');
                        const previewArea = container.querySelector('.video-preview-area');
                        const video = container.querySelector('.video-preview-player');
                        
                        let hoverTimer = null;
                        let previewTimer = null;
                        let isActivated = false;
                        
                        // Hover to show preview
                        thumbnail.addEventListener('mouseenter', function() {{
                            // Clear any existing timers
                            clearTimeout(hoverTimer);
                            clearTimeout(previewTimer);
                            
                            hoverTimer = setTimeout(() => {{
                                // Show preview area
                                thumbnail.style.display = 'none';
                                previewArea.style.display = 'block';
                                
                                // Load and play video
                                if (!isActivated) {{
                                    video.load();
                                    isActivated = true;
                                }}
                                
                                video.currentTime = 0;
                                video.play().then(() => {{
                                    showNotification(`Playing 60s preview: ${{videoName}}`, 'success');
                                    
                                    // Stop preview after 60 seconds
                                    previewTimer = setTimeout(() => {{
                                        video.pause();
                                        video.currentTime = 0;
                                        showNotification('Preview ended', 'success');
                                    }}, 60000);
                                }}).catch(error => {{
                                    console.log('Video preview failed:', error);
                                    showNotification('Preview failed to load', 'error');
                                }});
                            }}, 500); // 500ms delay before showing preview
                        }});
                        
                        // Mouse leave - hide preview after delay
                        previewArea.addEventListener('mouseleave', function() {{
                            clearTimeout(hoverTimer);
                            clearTimeout(previewTimer);
                            
                            setTimeout(() => {{
                                video.pause();
                                video.currentTime = 0;
                                previewArea.style.display = 'none';
                                thumbnail.style.display = 'flex';
                            }}, 200);
                        }});
                        
                        // Click preview to play full video
                        previewArea.addEventListener('click', function() {{
                            clearTimeout(previewTimer);
                            video.pause();
                            showNotification(`Opening full video: ${{videoName}}`, 'success');
                            
                            // Create a proper link and click it
                            const link = document.createElement('a');
                            link.href = encodeURIComponent(videoName);
                            link.target = '_blank';
                            link.rel = 'noopener noreferrer';
                            document.body.appendChild(link);
                            link.click();
                            document.body.removeChild(link);
                        }});
                        
                        // Also allow thumbnail click to immediately play
                        thumbnail.addEventListener('click', function() {{
                            clearTimeout(hoverTimer);
                            showNotification(`Opening video: ${{videoName}}`, 'success');
                            
                            // Create a proper link and click it
                            const link = document.createElement('a');
                            link.href = encodeURIComponent(videoName);
                            link.target = '_blank';
                            link.rel = 'noopener noreferrer';
                            document.body.appendChild(link);
                            link.click();
                            document.body.removeChild(link);
                        }});
                    }});
                }}
                
                async function updateServerStatus() {{
                    try {{
                        const response = await fetch('/api/status');
                        if (response.ok) {{
                            const status = await response.json();
                            const statusElement = document.getElementById('serverStatus');
                            statusElement.textContent = `🟢 Enhanced Server - ${{status.total_files}} files, ${{status.videos_count}} videos`;
                        }}
                    }} catch (error) {{
                        console.log('Status update failed:', error);
                    }}
                }}
            </script>
        </body>
        </html>
        '''
        
        return html
    
    def get_file_icon(self, filename):
        """Get appropriate icon for file type"""
        ext = os.path.splitext(filename)[1].lower()
        
        icon_map = {
            '.py': '🐍', '.js': '📜', '.html': '🌐', '.css': '🎨', '.json': '📋',
            '.txt': '📄', '.md': '📝', '.pdf': '📕', '.doc': '📘', '.docx': '📘',
            '.xls': '📗', '.xlsx': '📗', '.csv': '📊', '.log': '📋',
            '.zip': '📦', '.tar': '📦', '.gz': '📦', '.rar': '📦',
            '.exe': '⚙️', '.deb': '📦', '.rpm': '📦',
            '.sh': '⚡', '.bat': '⚡', '.cmd': '⚡'
        }
        
        return icon_map.get(ext, '📄')
    
    def find_file_by_name(self, filename):
        """Find a file by name starting from the current directory tree"""
        try:
            # Get the current working directory (the expanded path shown in the server)
            current_dir = os.getcwd()
            print(f"🔍 Searching for '{filename}' starting from: {current_dir}")
            
            # First check the current directory directly
            direct_path = os.path.join(current_dir, filename)
            if os.path.exists(direct_path):
                print(f"📍 Found '{filename}' directly at: '{direct_path}'")
                return direct_path
            
            # Then search all subdirectories recursively
            print(f"🔍 Searching subdirectories of: {current_dir}")
            for root, dirs, files in os.walk(current_dir):
                if filename in files:
                    found_path = os.path.join(root, filename)
                    print(f"📍 Found '{filename}' at: '{found_path}'")
                    return found_path
            
            # If not found in current tree, try parent directory tree
            parent_dir = os.path.dirname(current_dir)
            if parent_dir != current_dir and parent_dir != '/':  # Avoid infinite recursion
                print(f"🔍 Searching parent directory tree: {parent_dir}")
                for root, dirs, files in os.walk(parent_dir):
                    # Limit to reasonable depth to avoid excessive searching
                    level = root.replace(parent_dir, '').count(os.sep)
                    if level >= 4:  # Max 4 levels deep
                        dirs[:] = []
                        continue
                        
                    if filename in files:
                        found_path = os.path.join(root, filename)
                        print(f"📍 Found '{filename}' in parent tree at: '{found_path}'")
                        return found_path
            
            print(f"❌ File '{filename}' not found in directory tree")
            return None
            
        except Exception as e:
            print(f"❌ Error in file search for '{filename}': {e}")
            return None
    
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
    
    def log_message(self, format, *args):
        """Custom logging"""
        timestamp = time.strftime('%H:%M:%S')
        print(f"[{timestamp}] {format % args}")

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
        with ThreadingHTTPServer((bind_host, args.port), EnhancedNavigationHandler) as httpd:
            httpd.serve_forever()
            
    except KeyboardInterrupt:
        print("\n🛑 Server stopped by user")
    except OSError as e:
        if e.errno == 98:
            print(f"❌ Error: Port {args.port} is already in use")
            print(f"💡 Try a different port: python3 {sys.argv[0]} --port {args.port + 1}")
        else:
            print(f"❌ Server error: {e}")
    except Exception as e:
        print(f"❌ Unexpected error: {e}")

if __name__ == "__main__":
    main()