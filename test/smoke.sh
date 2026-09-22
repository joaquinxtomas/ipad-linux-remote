#!/usr/bin/env bash
set -euo pipefail

project_dir=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/..")
display=:98
runtime_dir=${XDG_RUNTIME_DIR:-/tmp}/remote-desktop
auth_file=$runtime_dir/Xauthority.98
profile_dir=$(mktemp -d /tmp/remote-desktop-firefox.XXXXXX)
password_file=$profile_dir/vnc.passwd
launcher_pid=
firefox_pid=

cleanup() {
    [[ -n $firefox_pid ]] && kill "$firefox_pid" 2>/dev/null || true
    [[ -n $launcher_pid ]] && kill "$launcher_pid" 2>/dev/null || true
    [[ -n $firefox_pid ]] && wait "$firefox_pid" 2>/dev/null || true
    [[ -n $launcher_pid ]] && wait "$launcher_pid" 2>/dev/null || true
    case $profile_dir in
        /tmp/remote-desktop-firefox.*) rm -rf -- "$profile_dir" ;;
    esac
}
trap cleanup EXIT INT TERM HUP

printf 'smoketest\n' | vncpasswd -f >"$password_file"
chmod 600 "$password_file"

REMOTE_DESKTOP_DISPLAY=$display \
    REMOTE_DESKTOP_VNC_PASSWORD_FILE=$password_file \
    "$project_dir/bin/start-desktop" \
    >/tmp/remote-desktop-smoke.log 2>&1 &
launcher_pid=$!

for _ in {1..100}; do
    curl -fsS http://127.0.0.1:6080/ >/dev/null 2>&1 && break
    kill -0 "$launcher_pid" 2>/dev/null || {
        cat /tmp/remote-desktop-smoke.log >&2
        exit 1
    }
    sleep 0.1
done
curl -fsS http://127.0.0.1:6080/ | grep 'iPad Linux Remote' >/dev/null
curl -fsS http://127.0.0.1:6080/manifest.webmanifest | grep 'Linux Remote' >/dev/null
curl -fsS http://127.0.0.1:6080/icon.svg | grep '<svg' >/dev/null

if REMOTE_DESKTOP_DISPLAY=$display \
    REMOTE_DESKTOP_VNC_PASSWORD_FILE=$password_file \
    "$project_dir/bin/start-desktop" >/tmp/remote-desktop-second.log 2>&1; then
    echo "second launcher unexpectedly started" >&2
    exit 1
fi
grep -q 'already running' /tmp/remote-desktop-second.log

url='http://127.0.0.1:6080/?scale=1.25#password=smoketest'
firefox --headless --no-remote --profile "$profile_dir" \
    --width 1200 --height 900 "$url" >/tmp/remote-desktop-firefox.log 2>&1 &
firefox_pid=$!

resized=false
for _ in {1..200}; do
    size=$(XAUTHORITY=$auth_file xrandr --display "$display" --current 2>/dev/null \
        | sed -n '1s/.*current \([0-9]*\) x \([0-9]*\).*/\1x\2/p' || true)
    if [[ -n $size && $size != 1366x1024 ]]; then
        resized=true
        break
    fi
    sleep 0.1
done
$resized || {
    cat /tmp/remote-desktop-smoke.log >&2
    cat /tmp/remote-desktop-firefox.log >&2
    echo "noVNC did not resize the remote desktop" >&2
    exit 1
}

width=${size%x*}
height=${size#*x}
((width >= 1450 && width <= 1550 && height >= 950 && height <= 1100))
XAUTHORITY=$auth_file xrandr --display "$display" --query \
    | grep -Eq '^VNC-0 connected primary'

kill "$firefox_pid"
wait "$firefox_pid" 2>/dev/null || true
firefox_pid=

url='http://127.0.0.1:6080/?scale=1.25#password=wrong-password'
firefox --headless --no-remote --profile "$profile_dir" \
    --width 1200 --height 900 "$url" >/tmp/remote-desktop-firefox.log 2>&1 &
firefox_pid=$!
sleep 3
[[ $(grep -c 'AuthFailureException' /tmp/remote-desktop-smoke.log || true) == 1 ]]

echo "smoke: balanced noVNC connected and remotely resized Xvnc to $size"
