#!/usr/bin/env python3

"""
Remote Advanced File Browser
A comprehensive HTTP server for browsing, filtering, and downloading files
Based on the ENDS file browser layout and styling
"""

import http.server
import socketserver
import os
import sys
import json
from urllib.parse import unquote
import mimetypes
import time
from collections import defaultdict

class RemoteFileServerHandler(http.server.SimpleHTTPRequestHandler):
    """Advanced file browser with ENDS-style layout and navigation"""
    
    def __init__(self, *args, **kwargs):
        # Setup comprehensive MIME types
        mimetypes.add_type('text/html', '.html')
        mimetypes.add_type('text/html', '.htm')
        mimetypes.add_type('text/css', '.css')
        mimetypes.add_type('application/javascript', '.js')
        mimetypes.add_type('application/json', '.json')
        mimetypes.add_type('text/plain', '.log')
        mimetypes.add_type('text/plain', '.txt')
        mimetypes.add_type('text/x-shellscript', '.sh')
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        """Handle GET requests with error handling and logging"""
        try:
            # Log the request type
            if self.path == '/':
                print(f"📁 Directory access: {self.path} (root)")
            elif self.path.endswith('/'):
                print(f"📁 Directory navigation: {self.path}")
            elif '/' in self.path:
                if any(self.path.lower().endswith(ext) for ext in ['.html', '.htm', '.txt', '.md', '.log', '.py', '.sh', '.json', '.csv']):
                    print(f"👁️ File viewing: {self.path}")
                else:
                    print(f"⬇️ File download: {self.path}")
            else:
                print(f"📄 File access: {self.path}")
            
            # Call the parent's do_GET method with error handling
            super().do_GET()
            
        except Exception as e:
            # Handle any exceptions gracefully
            try:
                self.send_error(500, f"Internal server error")
            except:
                pass  # If we can't even send an error, just continue
    
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
        
        # Prevent aggressive caching
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        
        super().end_headers()
    
    def log_message(self, format, *args):
        """Override to suppress default HTTP log messages"""
        pass
    
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
        
        # Get display path
        display_path = unquote(self.path)
        if display_path == '/':
            display_path = '/'
        
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
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 15px;
            padding: 20px;
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
            line-height: 1.3;
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
            display: flex;
            justify-content: space-between;
            margin-top: 12px;
            font-size: 0.9em;
            color: #aaa;
        }}
        .file-size {{
            font-weight: 600;
            color: #4fc3f7;
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
    </script>
</body>
</html>'''
        
        return html
    
    def generate_navigation_html(self, path):
        """Generate ENDS-style navigation section"""
        display_path = unquote(self.path)
        navigation_html = '''
        <div class="category-section" style="border-left-color: #4fc3f7;">
            <div class="category-header" style="border-left-color: #4fc3f7;">
                <span>🧭 Directory Navigation</span>
            </div>
            <div class="category-content">
                <div class="file-grid">
'''
        
        # Add parent directory if not at root
        if display_path != '/' and display_path != '':
            parent_path = os.path.dirname(display_path.rstrip('/'))
            if parent_path == '':
                parent_path = '/'
            parent_name = os.path.basename(parent_path) if parent_path != '/' else 'Root'
            
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
                            <span class="file-size">Directory</span>
                            <span>{parent_path}</span>
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
                            <span class="file-size">Directory</span>
                            <span>{display_path}</span>
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
                            <span class="file-size">{file_count} files</span>
                            <span>Subdirectory</span>
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
                    details = f'<span class="file-size">Directory</span><span>Subdirectory</span>'
                else:
                    _, ext = os.path.splitext(file_info['name'].lower())
                    file_icon = self.get_file_icon(ext)
                    actions = f'<a href="{file_info["name"]}" class="action-btn view-btn">View</a><a href="{file_info["name"]}" download class="action-btn download-btn">Download</a>'
                    details = f'<span class="file-size">{file_info["size"]}</span><span>{file_info["modified"]}</span>'
                
                files_html.append(f'''
                    <div class="file-item" data-filename="{file_info['name'].lower()}" data-original-name="{file_info['name']}" data-extension="{ext if not file_info['is_dir'] else ''}" data-size-bytes="{file_info['size_bytes']}" data-modified="{file_info['modified']}" data-hidden="false">
                        <div class="file-header">
                            <span class="file-icon">{file_icon}</span>
                            <div class="file-name">{file_info['name']}</div>
                        </div>
                        <div class="file-actions">
                            {actions}
                        </div>
                        <div class="file-details">
                            {details}
                        </div>
                    </div>
                ''')
            
            sections_html.append(f'''
                <div class="category-section">
                    <div class="category-header">
                        <span>{category_icon} {category} ({count})</span>
                    </div>
                    <div class="category-content">
                        <div class="file-grid">
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


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Remote Advanced File Browser")
    parser.add_argument("--port", "-p", type=int, default=8081, help="Port to serve on (default: 8081)")
    parser.add_argument("--directory", "-d", type=str, help="Directory to serve (default: current directory)")
    
    args = parser.parse_args()
    run_server(args.port, args.directory)