# 📷 SecurityCam by Addict

**Lightweight, local-only security camera system for Raspberry Pi**  
Streams live MJPEG video at adjustable resolution and FPS. Includes a Bootstrap-based web interface for real-time settings.

> ✅ Optimized for Raspberry Pi Zero W 2 running Raspbian Lite (Bookworm, kernel 6.12)

---

## 🎯 Project Goals

- Live MJPEG video feed via web browser
- Web UI with adjustable:
  - 🖼 Resolution (1920x1080, 1280x720, etc.)
  - 🎞 Frame rate (FPS)
- Minimal dependencies for high performance
- Auto-start on boot using systemd
- Fully headless installation
- Clean uninstall & reinstall support

---

## 📦 What You’ll Need

| Component        | Model Tested     |
|------------------|------------------|
| Raspberry Pi     | Zero 2 W         |
| Camera Module    | OV5647           |

**OS:** Raspberry Pi OS Lite (Bookworm)  
**Kernel:** 6.12  
**Release Date:** May 13, 2025

---

## 🚀 Easy Install (1-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/4ddict/securitycam/main/install_securitycam.sh -o install_securitycam.sh && chmod +x install_securitycam.sh && ./install_securitycam.sh
```

---

## 🛠 Manual Install

```bash
chmod +x install_securitycam.sh
./install_securitycam.sh
```

Use `--uninstall` or `--reinstall` for cleanup or refresh.

---

## 🌐 Web Interface

- Web stream + settings: [http://YOUR_PI_IP:8080](http://YOUR_PI_IP:8080)
- MJPEG Stream URL: `http://YOUR_PI_IP:8080/?action=stream`  
  (Use this with compatible clients like VLC, Scrypted, or Home Assistant)

---

## 🧹 Management

| Action         | Command                              |
|----------------|---------------------------------------|
| ✅ Fresh install   | `./install_securitycam.sh`              |
| ♻️ Reinstall       | `./install_securitycam.sh --reinstall`  |
| ❌ Uninstall       | `./install_securitycam.sh --uninstall`  |

---

## 📦 What Gets Installed

- `mjpg-streamer` (compiled from source for speed)
- `Flask` (Python3) for web interface
- Bootstrap 5 for modern UI
- Systemd unit to run on boot
- Minimal dependencies (no desktop GUI required)

---

## ✅ Status

- ✅ Works headless on Pi Zero 2 W
- ✅ No manual camera config needed (uses `libcamera`)
- ✅ Tested on fresh Raspberry Pi OS Lite (Bookworm, May 2025)
- ✅ Fast boot + low CPU usage

---

## 👨‍💻 Author

Built with ❤️ by [**@4ddict**](https://github.com/4ddict)

Found a bug or want to contribute?  
Feel free to [open an issue](https://github.com/4ddict/securitycam/issues) or fork the project!
