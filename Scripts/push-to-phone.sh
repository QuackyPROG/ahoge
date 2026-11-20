#!/usr/bin/env bash
# Keeps Ahoge current on the iPhone from WSL: builds new commits of a branch, installs them over Wi-Fi (or USB),
# and re-signs before the free Apple ID's 7 days run out. Safe to run on a timer; see Scripts/install-push-task.ps1.
# Usage: push-to-phone.sh [branch] [--force] [--quiet-hours HH-HH]
# Installing kills the running app, so new commits install only inside the quiet window (local hours, start inclusive,
# end exclusive, default 02-06, may wrap midnight like 22-06). --force installs at once, at any hour, and even when the
# branch is behind what is on the phone. Re-signing runs inside the window after 3 days, and outside it after 6 days.
# The Windows task does not wake the PC; if it is usually off at night, move the window with -QuietHours.
set -euo pipefail

branch="main"
force=false
quiet="02-06"
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=true ;;
    --quiet-hours) quiet="${2-}"; shift ;;
    *) branch="$1" ;;
  esac
  shift || true
done

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/push-policy.sh"
home="${AHOGE_PUSH_DIR:-$HOME/.ahoge-push}"
remote="https://github.com/QuackyPROG/ahoge.git"
mkdir -p "$home"

log() { echo "$(date '+%F %T') $*"; }

# Checked before output moves to the log, so a mistyped window also shows on the terminal.
if ! quiet_hours_valid "$quiet"; then
  log "invalid --quiet-hours '$quiet'; expected HH-HH with hours 00-23 and start different from end" | tee -a "$home/push.log" >&2
  exit 1
fi

exec >>"$home/push.log" 2>&1
exec 9>"$home/lock"
flock -n 9 || exit 0

hour="$(date +%H)"
log "local hour $hour, quiet window $quiet"

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
should_resign "$quiet" "$hour" $(($(date +%s) - signed_at)) && due=true

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

if ! should_install "$quiet" "$hour" "$force"; then
  log "waiting for quiet window $quiet (now $hour)"
# Older builds can't read a newer library, so a branch that went backwards never lands by itself.
elif [ -n "$installed" ] && ! $force && ! git merge-base --is-ancestor "$installed" "$head"; then
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
