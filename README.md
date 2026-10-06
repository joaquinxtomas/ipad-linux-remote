# iPad Linux Remote

A private Linux desktop for programming from an iPad, reachable from any
network. The desktop runs on its own virtual X display whose native resolution
follows the iPad's usable viewport, so it fills the screen without stretching
and without touching your physical monitor.

```text
iPad (Safari / home-screen app)
   │  HTTPS inside your tailnet — never on the public Internet
   ▼
tailscale serve ──► websockify + noVNC (127.0.0.1) ──► Xvnc virtual desktop
```

## Requirements

- A Linux distribution based on Debian/Ubuntu, Fedora, Arch or openSUSE.
- An X11 desktop: Cinnamon, XFCE, MATE, LXQt, Plasma (X11), Openbox or i3.
  GNOME is not supported because it no longer offers an X11 session.
- A free [Tailscale](https://tailscale.com) account and the Tailscale app on
  the iPad, signed in with the same account.

## Quick start

```sh
git clone https://github.com/joaquinxtomas/ipad-linux-remote.git
cd ipad-linux-remote
./bin/ipad-desktop up
```

`up` is safe to run again at any time. It:

1. installs missing packages with your package manager (asks first);
2. downloads a pinned, checksum-verified noVNC;
3. generates a VNC password and shows it once;
4. installs Tailscale with the official script if needed and prints a login
   QR code;
5. publishes the desktop only inside your tailnet with `tailscale serve`,
   restricted to your Tailscale login;
6. installs and starts a `systemd --user` service that survives reboots;
7. prints the iPad URL as a QR code.

On the iPad, open the URL in Safari and use **Share → Add to Home Screen** for
a fullscreen app. If Tailscale asks you to enable HTTPS certificates for your
tailnet, follow the link it prints once.

## Commands

| Command | Purpose |
|---|---|
| `ipad-desktop up` | Set up and start (default) |
| `ipad-desktop status` | Service state and iPad URL |
| `ipad-desktop down` | Stop the desktop |
| `ipad-desktop doctor` | Check dependencies without changing anything |
| `ipad-desktop password` | Generate a new VNC password |
| `ipad-desktop uninstall` | Remove the service and the Serve route |

Pass `--yes` before the command to accept all prompts.

## Configuration

Environment variables read by the launcher:

| Variable | Default | Meaning |
|---|---|---|
| `REMOTE_DESKTOP_SESSION` | first installed desktop | Desktop command, e.g. `xfce4-session` |
| `REMOTE_DESKTOP_RENDER_SCALE` | `1.25` | `1`, `1.25` or `1.5` times the viewport |
| `REMOTE_DESKTOP_DISPLAY` | `:98` | Virtual X display (never `:0`) |
| `REMOTE_DESKTOP_VNC_PORT` | `5998` | Loopback VNC port |
| `REMOTE_DESKTOP_WEB_PORT` | `6080` | Loopback noVNC port |
| `REMOTE_DESKTOP_NOVNC_DIR` | downloaded copy | Use another noVNC tree |

`ipad-desktop up` stores the allowed Tailscale login in
`~/.config/remote-desktop/config`; add more logins comma-separated in
`REMOTE_DESKTOP_ALLOWED_USERS`.

Per-connection options go in the URL: `?scale=1`, `?scale=1.5`, and
`#compression=0`…`#compression=9` (higher saves bandwidth at the cost of host
CPU). Render sizes are capped at 2560 pixels per axis and 4 megapixels.

The page includes scale, reconnect and clipboard controls and follows
`visualViewport`, including orientation and on-screen keyboard changes.

Firefox launched inside the virtual desktop uses an isolated profile so it can
run alongside Firefox on the physical desktop (snap and Flatpak included).

## Security model

- Nothing listens on a public or LAN interface: Xvnc and websockify bind to
  `127.0.0.1`, and only `tailscale serve` reaches them, over HTTPS.
- Requests must carry an allowed `Tailscale-User-Login` identity, which
  Tailscale Serve sets; others receive 403.
- The VNC password is a second layer. Keep it out of the repository.
- Do not use `tailscale funnel` with this project: it would publish the
  desktop to the Internet.

## Logs and troubleshooting

```sh
ipad-desktop doctor
journalctl --user -u remote-desktop.service -f
```

## Development

`test/smoke.sh` validates resizing on a real host (needs Firefox and xrandr);
`test/ci.sh` is the headless check run in CI across distributions.

### Measuring performance

Add `stats=1` to the URL (for example `?scale=1.25&stats=1`) to show frames
per second, received bandwidth, remote resolution and reconnect time. To
measure input latency, run `bin/latency-probe` inside the virtual session; it
opens a small coloured window. Then press **Probe latency** in the overlay.
Only timings and sizes are recorded.

`./test/bench.sh [scale...]` repeats this unattended on the host with VS Code
and reports latency, frame rate, bandwidth and CPU per process. Stop the user
service first. Results are in `docs/perf-baseline.md`.

## License

MIT
