#!/bin/bash
set -e

PROJECT_DIR="$HOME/securitycam"
SERVICE_NAME="cam.service"
STREAM_PORT=8080
PYTHON=$(which python3)

function uninstall() {
    echo "🧹 Uninstalling..."
    sudo systemctl stop cam.service || true
    sudo systemctl disable cam.service || true
    sudo rm -f /etc/systemd/system/$SERVICE_NAME
    sudo systemctl daemon-reload
    rm -rf "$PROJECT_DIR"
    echo "✅ Uninstalled successfully."
    exit 0
}

function install_deps() {
    echo "📦 Installing dependencies..."
    sudo apt update
    sudo apt install -y libcamera-apps python3 python3-pip python3-flask
}

function create_web_ui() {
    mkdir -p "$PROJECT_DIR/app/templates"
    mkdir -p "$PROJECT_DIR/app/static"

    cat <<EOF > "$PROJECT_DIR/app/templates/index.html"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>SecurityCam</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
  <div class="container py-4">
    <h1 class="mb-4">📷 SecurityCam</h1>
    <div class="row">
      <div class="col-md-8">
        <img src="http://{{ host }}:${STREAM_PORT}/stream.mjpg" class="img-fluid border">
      </div>
      <div class="col-md-4">
        <form method="post" action="/set">
          <div class="mb-3">
            <label class="form-label">Resolution</label>
            <select name="resolution" class="form-select">
              <option value="1920x1080">1920x1080</option>
              <option value="1280x720">1280x720</option>
              <option value="640x480">640x480</option>
            </select>
          </div>
          <div class="mb-3">
            <label class="form-label">FPS</label>
            <input type="number" name="fps" min="1" max="30" class="form-control" value="15">
          </div>
          <button type="submit" class="btn btn-primary">Apply</button>
        </form>
      </div>
    </div>
  </div>
</body>
</html>
EOF

    cat <<EOF > "$PROJECT_DIR/app/server.py"
from flask import Flask, render_template, request, redirect
import os
import subprocess

app = Flask(__name__)
config_path = os.path.expanduser("~/.cam_config")

@app.route("/")
def index():
    return render_template("index.html", host=request.host.split(":")[0])

@app.route("/set", methods=["POST"])
def set_config():
    resolution = request.form.get("resolution", "1920x1080")
    fps = request.form.get("fps", "15")
    with open(config_path, "w") as f:
        f.write(f"resolution={resolution}\\nfps={fps}\\n")
    os.system("sudo systemctl restart cam.service")
    return redirect("/")
EOF
}

function create_systemd_service() {
    cat <<EOF | sudo tee /etc/systemd/system/$SERVICE_NAME
[Unit]
Description=Security Camera Stream
After=network.target

[Service]
ExecStartPre=/bin/bash -c 'CONFIG=\$HOME/.cam_config; [ ! -f \$CONFIG ] && echo -e "resolution=1920x1080\\nfps=15" > \$CONFIG || true'
ExecStart=/bin/bash -c '
    source \$HOME/.cam_config
    libcamera-vid --inline --framerate \$fps --width \${resolution%x*} --height \${resolution#*x} --codec mjpeg -o - | \
    cvlc stream:///dev/stdin --sout "#standard{access=http,mux=mpjpeg,dst=:$STREAM_PORT/stream.mjpg}" --sout-keep &
    cd $PROJECT_DIR/app
    $PYTHON server.py
'
Restart=always
User=$USER

[Install]
WantedBy=multi-user.target
EOF
}

function main_install() {
    install_deps
    create_web_ui
    create_systemd_service
    sudo systemctl daemon-reload
    sudo systemctl enable cam.service
    sudo systemctl start cam.service
    echo "===================================="
    echo " ✅  Installed and Running!"
    echo " 🔄  Reboot recommended"
    echo " 🌐  Web UI: http://$(hostname -I | awk '{print \$1}'):8080"
    echo " 🧹  Uninstall: ./install_securitycam.sh --uninstall"
    echo " ♻️  Reinstall: ./install_securitycam.sh --reinstall"
    echo "===================================="
}

# Handle flags
if [[ "$1" == "--uninstall" ]]; then
    uninstall
elif [[ "$1" == "--reinstall" ]]; then
    uninstall
    main_install
else
    main_install
fi
