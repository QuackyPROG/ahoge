#!/usr/bin/env bash
# Serves /var/run/usbmuxd in WSL from Windows' Apple Mobile Device Service, so xtool reaches the iPhone without usbipd.
# Needs the Apple Devices app (or iTunes) on Windows and the phone plugged into Windows. Leave it running while you use xtool.
set -euo pipefail
# Passed by env var: socat can't parse the colon in a Windows path.
relay="$(wslpath -w "$(cd "$(dirname "$0")" && pwd)/usbmux-relay.ps1")"
sudo systemctl stop usbmuxd.service usbmuxd.socket 2>/dev/null || true
sudo rm -f /var/run/usbmuxd
sudo RELAY="$relay" socat UNIX-LISTEN:/var/run/usbmuxd,fork,mode=666 \
  SYSTEM:'exec /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$RELAY"'
