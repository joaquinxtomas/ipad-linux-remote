#!/usr/bin/env bash
# End-to-end check of the Selkies backend: auth, single instance, native
# resize for a Retina client, UI scale isolated from the physical desktop.
set -euo pipefail

project_dir=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/..")
display=:98
runtime_dir=${XDG_RUNTIME_DIR:-/tmp}/remote-desktop
auth_file=$runtime_dir/Xauthority.98
work_dir=$(mktemp -d /tmp/remote-desktop-selkies.XXXXXX)
password_file=$work_dir/selkies.passwd
profile_dir=$work_dir/firefox
log=/tmp/remote-desktop-selkies-smoke.log
launcher_pid=
firefox_pid=

cleanup() {
    [[ -n $firefox_pid ]] && kill "$firefox_pid" 2>/dev/null || true
    [[ -n $launcher_pid ]] && kill "$launcher_pid" 2>/dev/null || true
    [[ -n $firefox_pid ]] && wait "$firefox_pid" 2>/dev/null || true
    [[ -n $launcher_pid ]] && wait "$launcher_pid" 2>/dev/null || true
    case $work_dir in
        /tmp/remote-desktop-selkies.*) rm -rf -- "$work_dir" ;;
    esac
}
trap cleanup EXIT INT TERM HUP

fail() {
    echo "smoke-selkies: $*" >&2
    tail -n 30 "$log" >&2 || true
    exit 1
}

# Files Selkies would write into a shared home, and the physical UI scale.
home_files=("$HOME/.Xresources" "$HOME/.xsettingsd")
existing=()
for file in "${home_files[@]}"; do
    [[ -e $file ]] && existing+=("$file")
done
physical_scale=$(gsettings get org.cinnamon.desktop.interface scaling-factor 2>/dev/null || true)

(umask 077 && printf 'smoketest-selkies' >"$password_file")
REMOTE_DESKTOP_DISPLAY=$display REMOTE_DESKTOP_SELKIES_PASSWORD_FILE=$password_file \
    "$project_dir/bin/start-selkies" >"$log" 2>&1 &
launcher_pid=$!

code=
for _ in {1..120}; do
    code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:6080/ || true)
    [[ $code == 401 ]] && break
    kill -0 "$launcher_pid" 2>/dev/null || fail "launcher exited"
    sleep 0.25
