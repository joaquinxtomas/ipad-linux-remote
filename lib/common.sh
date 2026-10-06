# shellcheck shell=bash
# Shared helpers for the launcher and the ipad-desktop command.

NOVNC_VERSION=1.7.0
# shellcheck disable=SC2034  # used by bin/ipad-desktop
NOVNC_SHA256=b1003a11b6e6e8d8f7f5e5586daae7f8ca651d8aee0aa155ff9ac841c48f52c6
# shellcheck disable=SC2034
NOVNC_URL=https://github.com/novnc/noVNC/archive/refs/tags/v$NOVNC_VERSION.tar.gz

data_home=${XDG_DATA_HOME:-${HOME:?}/.local/share}
novnc_home=$data_home/remote-desktop/noVNC-$NOVNC_VERSION

# Supported X11 desktops, most preferred first.
SESSIONS=(cinnamon xfce4-session mate-session startlxqt startplasma-x11
    openbox-session i3)

detect_session() {
    if [[ -n ${REMOTE_DESKTOP_SESSION:-} ]]; then
        command -v "$REMOTE_DESKTOP_SESSION" >/dev/null || return 1
        echo "$REMOTE_DESKTOP_SESSION"
        return
    fi
    local session
    for session in "${SESSIONS[@]}"; do
        command -v "$session" >/dev/null && { echo "$session"; return; }
    done
    return 1
}

# Environment assignments that make a desktop cheaper to stream.
session_tuning() {
    case $1 in
        cinnamon)
            printf '%s\n' CINNAMON_2D=1 CINNAMON_SLOWDOWN_FACTOR=0.0001 \
                MUFFIN_NO_SHADOWS=1 CLUTTER_DEFAULT_FPS=60 ;;
    esac
}

session_arguments() {
    case $1 in
        cinnamon) printf '%s\n' --sm-disable "--display=$2" ;;
    esac
}

find_novnc() {
    local dir
    for dir in ${REMOTE_DESKTOP_NOVNC_DIR:+"$REMOTE_DESKTOP_NOVNC_DIR"} \
        "$novnc_home" /usr/share/novnc /usr/share/webapps/novnc; do
        [[ -f $dir/core/rfb.js && -d $dir/vendor ]] && { echo "$dir"; return; }
    done
    return 1
}

# Prints the package manager family: apt, dnf, pacman or zypper.
package_manager() {
    local id_like=
    [[ -r /etc/os-release ]] && id_like=$(
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "${ID:-} ${ID_LIKE:-}"
    )
    case " $id_like " in
        *" debian "* | *" ubuntu "*) echo apt ;;
        *" fedora "* | *" rhel "*) echo dnf ;;
        *" arch "*) echo pacman ;;
        *" suse "* | *" opensuse "*) echo zypper ;;
        *) return 1 ;;
    esac
}

# Maps a required command to the package that provides it.
package_for() {
    local manager=$1 command=$2
    case $manager:$command in
        apt:Xvnc) echo tigervnc-standalone-server ;;
        apt:vncpasswd) echo tigervnc-tools ;;
        apt:xdpyinfo) echo x11-utils ;;
        apt:xrandr) echo x11-xserver-utils ;;
        apt:websockify) echo websockify ;;
        apt:dbus-run-session) echo dbus ;;
        dnf:Xvnc | dnf:vncpasswd) echo tigervnc-server ;;
        dnf:xdpyinfo) echo xdpyinfo ;;
        dnf:xrandr) echo xrandr ;;
        dnf:websockify) echo python3-websockify ;;
        dnf:dbus-run-session) echo dbus-daemon ;;
        pacman:Xvnc | pacman:vncpasswd) echo tigervnc ;;
        pacman:xdpyinfo) echo xorg-xdpyinfo ;;
        pacman:xrandr) echo xorg-xrandr ;;
        pacman:xauth) echo xorg-xauth ;;
        pacman:websockify) echo websockify ;;
        pacman:dbus-run-session) echo dbus ;;
        zypper:Xvnc) echo xorg-x11-Xvnc ;;
        zypper:vncpasswd) echo tigervnc ;;
        zypper:xdpyinfo) echo xdpyinfo ;;
        zypper:xrandr) echo xrandr ;;
        zypper:websockify) echo python3-websockify ;;
        zypper:dbus-run-session) echo dbus-1-daemon ;;
        *:mcookie | *:flock) echo util-linux ;;
        *:sha256sum) echo coreutils ;;
        *:python3) [[ $manager == pacman ]] && echo python || echo python3 ;;
        *) echo "$command" ;;
    esac
}

install_packages() {
    case $1 in
        apt) sudo apt-get install -y "${@:2}" ;;
        dnf) sudo dnf install -y "${@:2}" ;;
        pacman) sudo pacman -S --needed --noconfirm "${@:2}" ;;
        zypper) sudo zypper --non-interactive install "${@:2}" ;;
    esac
}
