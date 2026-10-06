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
      │  https://<host>.<tailnet>.ts.net  (tailscale serve, tailnet only)
tailscale serve  (TLS; sets Tailscale-User-Login)
      │  127.0.0.1:6080
websockify  (serves web root + WebSocket→TCP proxy, loopback only;
             --web-auth with lib/tailscale_identity.py → 403 for other logins)
      │  127.0.0.1:5998
Xvnc :98    (TigerVNC: virtual X display + VNC server, -localhost, VncAuth,
             -AcceptSetDesktopSize=1)
      │
X11 desktop (auto-detected; Cinnamon on the main host, 2D mode)
```

Runtime dependencies come from distro packages (TigerVNC, websockify, …;
per-distro mapping in `lib/common.sh`). noVNC is pinned (1.7.0), downloaded
and checksum-verified into `$XDG_DATA_HOME/remote-desktop/`, with distro
paths as fallback.

## Layout

- `bin/ipad-desktop` — user-facing CLI: `up` (deps, noVNC, Tailscale login,
  password, `tailscale serve` route, service), `status`, `down`, `doctor`,
  `password`, `uninstall`, and `run` (used by the service).
- `bin/start-desktop` — the session launcher: validates env, checks deps and
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
- `test/smoke.sh` — end-to-end check (see below); `test/ci.sh` — headless
  identity-gate check run per distro family by `.github/workflows/ci.yml`.
- `web/stats.js`, `bin/latency-probe`, `test/bench.sh` — measurement tooling;
  `docs/perf-baseline.md` holds the numbers.
- Runtime state lives in `$XDG_RUNTIME_DIR/remote-desktop/` (lock, Xauthority,
  web root). The VNC password lives in `~/.config/remote-desktop/vnc.passwd`
  (mode 600, never in the repo); `~/.config/remote-desktop/config` holds
  `REMOTE_DESKTOP_ALLOWED_USERS` (written by `ipad-desktop up`).

## Configuration

Environment variables read by `bin/start-desktop`:
`REMOTE_DESKTOP_DISPLAY` (`:98`, never `:0`), `REMOTE_DESKTOP_VNC_PORT` (5998),
`REMOTE_DESKTOP_WEB_PORT` (6080), `REMOTE_DESKTOP_RENDER_SCALE` (`1`, `1.25`,
`1.5`), `REMOTE_DESKTOP_VNC_PASSWORD_FILE`, `REMOTE_DESKTOP_ALLOWED_USERS`
(Tailscale logins; empty disables the identity gate). `lib/common.sh` also
reads `REMOTE_DESKTOP_SESSION` and `REMOTE_DESKTOP_NOVNC_DIR`.

Client URL parameters (query or hash; hash wins): `scale`, `quality` (0–9,
default 9), `compression` (0–9, default 0), `password` (hash only, used by the
smoke test).

## Commands

```sh
./bin/ipad-desktop up                      # full setup + service
./bin/ipad-desktop doctor                  # check deps, no changes
./bin/start-desktop                        # foreground session on 127.0.0.1:6080
./test/ci.sh                               # headless identity-gate test
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

- Xvnc and websockify stay on loopback; remote access goes only through
  `tailscale serve` plus the identity gate. Never use `tailscale funnel`.
- Resolution adapts by resizing Xvnc (`SetDesktopSize`); `rfb.scaleViewport`
  only applies uniform residual scaling. Never scale X and Y independently.
- Resize limits live in two places and must stay in sync: allowed scales in
  `bin/start-desktop` and `web/index.html` (`scales`), plus the client caps
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

Phases 2, 3, 5 and 6 are validated on the physical iPad. Phase 6.5
(distribution: `ipad-desktop`, noVNC 1.7.0 pin, multi-distro CI) was written
without Linux and still needs the verification list in `PLAN.md`. Phase 4
(programming UX) and Phase 7 (final validation) are not started.