done
[[ $code == 401 ]] || fail "expected 401 without credentials, got $code"
code=$(curl -s -o /dev/null -w '%{http_code}' -u ipad:wrong http://127.0.0.1:6080/)
[[ $code == 401 ]] || fail "expected 401 with a wrong password, got $code"
code=$(curl -s -o /dev/null -w '%{http_code}' -u ipad:smoketest-selkies http://127.0.0.1:6080/)
[[ $code == 200 ]] || fail "expected 200 with the password, got $code"
ss -ltn | grep -E '[^0-9.](0\.0\.0\.0|\*|\[::\]):6080 ' && fail "port 6080 is not loopback-only"

# The page and the assets it references are served.
asset=$(curl -fsS -u ipad:smoketest-selkies http://127.0.0.1:6080/ \
    | grep -oE 'src="\./assets/[^"]+\.js"' | head -n 1 | cut -d'"' -f2)
[[ -n $asset ]] || fail "page references no script"
code=$(curl -s -o /dev/null -w '%{http_code}' -u ipad:smoketest-selkies "http://127.0.0.1:6080/$asset")
[[ $code == 200 ]] || fail "asset $asset returned $code"

curl -fsS -u ipad:smoketest-selkies http://127.0.0.1:6080/ | grep -q 'viewport-fit=cover' \
    || fail "page does not cover the iPad safe areas"

# The manifest is password-protected and keeps the token for home-screen apps.
code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:6080/manifest.json)
[[ $code == 401 ]] || fail "manifest served without the password ($code)"
curl -fsS -u ipad:smoketest-selkies http://127.0.0.1:6080/manifest.json \
    | grep -q '"start_url": "./?token=smoketest-selkies"' || fail "manifest lacks the token"

# The stream's WebSocket needs the token, not Basic credentials.
ws() {
    curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H 'Connection: Upgrade' \
        -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
        -H 'Sec-WebSocket-Key: c21va2V0ZXN0c2Vsa2llcw==' "$@" || true
}
code=$(ws -u ipad:smoketest-selkies http://127.0.0.1:6080/api/websockets)
[[ $code == 401 ]] || fail "stream accepted without a token ($code)"
code=$(ws http://127.0.0.1:6080/api/websockets?token=smoketest-selkies)
[[ $code == 101 ]] || fail "stream refused the token ($code)"

if REMOTE_DESKTOP_DISPLAY=$display REMOTE_DESKTOP_SELKIES_PASSWORD_FILE=$password_file \
    "$project_dir/bin/start-selkies" >"$work_dir/second.log" 2>&1; then
    fail "second launcher unexpectedly started"
fi
grep -q 'already running' "$work_dir/second.log" || fail "no single-instance message"

# A Retina iPad: 1200x900 CSS pixels at devicePixelRatio 2.
mkdir -p "$profile_dir"
cat >"$profile_dir/user.js" <<'EOF'
user_pref("network.http.phishy-userpass-length", 255);
user_pref("layout.css.devPixelsPerPx", "2.0");
EOF
firefox --headless --no-remote --profile "$profile_dir" --width 1200 --height 900 \
    "http://ipad:smoketest-selkies@127.0.0.1:6080/?token=smoketest-selkies" \
    >"$work_dir/firefox.log" 2>&1 &
firefox_pid=$!

size=
for _ in {1..240}; do
    size=$(XAUTHORITY=$auth_file xrandr --display "$display" --current 2>/dev/null \
        | sed -n '1s/.*current \([0-9]*\) x \([0-9]*\).*/\1x\2/p' || true)
    [[ -n $size && $size != 1366x1024 ]] && break
    sleep 0.25
done
[[ -n $size && $size != 1366x1024 ]] || fail "Selkies did not resize the desktop"
width=${size%x*}
height=${size#*x}
# Native pixels: twice the 1200 CSS px width; the height loses browser chrome.
((width >= 2380 && width <= 2410)) || fail "width $width is not ~2x the viewport"
((height >= 1400 && height <= 1800)) || fail "height $height is out of range"
echo "smoke-selkies: resized to ${width}x${height} for a 1200x900 @2x client"

virtual_scale=$(DCONF_PROFILE=$runtime_dir/dconf-profile \
    gsettings get org.cinnamon.desktop.interface scaling-factor)
[[ $virtual_scale == "uint32 2" ]] || fail "virtual UI scale is $virtual_scale"
blacklist=$(DCONF_PROFILE=$runtime_dir/dconf-profile \
    gsettings get org.cinnamon.SessionManager autostart-blacklist)
[[ $blacklist == *"'plank'"* ]] || fail "plank is not skipped: $blacklist"
now_physical=$(gsettings get org.cinnamon.desktop.interface scaling-factor 2>/dev/null || true)
[[ $now_physical == "$physical_scale" ]] || fail "the physical UI scale changed"
for file in "${home_files[@]}"; do
    [[ -e $file && " ${existing[*]} " != *" $file "* ]] && fail "$file was created"
done

# Stopping the launcher must take the whole virtual session with it.
kill "$firefox_pid" 2>/dev/null || true
wait "$firefox_pid" 2>/dev/null || true
firefox_pid=
kill "$launcher_pid"
wait "$launcher_pid" 2>/dev/null || true
launcher_pid=
leftovers=
for _ in {1..40}; do
    leftovers=$(grep -lzx "DISPLAY=$display" /proc/[0-9]*/environ 2>/dev/null || true)
    [[ -z $leftovers ]] && break
    sleep 0.25
done
[[ -z $leftovers ]] || fail "processes outlived the launcher: $leftovers"
[[ ! -e $runtime_dir/selkies-master.header ]] || fail "master token file left behind"
echo "smoke-selkies: auth, single instance, resize, settings isolation and" \
    "shutdown OK"
