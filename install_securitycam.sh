#!/bin/bash

# =============================
# Security Cam Installer (MJPEG)
# Raspberry Pi Zero 2 W (Bookworm)
# =============================

PROJECT_DIR="/opt/securitycam"
SERVICE_NAME="securitycam"
STREAM_SERVICE="${SERVICE_NAME}_stream"
CONFIG_FILE="$PROJECT_DIR/config.json"
FRAME_FILE="$PROJECT_DIR/latest.jpg"
WEB_PORT=8080

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Run this script as root (sudo)${NC}"
  exit 1
fi

function uninstall() {
  echo -e "${YELLOW}Uninstalling...${NC}"
  systemctl stop $SERVICE_NAME.service
  systemctl stop $STREAM_SERVICE.service
  systemctl disable $SERVICE_NAME.service
  systemctl disable $STREAM_SERVICE.service
  rm -f /etc/systemd/system/$SERVICE_NAME.service
  rm -f /etc/systemd/system/$STREAM_SERVICE.service
  systemctl daemon-reload
  rm -rf "$PROJECT_DIR"
  apt remove -y libcamera-apps python3-pip jq
  apt autoremove -y
  echo -e "${GREEN}✅ Uninstalled${NC}"
  exit 0
}

function reinstall() {
  uninstall
  install
}

function install_dependencies() {
  apt update
  apt install -y libcamera-apps python3-pip jq
  pip3 install flask flask-cors --break-system-packages
}

function create_project_files() {
  mkdir -p "$PROJECT_DIR/templates"

  # Default config
  cat > "$CONFIG_FILE" <<EOF
{
  "width": 1920,
  "height": 1080,
  "fps": 15,
  "bitrate": 5000000,
  "rotation": 0,
  "brightness": 0,
  "contrast": 1.0
}
EOF

  # Flask Web App
  cat > "$PROJECT_DIR/webapp.py" <<'EOF'
from flask import Flask, render_template, request, jsonify, Response
import json, os, time, subprocess

app = Flask(__name__)
config_file = "/opt/securitycam/config.json"
frame_file = "/opt/securitycam/latest.jpg"

def get_config():
    with open(config_file) as f:
        return json.load(f)

@app.route('/')
def index():
    config = get_config()
    return render_template('index.html', config=config)

@app.route('/video_feed')
def video_feed():
    def generate():
        while True:
            if os.path.exists(frame_file):
                with open(frame_file, 'rb') as f:
                    frame = f.read()
                    yield (b'--frame\r\n'
                           b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')
            time.sleep(1 / get_config().get("fps", 15))

    return Response(generate(),
                    mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/get_config', methods=['GET'])
def api_get_config():
    return jsonify(get_config())

@app.route('/update_config', methods=['POST'])
def api_update_config():
    config = get_config()
    new = request.json
    config['width'] = max(640, min(2592, int(new.get('width', config['width']))))
    config['height'] = max(480, min(1944, int(new.get('height', config['height']))))
    config['fps'] = max(1, min(30, int(new.get('fps', config['fps']))))
    config['rotation'] = int(new.get('rotation', config['rotation'])) % 360
    config['brightness'] = max(-1.0, min(1.0, float(new.get('brightness', config['brightness']))))
    config['contrast'] = max(0.0, min(2.0, float(new.get('contrast', config['contrast']))))

    with open(config_file, 'w') as f:
        json.dump(config, f, indent=4)

    subprocess.run(["systemctl", "restart", "securitycam_stream.service"])
    return jsonify({"status": "success", "config": config})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, threaded=True)
EOF

  # HTML Template
  cat > "$PROJECT_DIR/templates/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Security Camera</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light p-4">
  <div class="container">
    <h1 class="mb-4 text-center">📷 Security Camera</h1>
    <div class="row">
      <div class="col-md-8">
        <img src="{{ url_for('video_feed') }}" class="img-fluid rounded shadow" alt="Camera Feed">
      </div>
      <div class="col-md-4">
        <form id="settingsForm" class="p-3 bg-white shadow rounded">
          <h4>Settings</h4>
          <div class="mb-2"><label>Width</label><input type="number" id="width" class="form-control" value="{{ config.width }}"></div>
          <div class="mb-2"><label>Height</label><input type="number" id="height" class="form-control" value="{{ config.height }}"></div>
          <div class="mb-2"><label>FPS</label><input type="number" id="fps" class="form-control" value="{{ config.fps }}"></div>
          <div class="mb-2"><label>Rotation</label><input type="number" id="rotation" class="form-control" value="{{ config.rotation }}"></div>
          <div class="mb-2"><label>Brightness</label><input type="number" step="0.1" id="brightness" class="form-control" value="{{ config.brightness }}"></div>
          <div class="mb-2"><label>Contrast</label><input type="number" step="0.1" id="contrast" class="form-control" value="{{ config.contrast }}"></div>
          <button type="submit" class="btn btn-primary mt-3">Save</button>
        </form>
      </div>
    </div>
  </div>
  <script>
    document.getElementById("settingsForm").addEventListener("submit", function(e) {
      e.preventDefault();
      const data = {
        width: +width.value,
        height: +height.value,
        fps: +fps.value,
        rotation: +rotation.value,
        brightness: +brightness.value,
        contrast: +contrast.value
      };
      fetch('/update_config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      }).then(res => res.json()).then(res => {
        alert('Settings saved! Stream will restart.');
        location.reload();
      });
    });
  </script>
</body>
</html>
EOF

  # MJPEG Camera Streamer
  cat > "$PROJECT_DIR/camera_streamer.sh" <<'EOF'
#!/bin/bash
CONFIG="/opt/securitycam/config.json"
OUTPUT="/opt/securitycam/latest.jpg"

while true; do
  CFG=$(cat "$CONFIG")
  WIDTH=$(echo "$CFG" | jq -r .width)
  HEIGHT=$(echo "$CFG" | jq -r .height)
  ROTATION=$(echo "$CFG" | jq -r .rotation)
  BRIGHTNESS=$(echo "$CFG" | jq -r .brightness)
  CONTRAST=$(echo "$CFG" | jq -r .contrast)
  FPS=$(echo "$CFG" | jq -r .fps)

  libcamera-jpeg -n -o "$OUTPUT" --width $WIDTH --height $HEIGHT \
    --rotation $ROTATION --brightness $BRIGHTNESS --contrast $CONTRAST \
    --quality 90 --timeout $((1000 / FPS)) >/dev/null 2>&1
done
EOF
  chmod +x "$PROJECT_DIR/camera_streamer.sh"
}

