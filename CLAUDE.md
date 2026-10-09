# CLAUDE.md

@AGENTS.md

`AGENTS.md` holds the project rules (security, adaptive geometry, workflow,
definition of done); `PLAN.md` holds the phases and their current status. Read
both before architectural changes. This file only adds what is specific to the
current implementation.

## Stack

No build step, no package manager, no application server. The MVP is glue
around mature components:

Default backend (Selkies, `REMOTE_DESKTOP_BACKEND=selkies`):

```text
iPad Safari/PWA ── Selkies web client (H.264 via WebCodecs)
      │  https://<host>.<tailnet>.ts.net  (tailscale serve, tailnet only)
tailscale serve  (TLS)
      │  127.0.0.1:6080  (one WebSocket: video + input + clipboard)
Selkies 2.0  (Python venv, secure mode: Basic auth `ipad` for the page, the
              same secret as session token `?token=` for the WebSocket;
              NVENC/VA-API/x264; resizes the display via RandR)
      │
Xvfb :98    (8192x4096 framebuffer, RandR-resized to the client size)
      │
Cinnamon    (cinnamon-session-cinnamon2d in dbus-run-session; UI scale from
             an isolated dconf profile)
```

Fallback backend (`REMOTE_DESKTOP_BACKEND=vnc`):

```text
iPad Safari/PWA ── web/index.html (noVNC RFB client, ES module)
      │  tailscale serve → 127.0.0.1:6080
websockify  (web root + WebSocket→TCP proxy, loopback only;
             --web-auth with lib/tailscale_identity.py → 403 for other logins)
      │  127.0.0.1:5998
Xvnc :98    (TigerVNC, -localhost, VncAuth, -AcceptSetDesktopSize=1)
      │
X11 desktop (auto-detected; bare `cinnamon` window manager)
```

Runtime dependencies come from distro packages (Xvfb, TigerVNC, websockify,
…; per-distro mapping in `lib/common.sh`). Selkies is pinned
(`SELKIES_VERSION`, 2.0.0) and installed from PyPI into
`$XDG_DATA_HOME/remote-desktop/selkies-<version>/`. noVNC is pinned (1.7.0),
downloaded and checksum-verified, with distro paths as fallback. Phase 6.7 in
`PLAN.md` records why Selkies was chosen.

## Layout

- `bin/ipad-desktop` — user-facing CLI: `up` (deps, noVNC, Tailscale login,
  password, `tailscale serve` route, service), `status`, `down`, `doctor`,
  `password`, `uninstall`, and `run` (used by the service).
- `bin/start-selkies` — the Selkies launcher (default backend): validates env
  and the password file mode, takes the shared `flock`, starts Xvfb → desktop
  (own process group) → Selkies, and tears everything down when any exits.
- `bin/start-desktop` — the VNC launcher: validates env, checks deps and
  the password file mode, takes a `flock`, starts Xvnc → desktop → websockify,
  and tears everything down when any of them exits.
- `lib/common.sh` — shared helpers: distro/package mapping, session
  detection, noVNC pin. `lib/tailscale_identity.py` — websockify auth plugin
  checking `Tailscale-User-Login`.
- `bin/firefox` — wrapper put first in `PATH` inside the virtual session so
  Firefox uses an isolated profile.
- `web/index.html` — the entire client: `visualViewport` tracking, debounced
  (500 ms) resize negotiation, render scale, auth form, clipboard panel,
  reconnect logic. Inline CSS/JS, no framework.
- `systemd/remote-desktop.service` — `systemd --user` unit; runs the symlink
  `~/.local/bin/ipad-desktop run`, so repo edits apply on restart.
- `test/smoke-selkies.sh`, `test/smoke.sh` — end-to-end checks for each
  backend (see below); `test/ci.sh` — headless
  identity-gate check run per distro family by `.github/workflows/ci.yml`.
- `web/stats.js`, `bin/latency-probe`, `test/bench.sh` — measurement tooling;
  `docs/perf-baseline.md` holds the numbers.
- Runtime state lives in `$XDG_RUNTIME_DIR/remote-desktop/` (lock, Xauthority,
  web root). The VNC password lives in `~/.config/remote-desktop/vnc.passwd`
  and the Selkies password in `~/.config/remote-desktop/selkies.passwd` (both
  mode 600, never in the repo). `~/.config/remote-desktop/config` holds
  `KEY=value` settings (`REMOTE_DESKTOP_BACKEND`,
  `REMOTE_DESKTOP_ALLOWED_USERS`, …) that `ipad-desktop` loads unless the
  environment already sets them. Selkies runs with
  `HOME=$XDG_STATE_HOME/remote-desktop/selkies-home`; the virtual Cinnamon
  uses the dconf database `~/.config/dconf/remote_desktop`.

## Configuration

Shared: `REMOTE_DESKTOP_BACKEND` (`selkies` | `vnc`), `REMOTE_DESKTOP_DISPLAY`
(`:98`, never `:0`), `REMOTE_DESKTOP_WEB_PORT` (6080), `REMOTE_DESKTOP_SESSION`.
Selkies: `REMOTE_DESKTOP_UI_SCALE` (`1` | `2`, default 2),
`REMOTE_DESKTOP_TEXT_SCALE` (0.5–2, default 1),
`REMOTE_DESKTOP_SELKIES_PASSWORD_FILE`, `REMOTE_DESKTOP_SELKIES_DIR`.
VNC: `REMOTE_DESKTOP_VNC_PORT` (5998), `REMOTE_DESKTOP_RENDER_SCALE` (`1`,
`1.25`, `1.5`), `REMOTE_DESKTOP_VNC_PASSWORD_FILE`,
`REMOTE_DESKTOP_ALLOWED_USERS` (Tailscale logins; empty disables the identity
gate), `REMOTE_DESKTOP_NOVNC_DIR`.

