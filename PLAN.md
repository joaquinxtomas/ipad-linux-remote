# iPad Linux Remote — Implementation Plan

## Objective

Build a private remote Linux desktop optimized for programming from an iPad.

The core requirement is not merely remote access.

The Linux host must create a **virtual desktop whose resolution adapts to the usable iPad viewport**, allowing the desktop to fill the screen without stretching or geometric distortion.

Target:

```text
iPad / Safari
      │
      │ private encrypted network
      ▼
   Tailscale
      │
      ▼
Linux Mint / Cinnamon
      │
      ▼
virtual desktop
      │
      ▼
remote desktop backend
```

No public remote desktop endpoint is required.

## Phase 0 — Technical validation

### Validation result — 2026-09-16

- `Xvfb` was rejected because its framebuffer could not be resized dynamically.
- Xorg with `xserver-xorg-video-dummy` created a display independent from the
  physical monitor and accepted RANDR mode changes without restarting.
- Cinnamon and a fullscreen application survived
  `1366x1024 -> 1024x1366 -> 1366x1024` and followed the new geometry exactly.
- TigerVNC `Xvnc` was selected for implementation because it combines the
  virtual X display and VNC server and accepts remote `SetDesktopSize` requests.
- noVNC resized Xvnc from `1366x1024` to the browser's usable `1200x814`
  viewport while keeping the virtual output connected.
- Xvnc and noVNC currently listen only on loopback.

The virtual-display gate is satisfied. Guacamole was not selected because its
proxy and web application add infrastructure that the personal MVP does not
need.

Before building application code, validate the underlying technologies.

Investigate and prototype:

- Linux Mint/Cinnamon virtual sessions;
- X11/Xorg virtual displays;
- dynamic resolution changes;
- browser-compatible remote desktop technologies;
- Safari/iPadOS compatibility;
- Tailscale connectivity.

Compare existing remote desktop backends such as:

- Apache Guacamole;
- noVNC + VNC backend;
- other actively maintained browser-compatible alternatives.

The comparison must prioritize:

1. dynamic server-side resolution;
2. Safari compatibility;
3. input quality;
4. text clarity;
5. latency;
6. maintainability.

### Gate

Do not proceed until a virtual Linux desktop can be created and resized independently of the physical monitor.

## Phase 1 — Local virtual desktop

**Status:** complete for the local MVP through the Xvnc display.

Create an independent Linux graphical session.

Requirements:

- does not depend on physical monitor resolution;
- can launch the required development environment;
- supports arbitrary reasonable resolutions;
- can change resolution without recreating the entire machine/session.

Initial validation resolutions should include representative 4:3-ish and iPad-like aspect ratios.

Verify manually that applications reflow normally after resizing.

### Gate

Changing the virtual display dimensions must actually change the Linux desktop geometry.

No stretched 16:9 framebuffer is acceptable.

## Phase 2 — Browser remote desktop

**Status:** active; local noVNC connection and remote resize validated. The
virtual session uses low-overhead Cinnamon settings, a balanced 1.25x render
scale, native profile controls and `visualViewport`; validated on the physical
iPad.

Expose the virtual session through a browser-compatible remote desktop backend.

Initially run everything locally/LAN.

Required:

- image streaming;
- keyboard input;
- pointer/trackpad input;
- reconnect support.

Do not optimize encoding prematurely.

### Gate

Safari on the iPad can interact with the virtual Linux desktop reliably.

## Phase 3 — Adaptive display

**Status:** active; browser-driven resize, orientation events and configurable
HiDPI render scale are implemented and validated on the physical iPad.

Implement the project's main feature.

Client determines the usable viewport using browser APIs.

Conceptually:

```text
Safari opens session
       ↓
measure viewport
       ↓
send target dimensions
       ↓
server validates request
       ↓
virtual display resizes
       ↓
Linux renders new geometry
       ↓
stream matches viewport
```

Handle:

- initial connection;
- landscape mode;
- portrait mode;
- orientation changes;
- browser/PWA viewport changes;
- virtual keyboard appearance where relevant;
- reconnects.

Use debouncing to prevent resize storms.

The final presentation must use uniform scaling only when small residual scaling is unavoidable.

Never independently stretch X and Y.

### Gate

On the physical iPad:

- desktop fills the usable display;
- circles remain circles;
- squares remain squares;
- text is not stretched;
- no unnecessary black bars appear;
- orientation changes work correctly.

This is the primary acceptance test for the project.

## Phase 4 — Programming UX

Improve interaction specifically for development.

Priorities:

1. external keyboard;
2. common keyboard shortcuts;
3. pointer/trackpad;
4. clipboard;
5. text readability;
6. fullscreen/PWA experience;
7. reconnect behavior.

Test with:

- terminal;
- VS Code or equivalent;
- browser;
- Git workflows.

Do not add multimedia-oriented features unless required later.

## Phase 5 — Private remote access

**Status:** automated. `ipad-desktop up` installs Tailscale, guides login with
a QR code and publishes noVNC through `tailscale serve` (HTTPS, tailnet only,
restricted by `Tailscale-User-Login`). Validated on the iPad.

Install/configure Tailscale on:

- Linux host;
- iPad.

Remote desktop services must not be publicly exposed.

Target:

```text
University / other network
          │
        iPad
          │
     encrypted VPN
          │
      Tailscale
          │
      Linux host
```

Verify access while the devices are on different physical networks.

Restrict access to the user's authorized devices/account.

### Gate

The iPad can reach the desktop remotely while the server remains inaccessible from the public Internet.

## Phase 6 — Reliability

