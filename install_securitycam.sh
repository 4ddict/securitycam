#!/bin/bash

# Security Camera Installation Script
# For Raspberry Pi Zero W 2 with OV5647 camera
# Raspbian Lite (Bookworm) - May 2025 release

PROJECT_DIR="/opt/securitycam"
SERVICE_NAME="securitycam"
WEB_PORT=8080
CONFIG_FILE="$PROJECT_DIR/config.json"

# Default configuration
DEFAULT_CONFIG='{
    "width": 1920,
    "height": 1080,
    "fps": 15,
    "bitrate": 5000000,
    "rotation": 0,
    "brightness": 0,
    "contrast": 1.0
}'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root${NC}" >&2
    exit 1
fi

# Uninstall function
uninstall_securitycam() {
    echo -e "${YELLOW}Uninstalling security camera...${NC}"
    
    # Stop and disable service
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1
    systemctl disable "$SERVICE_NAME" >/dev/null 2>&1
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    
    # Remove project directory
    rm -rf "$PROJECT_DIR"
    
    # Remove dependencies
    apt-get remove -y ffmpeg python3-pip libcamera-apps
    apt-get autoremove -y
    
    echo -e "${GREEN}Security camera uninstalled successfully${NC}"
    exit 0
}

# Reinstall function
reinstall_securitycam() {
    uninstall_securitycam
    # Continue with installation
}

# Handle command line arguments
case "$1" in
    --uninstall)
        uninstall_securitycam
        ;;
    --reinstall)
        reinstall_securitycam
        ;;
esac

# Check if already installed
if [ -d "$PROJECT_DIR" ]; then
    echo -e "${YELLOW}Security camera seems to be already installed.${NC}"
    echo -e "Use ${GREEN}--reinstall${NC} to reinstall or ${GREEN}--uninstall${NC} to remove."
    exit 1
fi

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
apt-get update
apt-get install -y ffmpeg python3-pip libcamera-apps

# Install Python packages
pip3 install flask flask-cors

# Create project directory
echo -e "${YELLOW}Setting up project directory...${NC}"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR" || exit

# Create config file
echo "$DEFAULT_CONFIG" > "$CONFIG_FILE"

# Create web interface files
cat > "$PROJECT_DIR/webapp.py" << 'EOL'
from flask import Flask, render_template, request, jsonify, Response
import json
import os
import subprocess
from threading import Lock

app = Flask(__name__)
config_file = "/opt/securitycam/config.json"
config_lock = Lock()

def get_config():
    with open(config_file) as f:
        return json.load(f)

def save_config(config):
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=4)

@app.route('/')
def index():
    config = get_config()
    return render_template('index.html', config=config)

@app.route('/video_feed')
def video_feed():
    config = get_config()
    cmd = [
        'libcamera-vid',
        '-t', '0',
        '--width', str(config['width']),
        '--height', str(config['height']),
        '--framerate', str(config['fps']),
        '--bitrate', str(config['bitrate']),
        '--rotation', str(config['rotation']),
        '--brightness', str(config['brightness']),
        '--contrast', str(config['contrast']),
        '--inline',
        '--listen',
        '--codec', 'h264',
        '-o', 'tcp://127.0.0.1:5000'
    ]
    
    def generate():
        with subprocess.Popen(cmd, stdout=subprocess.PIPE) as proc:
            try:
                while True:
                    data = proc.stdout.read(1024)
                    if not data:
                        break
                    yield (b'--frame\r\n'
                           b'Content-Type: image/jpeg\r\n\r\n' + data + b'\r\n')
            finally:
                proc.terminate()
    
    return Response(generate(),
                    mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/get_config', methods=['GET'])
def api_get_config():
    return jsonify(get_config())

@app.route('/update_config', methods=['POST'])
def api_update_config():
    with config_lock:
        config = get_config()
        new_config = request.json
        
        # Validate parameters
        if 'width' in new_config:
            config['width'] = max(640, min(2592, int(new_config['width'])))
        if 'height' in new_config:
            config['height'] = max(480, min(1944, int(new_config['height'])))
        if 'fps' in new_config:
            config['fps'] = max(1, min(30, int(new_config['fps'])))
        if 'bitrate' in new_config:
            config['bitrate'] = max(1000000, min(10000000, int(new_config['bitrate'])))
        if 'rotation' in new_config:
            config['rotation'] = int(new_config['rotation']) % 360
        if 'brightness' in new_config:
            config['brightness'] = max(-1.0, min(1.0, float(new_config['brightness'])))
        if 'contrast' in new_config:
            config['contrast'] = max(0.0, min(2.0, float(new_config['contrast'])))
        
        save_config(config)
        return jsonify({"status": "success", "config": config})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, threaded=True)