noVNC client URL parameters (query or hash; hash wins): `scale`, `quality` (0–9,
default 9), `compression` (0–9, default 0), `password` (hash only, used by the
smoke test).

## Commands

```sh
./bin/ipad-desktop up                      # full setup + service
./bin/ipad-desktop doctor                  # check deps, no changes
./bin/start-selkies                        # foreground Selkies session on 127.0.0.1:6080
./bin/start-desktop                        # foreground VNC session on 127.0.0.1:6080
./test/smoke-selkies.sh                    # end-to-end Selkies test
./test/ci.sh                               # headless identity-gate test
./test/smoke.sh                            # end-to-end geometry/auth test
systemctl --user status remote-desktop.service
journalctl --user -u remote-desktop.service -f
```

`test/smoke-selkies.sh` (same display, port and lock; stop the service first)
checks 401/200 basic auth, that assets are served, that the manifest is
protected and carries the token, that the stream WebSocket needs the token
(401 without, 101 with), the single-instance lock, that a 1200×900 @2x
headless Firefox resizes Xvfb to ~2400×1628, that the virtual dconf profile
has `scaling-factor` 2 while the physical one is unchanged, that no
`~/.Xresources`/`~/.xsettingsd` appear, and that no process with
`DISPLAY=:98` outlives the launcher.

`test/smoke.sh` uses display `:98`, port 6080 and the same launcher lock as the
service. Stop the service first (`systemctl --user stop remote-desktop.service`)
or the test fails with "already running". It needs `firefox`, `xrandr`, `curl`
and `vncpasswd`, and writes logs to `/tmp/remote-desktop-*.log`. It verifies:
page/manifest/icon served, single-instance lock, headless Firefox at 1200×900
resizes Xvnc to ~1500×1060 (1.25×), `VNC-0` output stays connected, and a
wrong password produces exactly one auth failure.

`test/bench.sh [scale...]` is the performance baseline (same service caveat).
It uses `bin/latency-probe` plus the opt-in `web/stats.js` overlay
(`?stats=1`, `#bench=1`) to report click-to-pixel latency, fps, bandwidth and
per-process CPU. `BENCH_PARAMS` adds client hash parameters and
`BENCH_LAUNCHER` swaps the launcher. Record results in `docs/perf-baseline.md`
and compare against them before and after any performance change.

CI runs `shellcheck -x` on the shell scripts (`.shellcheckrc` allows the
`a && b || true` idiom) on every push; run the same command from
`.github/workflows/ci.yml` locally before committing.

## Invariants to preserve

- Selkies, Xvnc and websockify stay on loopback; remote access goes only
  through `tailscale serve`. Never use `tailscale funnel`. Selkies has no
  Tailscale identity gate (basic auth only); do not weaken its auth.
- Selkies must not touch the user's real home or desktop settings: keep
  `--scaling-dpi=96` (it otherwise writes `~/.Xresources`/`~/.xsettingsd`),
  its private `HOME`, and the isolated `DCONF_PROFILE` (`user-db` names must
  not contain hyphens or `gsettings` hangs).
- Both launchers run the desktop in its own process group and no child
  inherits the lock fd; `cinnamon-session` and the session services survive
  their X server otherwise. Both smoke tests check for leftovers.
- Selkies secure mode: the password file holds one URL-safe secret used as
  the Basic password and as the only session token (provisioned through
  `/api/tokens` with a per-start master token kept in the runtime dir).
  Safari sends no Basic credentials on the WebSocket, so the token is
  required. The client is served from a copy in `$XDG_RUNTIME_DIR` whose
  `manifest.json` start URL keeps `?token=` (aiohttp static routes do not
  follow symlinks, so it must be a copy).
- Resolution adapts by resizing the X display (Selkies: RandR on Xvfb to the
  client's native pixels; VNC: `SetDesktopSize`); presentation scaling is
  uniform only. Never scale X and Y independently.
- VNC resize limits live in two places and must stay in sync: allowed scales
  in `bin/start-desktop` and `web/index.html` (`scales`), plus the client caps
  `maxAxis = 2560` and `maxPixels = 4000000` documented in `README.md`.
- `requestRemoteResize()` uses noVNC internals (`_sock`,
  `_supportsSetDesktopSize`, `_screenID`, `_screenFlags`). Re-check them whenever
  `NOVNC_VERSION` in `lib/common.sh` changes (now 1.7.0).
- Never log or persist clipboard contents or passwords; the clipboard panel is
  in-memory only and there is no service worker/offline cache.
- Normal operation runs without root.

## Conventions

- Bash: `#!/usr/bin/env bash`, `set -euo pipefail`, 4-space indent, lowercase
  variables, validation as `[[ ... ]] || { echo "..." >&2; exit 2; }`
  (exit 2 = bad input, 1 = environment/runtime failure).
- `# ponytail:` comments mark deliberate MVP shortcuts together with the
  upgrade path; keep that format when adding one.
- Docs and code are in English. `README.md` is user-facing; update it when
  behavior, env vars or URL parameters change, and update the phase status in
  `PLAN.md` when a gate is reached.
- Small commits, one logical change each (see `AGENTS.md` → Git).

## Current focus

Phase 6.7 (Selkies video backend) is implemented and passes
`test/smoke-selkies.sh`; it still needs validation on the iPad through the
service (geometry, UI scale, keyboard/clipboard, Safari basic auth in the
home-screen app). Phase 6.5 only lacks a final `ipad-desktop up` run. Phase 4
(programming UX) and Phase 7 (final validation) are not started.
