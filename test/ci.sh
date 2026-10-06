#!/usr/bin/env bash
# Headless check for CI containers: start the desktop, then verify that the
# Tailscale identity gate rejects anonymous requests and admits allowed users.
set -euo pipefail

project_dir=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
launcher_pid=
cleanup() {
    [[ -n $launcher_pid ]] && kill "$launcher_pid" 2>/dev/null || true
    [[ -n $launcher_pid ]] && wait "$launcher_pid" 2>/dev/null || true
    # A full desktop may leave gvfs mounted in the runtime dir.
    fusermount -uz "$work/run/gvfs" 2>/dev/null || true
    rm -rf -- "$work"
}
trap cleanup EXIT

export XDG_DATA_HOME=$work/data XDG_RUNTIME_DIR=$work/run
mkdir -m700 "$XDG_RUNTIME_DIR"
# shellcheck source=lib/common.sh
source "$project_dir/lib/common.sh"
session=$(detect_session)
echo "detected desktop: $session"

curl -fsSL "$NOVNC_URL" -o "$work/novnc.tgz"
echo "$NOVNC_SHA256  $work/novnc.tgz" | sha256sum -c -
mkdir -p "$(dirname "$novnc_home")"
tar -xzf "$work/novnc.tgz" -C "$(dirname "$novnc_home")"

printf 'citest\n' | vncpasswd -f >"$work/vnc.passwd"
chmod 600 "$work/vnc.passwd"

REMOTE_DESKTOP_VNC_PASSWORD_FILE=$work/vnc.passwd \
    REMOTE_DESKTOP_ALLOWED_USERS=owner@example.com \
    "$project_dir/bin/start-desktop" >"$work/launcher.log" 2>&1 &
launcher_pid=$!

status() {
    curl -so /dev/null -w '%{http_code}' "$@" http://127.0.0.1:6080/ || true
}
for _ in {1..100}; do
    [[ $(status) == 403 ]] && break
    kill -0 "$launcher_pid" 2>/dev/null || { cat "$work/launcher.log"; exit 1; }
    sleep 0.2
done
[[ $(status) == 403 ]]
[[ $(status -H 'Tailscale-User-Login: intruder@example.com') == 403 ]]
[[ $(status -H 'Tailscale-User-Login: Owner@Example.com') == 200 ]]
kill -0 "$launcher_pid"
echo "ci: $session desktop served; identity gate enforced"
