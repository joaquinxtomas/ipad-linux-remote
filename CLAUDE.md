# CLAUDE.md

@AGENTS.md

`AGENTS.md` holds the project rules (security, adaptive geometry, workflow,
definition of done); `PLAN.md` holds the phases and their current status. Read
both before architectural changes. This file only adds what is specific to the
current implementation.

## Stack

No build step, no package manager, no application server. The MVP is glue
around mature components:

```text
iPad Safari/PWA ── web/index.html (noVNC RFB client, ES module)
      │  ws://<tailscale-ip>:6080/websockify
websockify  (serves web root + WebSocket→TCP proxy; bound to 127.0.0.1 or Tailscale IPv4)
      │  127.0.0.1:5998
Xvnc :98    (TigerVNC: virtual X display + VNC server, -localhost, VncAuth,
             -AcceptSetDesktopSize=1)
      │
Cinnamon    (dbus-run-session, 2D mode, no shadows/animations)
```

Runtime dependencies come from Debian/Mint packages: `tigervnc-standalone-server`
and `novnc` (noVNC 1.3 served from `/usr/share/novnc`, symlinked into the web
root at startup).

## Layout

- `bin/start-desktop` — the whole launcher: validates env, checks deps and the
  password file mode, takes a `flock`, starts Xvnc → Cinnamon → websockify,
  and tears everything down when any of them exits.
- `bin/start-tailscale-desktop` — resolves `tailscale ip -4` and execs
  `start-desktop` bound to it. Used by the systemd unit.
- `bin/firefox` — wrapper put first in `PATH` inside the virtual session so
  Firefox uses an isolated profile.
- `web/index.html` — the entire client: `visualViewport` tracking, debounced
  (500 ms) resize negotiation, render scale, auth form, clipboard panel,
  reconnect logic. Inline CSS/JS, no framework.
- `systemd/remote-desktop.service` — `systemd --user` unit; runs the symlink
  `~/.local/bin/start-tailscale-desktop`, so repo edits apply on restart.
- `test/smoke.sh` — end-to-end check (see below).
- `web/stats.js`, `bin/latency-probe`, `test/bench.sh` — measurement tooling;
  `docs/perf-baseline.md` holds the numbers.
- Runtime state lives in `$XDG_RUNTIME_DIR/remote-desktop/` (lock, Xauthority,
  web root). The VNC password lives in `~/.config/remote-desktop/vnc.passwd`
  (mode 600, never in the repo).

## Configuration

Environment variables read by `bin/start-desktop`:
`REMOTE_DESKTOP_DISPLAY` (`:98`, never `:0`), `REMOTE_DESKTOP_VNC_PORT` (5998),
`REMOTE_DESKTOP_WEB_PORT` (6080), `REMOTE_DESKTOP_WEB_BIND` (`127.0.0.1`; any
other value must equal the active Tailscale IPv4), `REMOTE_DESKTOP_RENDER_SCALE`
(`1`, `1.25`, `1.5`), `REMOTE_DESKTOP_VNC_PASSWORD_FILE`.

Client URL parameters (query or hash; hash wins): `scale`, `quality` (0–9,
default 9), `compression` (0–9, default 0), `password` (hash only, used by the
smoke test).

## Commands

```sh
./bin/start-desktop                        # local session on 127.0.0.1:6080
./test/smoke.sh                            # end-to-end geometry/auth test
systemctl --user status remote-desktop.service
journalctl --user -u remote-desktop.service -f
```

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

No formatter or linter is configured; run `shellcheck bin/* test/*.sh` if it is
installed.

## Invariants to preserve

- Xvnc always keeps `-localhost`; only websockify may bind to the Tailscale
  address, and the launcher must keep rejecting wildcard/LAN binds.
- Resolution adapts by resizing Xvnc (`SetDesktopSize`); `rfb.scaleViewport`
  only applies uniform residual scaling. Never scale X and Y independently.
- Resize limits live in two places and must stay in sync: allowed scales in
  `bin/start-desktop` and `web/index.html` (`scales`), plus the client caps
  `maxAxis = 2560` and `maxPixels = 4000000` documented in `README.md`.
- `requestRemoteResize()` uses noVNC 1.3 internals (`_sock`,
  `_supportsSetDesktopSize`, `_screenID`, `_screenFlags`). Re-check them if the
  `novnc` package is upgraded.
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

Phases 2, 3 and 6 are active; Phase 5 (Tailscale) is prepared. The main open
item is validating geometry, orientation changes, keyboard/pointer input and
reconnect on the physical iPad. Phase 4 (programming UX) and Phase 7 (final
validation) are not started.
