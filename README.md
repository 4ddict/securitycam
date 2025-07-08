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
