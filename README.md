# iPad Linux Remote

A private Linux desktop for programming from an iPad, reachable from any
network. The desktop runs on its own virtual X display whose native resolution
follows the iPad's usable viewport, so it fills the screen without stretching
and without touching your physical monitor.

```text
iPad (Safari / home-screen app)
   │  HTTPS inside your tailnet — never on the public Internet
   ▼
tailscale serve ──► Selkies (127.0.0.1) ──► Xvfb virtual desktop
                    H.264 video, GPU-encoded when available
```

The desktop is streamed as video by
[Selkies](https://github.com/selkies-project/selkies), encoded on the GPU
(NVIDIA NVENC, VA-API) or in software, and decoded by the iPad's hardware, so
scrolling stays fluid. The previous noVNC/VNC backend remains available as a
fallback (see *Backends*).

## Requirements

- A Linux distribution based on Debian/Ubuntu, Fedora, Arch or openSUSE.
  On Arch, install `websockify` from the AUR first.
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
2. installs a pinned Selkies into a private Python environment (no root);
3. generates a short password and shows it once;
4. installs Tailscale with the official script if needed and prints a login
   QR code;
5. publishes the desktop only inside your tailnet with `tailscale serve`;
6. installs and starts a `systemd --user` service that survives reboots;
7. prints the iPad URL as a QR code; with Selkies the URL carries the
   password as `?token=…`, which the video stream uses to authenticate.

On the iPad, scan the QR code (or open the URL) in Safari. Safari asks once
for a user and password: the user is `ipad` and the password is the text after
`token=` in the URL. Then use **Share → Add to Home Screen** for a fullscreen
app; it keeps the token. `ipad-desktop password` makes a new password and
prints the new QR code. If Tailscale asks you to enable HTTPS certificates for your
tailnet, follow the link it prints once.

## Commands

| Command | Purpose |
|---|---|
| `ipad-desktop up` | Set up and start (default) |
| `ipad-desktop status` | Service state and iPad URL |
| `ipad-desktop down` | Stop the desktop |
| `ipad-desktop doctor` | Check dependencies without changing anything |
| `ipad-desktop password` | Generate a new desktop password |
| `ipad-desktop uninstall` | Remove the service and the Serve route |

Pass `--yes` before the command to accept all prompts.

## Configuration

Settings go in `~/.config/remote-desktop/config` as `KEY=value` lines (the
environment overrides them). Restart with `systemctl --user restart
remote-desktop.service` after changing them.

| Variable | Default | Meaning |
|---|---|---|
| `REMOTE_DESKTOP_BACKEND` | `selkies` | `selkies` (video) or `vnc` (noVNC fallback) |
| `REMOTE_DESKTOP_UI_SCALE` | `2` | Selkies: desktop UI scale, `1` or `2` (Cinnamon) |
| `REMOTE_DESKTOP_TEXT_SCALE` | `1` | Selkies: text and app size, `0.5`–`2` (Cinnamon) |
| `REMOTE_DESKTOP_SESSION` | first installed desktop | Desktop command, e.g. `xfce4-session` |
| `REMOTE_DESKTOP_DISPLAY` | `:98` | Virtual X display (never `:0`) |
| `REMOTE_DESKTOP_WEB_PORT` | `6080` | Loopback web port |
| `REMOTE_DESKTOP_RENDER_SCALE` | `1.25` | VNC: `1`, `1.25` or `1.5` times the viewport |
| `REMOTE_DESKTOP_VNC_PORT` | `5998` | VNC: loopback VNC port |
| `REMOTE_DESKTOP_NOVNC_DIR` | downloaded copy | VNC: use another noVNC tree |

## Backends

**Selkies (default).** The iPad asks for its native Retina resolution and the
virtual desktop resizes to it, so text is sharp and never stretched. Cinnamon
then draws the interface at `REMOTE_DESKTOP_UI_SCALE` (2 matches the size of
native iPad apps). If everything looks too big or too small, change
`REMOTE_DESKTOP_TEXT_SCALE` (for example `0.8` fits more code on screen; VS Code
follows it too). These settings live in a separate dconf profile
(`~/.config/dconf/remote_desktop`, seeded from yours on first start), so your
physical desktop is never rescaled. Audio, gamepads, printing and file
transfers are disabled; the clipboard works.

**VNC (fallback).** Set `REMOTE_DESKTOP_BACKEND=vnc` and run
`ipad-desktop up` again. `ipad-desktop up` then stores the allowed Tailscale
login in `REMOTE_DESKTOP_ALLOWED_USERS` (comma-separated for more) and noVNC
rejects other identities. Per-connection options go in the URL: `?scale=1`, `?scale=1.5`, and
`#compression=0`…`#compression=9` (higher saves bandwidth at the cost of host
CPU). Render sizes are capped at 2560 pixels per axis and 4 megapixels.

The noVNC page includes scale, reconnect and clipboard controls and follows
`visualViewport`, including orientation and on-screen keyboard changes.

Firefox launched inside the virtual desktop uses an isolated profile so it can
run alongside Firefox on the physical desktop (snap and Flatpak included).

## Security model

- Nothing listens on a public or LAN interface: Selkies (or Xvnc and
  websockify) bind to `127.0.0.1`, and only `tailscale serve` reaches them,
  over HTTPS, from devices in your tailnet.
- Selkies requires its password (user `ipad`) for the page, and the same
  secret as a session token for the video stream (Safari does not send Basic
  credentials on WebSockets). The URL and QR code therefore contain it: treat
  them like the password. Selkies cannot check the Tailscale identity, so keep
  the tailnet to your own devices or restrict this machine with Tailscale ACLs.
- The password is short (8 characters) while the setup is being tested;
  lengthen it in `new_password` in `bin/ipad-desktop` when it is final.
- With the VNC backend, requests must also carry an allowed
  `Tailscale-User-Login` identity (others receive 403), and the VNC password
  is a second layer.
- Passwords live in `~/.config/remote-desktop/` (mode 600), never in the
  repository.
- Do not use `tailscale funnel` with this project: it would publish the
  desktop to the Internet.

## Logs and troubleshooting

```sh
ipad-desktop doctor
journalctl --user -u remote-desktop.service -f
```

## Development

`test/smoke-selkies.sh` validates the Selkies backend on a real host:
authentication, single instance, native resize for a Retina client, settings
isolation and clean shutdown. `test/smoke.sh` does the same for VNC (both need
Firefox and xrandr, and the service stopped). `test/ci.sh` is the headless
check run in CI across distributions.

### Measuring performance

These tools measure the VNC backend; Selkies shows its own frame rate and
bandwidth in its side menu. Add `stats=1` to the URL (for example `?scale=1.25&stats=1`) to show frames
per second, received bandwidth, remote resolution and reconnect time. To
measure input latency, run `bin/latency-probe` inside the virtual session; it
opens a small coloured window. Then press **Probe latency** in the overlay.
Only timings and sizes are recorded.

`./test/bench.sh [scale...]` repeats this unattended on the host with VS Code
and reports latency, frame rate, bandwidth and CPU per process. Stop the user
service first. Results are in `docs/perf-baseline.md`.

## License

MIT
