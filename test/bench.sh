#!/usr/bin/env bash
set -euo pipefail

# Local performance baseline: for each render scale, starts the desktop, opens
# VS Code and bin/latency-probe in the virtual session, drives headless Firefox
# through web/stats.js and samples per-process CPU for each benchmark phase.
# Usage: test/bench.sh [scale...]   (default: 1 1.25 1.5)
# BENCH_WIDTH/BENCH_HEIGHT set the browser viewport (default iPad 10th gen
# landscape, 1180x820); BENCH_PARAMS adds client hash parameters, e.g.
# BENCH_PARAMS='compression=2&quality=6'.

export LC_ALL=C

project_dir=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/..")
display=:98
runtime_dir=${XDG_RUNTIME_DIR:-/tmp}/remote-desktop
auth_file=$runtime_dir/Xauthority.98
work_dir=$(mktemp -d /tmp/remote-desktop-bench.XXXXXX)
password_file=$work_dir/vnc.passwd
code_dir=$work_dir/vscode
profile_dir=$work_dir/firefox
viewport_width=${BENCH_WIDTH:-1180}
viewport_height=${BENCH_HEIGHT:-820}
extra_params=${BENCH_PARAMS:+&$BENCH_PARAMS}
scales=("$@")
((${#scales[@]})) || scales=(1 1.25 1.5)
tick_rate=$(getconf CLK_TCK)
launcher_pid=
firefox_pid=

cleanup() {
    [[ -n $firefox_pid ]] && kill "$firefox_pid" 2>/dev/null || true
    pkill -f -- "--user-data-dir=$code_dir" 2>/dev/null || true
    [[ -n $launcher_pid ]] && kill "$launcher_pid" 2>/dev/null || true
    [[ -n $firefox_pid ]] && wait "$firefox_pid" 2>/dev/null || true
    [[ -n $launcher_pid ]] && wait "$launcher_pid" 2>/dev/null || true
    firefox_pid=
    launcher_pid=
}
remove_work_dir() {
    cleanup
    case $work_dir in
        /tmp/remote-desktop-bench.*) rm -rf -- "$work_dir" ;;
    esac
}
trap remove_work_dir EXIT INT TERM HUP

in_session() {
    DISPLAY=$display XAUTHORITY=$auth_file "$@"
}

# Sum of user+system CPU ticks of all processes matching a pattern.
ticks() {
    local total=0 pid value
    for pid in $(pgrep -f -- "$1" || true); do
        value=$(awk '{sub(/.*\) /, ""); print $12 + $13}' "/proc/$pid/stat" 2>/dev/null) || continue
        total=$((total + ${value:-0}))
    done
    echo "$total"
}

groups=(xvnc cinnamon websockify vscode firefox)
declare -A patterns=(
    [xvnc]="^Xvnc $display "
    [cinnamon]="cinnamon --sm-disable --display=$display"
    [websockify]="websockify --web $runtime_dir/web"
    [vscode]="--user-data-dir=$code_dir"
    [firefox]="--profile $profile_dir"
)

snapshot() {
    local group
    snap_time[$1]=$(date +%s.%N)
    for group in "${groups[@]}"; do
        snap_ticks[$1:$group]=$(ticks "${patterns[$group]}")
    done
}

cpu_report() {
    local phase=$1 group seconds line=""
    seconds=$(echo "${snap_time[$phase-end]} - ${snap_time[$phase-start]}" | bc -l)
    for group in "${groups[@]}"; do
        line+=$(printf ' %s=%.0f%%' "$group" "$(echo "(${snap_ticks[$phase-end:$group]} - ${snap_ticks[$phase-start:$group]}) / $tick_rate / $seconds * 100" | bc -l)")
    done
    echo "  cpu[$phase]$line"
}

for command in xterm xwininfo code firefox bc; do
    command -v "$command" >/dev/null || {
        echo "Missing dependency: $command" >&2
        exit 1
    }
done
printf 'benchpass\n' | vncpasswd -f >"$password_file"
chmod 600 "$password_file"
mkdir -p "$code_dir/User" "$profile_dir"
cat >"$code_dir/User/settings.json" <<'EOF'
{
    "window.newWindowDimensions": "maximized",
    "workbench.startupEditor": "none",
    "security.workspace.trust.enabled": false,
    "update.mode": "none",
    "telemetry.telemetryLevel": "off",
    "extensions.autoCheckUpdates": false
}
EOF
cat >"$profile_dir/user.js" <<'EOF'
user_pref("devtools.console.stdout.content", true);
EOF

for scale in "${scales[@]}"; do
    declare -A snap_time=() snap_ticks=()
    log=$work_dir/firefox-$scale.log

    REMOTE_DESKTOP_DISPLAY=$display \
        REMOTE_DESKTOP_VNC_PASSWORD_FILE=$password_file \
        "${BENCH_LAUNCHER:-$project_dir/bin/start-desktop}" >"$work_dir/launcher-$scale.log" 2>&1 &
    launcher_pid=$!
    for _ in {1..100}; do
        curl -fsS http://127.0.0.1:6080/ >/dev/null 2>&1 && break
        kill -0 "$launcher_pid" 2>/dev/null || {
            cat "$work_dir/launcher-$scale.log" >&2
            exit 1
        }
        sleep 0.1
    done
    [[ $scale == "${scales[0]}" ]] && echo "renderer: $(in_session glxinfo -B 2>/dev/null \
        | sed -n 's/^OpenGL renderer string: //p')"

    in_session code --user-data-dir="$code_dir" --extensions-dir="$code_dir/extensions" \
        --disable-extensions --password-store=basic --new-window \
        /usr/share/novnc/core/rfb.js >/dev/null 2>&1 &
    for _ in {1..150}; do
        in_session xwininfo -root -tree 2>/dev/null | grep -q 'rfb.js' && break
        sleep 0.2
    done
    sleep 3
    in_session "$project_dir/bin/latency-probe" >/dev/null 2>&1 &
    sleep 1

    # Headless Firefox reserves 86 px of window height for browser chrome.
    firefox --headless --no-remote --profile "$profile_dir" \
        --width "$viewport_width" --height "$((viewport_height + 86))" \
        "http://127.0.0.1:6080/?scale=$scale&stats=1#password=benchpass&bench=1$extra_params" \
        >"$log" 2>&1 &
    firefox_pid=$!

    result=
    while IFS= read -r line; do
        if [[ $line =~ BENCH\ mark\ ([a-z]+-(start|end)) ]]; then
            snapshot "${BASH_REMATCH[1]}"
        elif [[ $line =~ BENCH\ result\ (\{.*\}) ]]; then
            result=${BASH_REMATCH[1]//\\\"/\"}
            break
        fi
    done < <(timeout 180 tail -n +1 -F "$log" 2>/dev/null)

    echo "scale $scale${extra_params:+ ($BENCH_PARAMS)}"
    if [[ -z $result ]]; then
        echo "  no result; see $log" >&2
        cat "$log" >&2
        exit 1
    fi
    echo "  $result"
    for phase in probe idle scroll; do
        cpu_report "$phase"
    done
    cleanup
    sleep 2
done
