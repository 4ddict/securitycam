#!/bin/bash

PROJECT_DIR="$HOME/securitycam"
SERVICE_NAME="securitycam"
PORT=8080

function install_dependencies() {
  sudo apt update
  sudo apt install -y python3 python3-pip lighttpd libcamera-apps uv4l
  pip3 install flask
}

function setup_project() {
  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR" || exit 1

  # Flask App
  cat > app.py <<EOF
from flask import Flask, render_template, request, redirect, url_for
import os

app = Flask(__name__)

CONFIG_FILE = "config.txt"

def read_config():
    if not os.path.exists(CONFIG_FILE):
        return {"width": 1920, "height": 1080, "fps": 15}
    with open(CONFIG_FILE) as f:
        data = f.read().split(',')
        return {"width": int(data[0]), "height": int(data[1]), "fps": int(data[2])}

def write_config(config):
    with open(CONFIG_FILE, 'w') as f:
        f.write(f"{config['width']},{config['height']},{config['fps']}")

@app.route("/", methods=["GET", "POST"])
def index():
    config = read_config()
    if request.method == "POST":
        config["width"] = int(request.form["width"])
        config["height"] = int(request.form["height"])
        config["fps"] = int(request.form["fps"])
        write_config(config)
        os.system("systemctl restart securitycam.service")
        return redirect(url_for("index"))
    return render_template("index.html", config=config)

@app.route("/video")
def video():
    return redirect(f"http://localhost:8081")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=$PORT)
EOF

  # HTML Template
  mkdir -p templates
  cat > templates/index.html <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Security Cam</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-dark text-light">
  <div class="container py-5">
    <h1 class="mb-4">📷 Security Camera</h1>
    <div class="mb-4">
      <iframe src="/video" width="100%" height="540" frameborder="0"></iframe>
    </div>
    <form method="POST" class="bg-secondary p-4 rounded">
      <h4>Settings</h4>
      <div class="row g-2 mb-3">
        <div class="col">
          <label>Width</label>
          <input type="number" name="width" class="form-control" value="{{ config.width }}">
        </div>
        <div class="col">
          <label>Height</label>
          <input type="number" name="height" class="form-control" value="{{ config.height }}">
        </div>
        <div class="col">
          <label>FPS</label>
          <input type="number" name="fps" class="form-control" value="{{ config.fps }}">
        </div>
      </div>
      <button type="submit" class="btn btn-light">Save & Restart</button>
    </form>
  </div>
</body>
</html>
EOF

  # Default config
  echo "1920,1080,15" > config.txt
}

function create_stream_service() {
  sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Security Cam Streaming Service
After=network.target

[Service]
ExecStart=/bin/bash -c 'cd $PROJECT_DIR && ./start_stream.sh'
Restart=always
User=$USER

[Install]
WantedBy=multi-user.target
EOF
}

function create_stream_script() {
  cat > "$PROJECT_DIR/start_stream.sh" <<'EOF'
#!/bin/bash

cd "$(dirname "$0")" || exit 1
read -r WIDTH HEIGHT FPS < <(tr ',' ' ' < config.txt)

# Kill old stream
pkill -f libcamera-vid

# Start new stream
libcamera-vid -t 0 --inline --width $WIDTH --height $HEIGHT --framerate $FPS -o - | cvlc - --sout '#standard{access=http,mux=ts,dst=:8081}' :demux=h264
EOF
  chmod +x "$PROJECT_DIR/start_stream.sh"
}

function create_flask_service() {
  sudo tee /etc/systemd/system/${SERVICE_NAME}_web.service > /dev/null <<EOF
[Unit]
Description=Security Cam Flask Web Server
After=network.target

[Service]
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/python3 $PROJECT_DIR/app.py
Restart=always
User=$USER

[Install]
WantedBy=multi-user.target
EOF
}

function enable_services() {
  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload
  sudo systemctl enable ${SERVICE_NAME}.service
  sudo systemctl enable ${SERVICE_NAME}_web.service
  sudo systemctl start ${SERVICE_NAME}.service
  sudo systemctl start ${SERVICE_NAME}_web.service
}

function uninstall() {
  echo "Uninstalling..."

  sudo systemctl stop ${SERVICE_NAME}.service
  sudo systemctl stop ${SERVICE_NAME}_web.service
  sudo systemctl disable ${SERVICE_NAME}.service
  sudo systemctl disable ${SERVICE_NAME}_web.service
  sudo rm -f /etc/systemd/system/${SERVICE_NAME}*.service
  sudo systemctl daemon-reload

  rm -rf "$PROJECT_DIR"

  echo "✅ Uninstalled!"
  exit 0
}

function reinstall() {
  uninstall
  install
}

function install() {
  install_dependencies
  setup_project
  create_stream_script
  create_stream_service
  create_flask_service
  enable_services

  echo "===================================="
  echo " ✅  Installed and Running!"
  echo " 🔄  Reboot recommended"
  echo " 🌐  Web UI: http://$(hostname -I | awk '{print $1}'):8080"
  echo " 🧹  Uninstall: ./install_securitycam.sh --uninstall"
  echo " ♻️  Reinstall: ./install_securitycam.sh --reinstall"
  echo "===================================="
}

case "$1" in
  --uninstall)
    uninstall
    ;;
  --reinstall)
    reinstall
    ;;
  *)
    install
    ;;
esac