**Status:** active; a single-instance `systemd --user` service, automatic
restart, boot activation through user lingering, control-group shutdown and
journal logging are implemented. `ipad-desktop up` installs and starts the
service; `status`, `down`, `password` and `uninstall` manage it.

Add:

- automatic service startup;
- virtual-session lifecycle management;
- useful local logging;
- graceful shutdown;
- reconnect handling;
- recovery from remote backend failure;
- sensible resolution limits.

Avoid requiring manual terminal commands for normal usage.

## Phase 6.5 — Distribution

**Status:** active. Goal: anyone can clone the repository and run one command.

- Support X11 desktops on Debian/Ubuntu, Fedora, Arch and openSUSE families
  (session auto-detection, per-distro package mapping, `doctor`).
- Pin and checksum-verify noVNC instead of relying on distro paths.
- Replace the LAN/Caddy idea with `tailscale serve`; Caddy was dropped.
- CI: shellcheck plus a headless identity-gate test in each distro family.
- Wayland-only desktops (GNOME) are out of scope until a headless Wayland
  backend with client-driven resize is validated.

### Verification (2026-10-06, Linux Mint 22.3)

1. `ipad-desktop doctor` passes. **Pending:** run `ipad-desktop up` and
   confirm the Tailscale login QR, HTTPS prompt, Serve route and final URL.
2. Done: `test/smoke.sh` passes with the downloaded noVNC 1.7.0 (resize to
   1500x1017); the internals used by `requestRemoteResize()` still exist.
3. Done: package mapping fixed (`sha256sum` → `coreutils`, openSUSE
   `dbus-1-daemon`). Arch ships `websockify` only in the AUR, so
   `ipad-desktop` asks the user to install it; CI installs it with pip. All
   five distro jobs pass locally in containers; shellcheck is clean.
4. Done: every distro's websockify supports `--web-auth` (`test/ci.sh`
   enforces the identity gate in all five).
5. Known trade-off: with the identity gate on, `http://127.0.0.1:6080` returns
   403 locally. Comment out the config line for local use.

## Phase 6.7 — Video streaming backend (Selkies)

**Status:** active.

### Decision — 2026-10-09

On the iPad, VNC reached ~30 fps for ordinary windows but stayed below
20 fps while scrolling VS Code even with `compression=2&quality=7`. VNC sends
each changed region as an independent JPEG that noVNC decodes in JavaScript,
so scrolling large text areas cannot become fluid by tuning alone.

[Selkies](https://github.com/selkies-project/selkies) 2.0 (MPL-2.0) streams
the X display as H.264 video encoded on the GPU (NVENC, VA-API, software x264
fallback) and decoded by the browser's hardware decoder. A prototype on the
iPad was clearly fluid. It fits the existing architecture:

- one WebSocket over a single TCP port (no WebRTC/UDP, no TURN), so it stays
  behind `tailscale serve` on loopback with the same URL and QR code;
- binds to `localhost` by default and requires HTTP basic auth;
- resizes a virtual Xvfb display to the browser viewport (RandR), so geometry
  remains native and undistorted;
- installs from PyPI into a private venv, without root.

Rejected alternatives: KasmVNC (still per-rectangle VNC encoding), xrdp with a
native RDP client and Sunshine/Moonlight (native iPad apps, against the
browser-first rule; Moonlight is game streaming).

### Design

- `bin/start-selkies` mirrors `bin/start-desktop`: Xvfb on `:98`, desktop in
  `dbus-run-session`, Selkies on `127.0.0.1:6080`, the same launcher lock.
- The client requests the native Retina size; the desktop is scaled by
  Cinnamon (`scaling-factor`, `text-scaling-factor`) inside an isolated dconf
  profile so the physical desktop's settings never change.
- Selkies' own DPI handling is pinned to 96 and its `HOME` points to a state
  directory: it would otherwise write `~/.Xresources` and `~/.xsettingsd`,
  which the physical session also reads.
- `REMOTE_DESKTOP_BACKEND=vnc` keeps the previous backend as a fallback.

### Security trade-off

Selkies has no hook for the websockify identity plugin, so the
`Tailscale-User-Login` check does not apply to this backend. Access requires
being inside the tailnet (`tailscale serve`, never Funnel) plus Selkies basic
auth with a generated password. Restricting the node with Tailscale ACLs is the
recommended extra layer.

### Gate

VS Code scrolling is fluid on the iPad, the desktop fills the viewport at a
readable size without distortion, and the physical desktop's settings and home
files stay untouched.

## Phase 7 — Final validation

Test the actual workflow:

```text
Leave Linux PC at home
        ↓
connect iPad to another network
        ↓
enable private network
        ↓
open Safari/PWA
        ↓
connect
        ↓
virtual desktop adapts to iPad
        ↓
open development environment
        ↓
program normally
```

Verify:

- correct geometry;
- readable text;
- acceptable latency;
- keyboard shortcuts;
- pointer behavior;
- clipboard;
- reconnect;
- orientation changes;
- no public ports.

## Phase 8 — Embedded Tailscale (future)

Only after `tailscale serve` proves itself on the iPad: evaluate a single Go
binary that joins the tailnet itself through `tsnet`, removing the system
Tailscale install, sudo and the operator setting.

## Out of Scope

Do not implement unless requirements change:

- native iPad application;
- App Store distribution;
- multi-user hosting;
- public remote desktop service;
- game streaming;
- audio streaming;
- remote gaming optimizations;
- custom video codec;
- custom VPN;
- custom cryptography;
- custom NAT traversal;
- file synchronization platform.

## Success Criterion

The project succeeds when an iPad can securely connect from outside the home network and obtain a responsive Linux development desktop whose **native virtual resolution follows the iPad's usable viewport**, filling the screen without stretching or distortion.