function create_services() {
  # Web UI Service
  cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Security Camera Web UI
After=network.target

[Service]
ExecStart=/usr/bin/python3 $PROJECT_DIR/webapp.py
WorkingDirectory=$PROJECT_DIR
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  # MJPEG Streamer Service
  cat > "/etc/systemd/system/$STREAM_SERVICE.service" <<EOF
[Unit]
Description=Security Camera Streamer
After=network.target

[Service]
ExecStart=$PROJECT_DIR/camera_streamer.sh
WorkingDirectory=$PROJECT_DIR
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl enable "$STREAM_SERVICE"
  systemctl start "$SERVICE_NAME"
  systemctl start "$STREAM_SERVICE"
}

function install() {
  install_dependencies
  create_project_files
  create_services

  echo -e "${GREEN}====================================${NC}"
  echo -e "${GREEN} ✅  Installed and Running!${NC}"
  echo -e "${GREEN} 🔄  Reboot recommended${NC}"
  echo -e "${GREEN} 🌐  Web UI: http://$(hostname -I | awk '{print $1}'):$WEB_PORT${NC}"
  echo -e "${GREEN} 🧹  Uninstall: ./install_securitycam.sh --uninstall${NC}"
  echo -e "${GREEN} ♻️  Reinstall: ./install_securitycam.sh --reinstall${NC}"
  echo -e "${GREEN}====================================${NC}"
}

case "$1" in
  --uninstall) uninstall ;;
  --reinstall) reinstall ;;
  *) install ;;
esac
