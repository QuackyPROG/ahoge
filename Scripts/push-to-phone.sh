#!/usr/bin/env bash
# Keeps Ahoge current on the iPhone from WSL: builds new commits of a branch, installs them over Wi-Fi (or USB),
# and re-signs before the free Apple ID's 7 days run out. Safe to run on a timer; see Scripts/install-push-task.ps1.
# Usage: push-to-phone.sh [branch] [--force]    --force installs even when the branch is behind what is on the phone.
set -euo pipefail

branch="main"
force=false
for arg in "$@"; do
  case "$arg" in
    --force) force=true ;;
    *) branch="$arg" ;;
  esac
done

here="$(cd "$(dirname "$0")" && pwd)"
home="${AHOGE_PUSH_DIR:-$HOME/.ahoge-push}"
remote="https://github.com/QuackyPROG/ahoge.git"
resign_after=$((3 * 24 * 60 * 60))
mkdir -p "$home"
exec >>"$home/push.log" 2>&1
exec 9>"$home/lock"
flock -n 9 || exit 0

log() { echo "$(date '+%F %T') $*"; }

started_relay=false
cleanup() {
  if $started_relay; then
    sudo pkill -x socat || true
    sudo rm -f /var/run/usbmuxd
  fi
}
trap cleanup EXIT

if ! pgrep -x socat >/dev/null; then
  setsid bash "$here/wsl-usbmux.sh" >/dev/null 2>&1 &
  started_relay=true
  for _ in {1..10}; do
    [ -S /var/run/usbmuxd ] && break
    sleep 1
  done
fi

# Wi-Fi first: a phone that is also plugged in is listed twice, and xtool would stop to ask which one.
mode=""
for candidate in --network --usb; do
  if [ -n "$(timeout 30 xtool devices "$candidate" --no-wait 2>/dev/null)" ]; then
    mode="$candidate"
    break
  fi
done
if [ -z "$mode" ]; then
  log "iPhone not reachable; trying again next run"
  exit 0
fi

[ -d "$home/repo/.git" ] || git clone --quiet "$remote" "$home/repo"
cd "$home/repo"
git fetch --quiet origin "$branch"
head="$(git rev-parse FETCH_HEAD)"

installed="$(cat "$home/installed-commit" 2>/dev/null || true)"
signed_at="$(cat "$home/installed-at" 2>/dev/null || echo 0)"
due=false
[ $(($(date +%s) - signed_at)) -ge "$resign_after" ] && due=true

# Runs under `if`, where set -e is off, so each step that can fail stops the build itself.
build() {
  git checkout --quiet --force --detach "$head" || return 1
  git clean --quiet -fd -e .build -e xtool || return 1
  sed -i "/<key>CFBundleVersion<\/key>/{n;s|<string>.*</string>|<string>$(git rev-list --count HEAD)</string>|}" Info-xtool.plist
  sed -i "0,/<dict>/s|<dict>|<dict>\n\t<key>AhogeCommit</key>\n\t<string>${head:0:7}</string>|" Info-xtool.plist
  xtool dev build -c release || return 1
  rm -rf "$home/Ahoge.app"
  cp -R xtool/Ahoge.app "$home/Ahoge.app"
}

deploy() {
  xtool install "$mode" "$home/Ahoge.app"
  date +%s >"$home/installed-at"
  echo "$1" >"$home/installed-commit"
}

if [ "$head" = "$installed" ]; then
  if $due; then
    log "re-signing ${installed:0:7}"
    deploy "$installed"
  fi
  exit 0
fi

# Older builds can't read a newer library, so a branch that went backwards never lands by itself.
if [ -n "$installed" ] && ! $force && ! git merge-base --is-ancestor "$installed" "$head"; then
  log "$branch (${head:0:7}) does not contain ${installed:0:7} from the phone; not installing it (--force overrides)"
else
  log "building $branch ${head:0:7}"
  if build; then
    log "installing ${head:0:7} ($mode)"
    deploy "$head"
    log "installed ${head:0:7}"
    exit 0
  fi
  log "build failed for ${head:0:7}"
fi

# A commit that can't land must not let the signature lapse.
if $due && [ -d "$home/Ahoge.app" ]; then
  log "re-signing ${installed:0:7}"
  deploy "$installed"
fi