EOL

# Create HTML template
mkdir -p "$PROJECT_DIR/templates"
cat > "$PROJECT_DIR/templates/index.html" << 'EOL'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Camera</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body {
            padding: 20px;
            background-color: #f8f9fa;
        }
        .camera-container {
            background-color: #000;
            margin-bottom: 20px;
            border-radius: 5px;
            overflow: hidden;
        }
        .settings-panel {
            background-color: white;
            border-radius: 5px;
            padding: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .status-badge {
            font-size: 0.9rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="text-center mb-4">Security Camera</h1>
        
        <div class="row">
            <div class="col-md-8">
                <div class="camera-container">
                    <img src="{{ url_for('video_feed') }}" class="img-fluid" alt="Camera Feed">
                </div>
            </div>
            
            <div class="col-md-4">
                <div class="settings-panel">
                    <h4>Camera Settings</h4>
                    <form id="settingsForm">
                        <div class="mb-3">
                            <label for="width" class="form-label">Width</label>
                            <input type="number" class="form-control" id="width" name="width" value="{{ config.width }}">
                        </div>
                        <div class="mb-3">
                            <label for="height" class="form-label">Height</label>
                            <input type="number" class="form-control" id="height" name="height" value="{{ config.height }}">
                        </div>
                        <div class="mb-3">
                            <label for="fps" class="form-label">FPS</label>
                            <input type="number" class="form-control" id="fps" name="fps" value="{{ config.fps }}">
                        </div>
                        <div class="mb-3">
                            <label for="rotation" class="form-label">Rotation (0-360)</label>
                            <input type="number" class="form-control" id="rotation" name="rotation" value="{{ config.rotation }}">
                        </div>
                        <div class="mb-3">
                            <label for="brightness" class="form-label">Brightness (-1.0 to 1.0)</label>
                            <input type="number" step="0.1" class="form-control" id="brightness" name="brightness" value="{{ config.brightness }}">
                        </div>
                        <div class="mb-3">
                            <label for="contrast" class="form-label">Contrast (0.0 to 2.0)</label>
                            <input type="number" step="0.1" class="form-control" id="contrast" name="contrast" value="{{ config.contrast }}">
                        </div>
                        <button type="submit" class="btn btn-primary">Save Settings</button>
                    </form>
                    
                    <div class="mt-4">
                        <h5>System Status</h5>
                        <div>
                            <span class="badge bg-success status-badge">Active</span>
                            <span class="status-badge">Streaming at {{ config.width }}x{{ config.height }} @{{ config.fps }}fps</span>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        document.getElementById('settingsForm').addEventListener('submit', function(e) {
            e.preventDefault();
            
            const formData = {
                width: parseInt(document.getElementById('width').value),
                height: parseInt(document.getElementById('height').value),
                fps: parseInt(document.getElementById('fps').value),
                rotation: parseInt(document.getElementById('rotation').value),
                brightness: parseFloat(document.getElementById('brightness').value),
                contrast: parseFloat(document.getElementById('contrast').value)
            };
            
            fetch('/update_config', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(formData)
            })
            .then(response => response.json())
            .then(data => {
                if (data.status === 'success') {
                    alert('Settings saved successfully! The video feed will restart with new settings.');
                    window.location.reload();
                } else {
                    alert('Error saving settings');
                }
            })
            .catch(error => {
                console.error('Error:', error);
                alert('Error saving settings');
            });
        });
    </script>
</body>
</html>
EOL

# Create systemd service file
cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOL
[Unit]
Description=Security Camera Service
After=network.target

[Service]
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/python3 $PROJECT_DIR/webapp.py
Restart=always
User=root
Group=root
Environment=PATH=/usr/bin:/usr/local/bin
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOL

# Enable and start service
echo -e "${YELLOW}Starting service...${NC}"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# Enable camera interface (not needed on Bookworm as it's auto-enabled)
# but just in case:
raspi-config nonint do_camera 0

echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN} ✅  Installed and Running!${NC}"
echo -e "${GREEN} 🔄  Reboot recommended${NC}"
echo -e "${GREEN} 🌐  Web UI: http://$(hostname -I | awk '{print $1}'):$WEB_PORT${NC}"
echo -e "${GREEN} 🧹  Uninstall: $0 --uninstall${NC}"
echo -e "${GREEN} ♻️  Reinstall: $0 --reinstall${NC}"
echo -e "${GREEN}====================================${NC}"
