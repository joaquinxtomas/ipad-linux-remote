# iPad Linux Remote

Private, browser-oriented Linux desktop for programming from an iPad. The
desktop uses an independent Xorg display whose native geometry can follow the
iPad viewport without stretching the physical monitor.

## Current phase

The current MVP provides an adaptive TigerVNC desktop through noVNC and binds
remote access only to the host's Tailscale address.

## Run locally

Linux Mint 22 with Cinnamon needs:

```sh
sudo apt install tigervnc-standalone-server novnc
```

Create the VNC credential outside the repository:

```sh
mkdir -p ~/.config/remote-desktop
vncpasswd ~/.config/remote-desktop/vnc.passwd
chmod 600 ~/.config/remote-desktop/vnc.passwd
```

```sh
./bin/start-desktop
```

The default display is `:98`; VNC uses `127.0.0.1:5998` and noVNC uses
`127.0.0.1:6080`. Override the display or ports without using physical `:0`:

```sh
REMOTE_DESKTOP_DISPLAY=:97 REMOTE_DESKTOP_VNC_PORT=5997 \
    REMOTE_DESKTOP_WEB_PORT=6081 ./bin/start-desktop
```

Open the URL printed by the command. For the defaults:

```text
http://127.0.0.1:6080/?scale=1.25
```

The custom noVNC page asks Xvnc for 1.25 times the usable browser dimensions,
then scales uniformly to the viewport. This balances text clarity and latency
without changing aspect ratio. Available render scales are `1`, `1.25` and
`1.5`; all are capped at 2560 pixels per axis and 4 megapixels:

```sh
REMOTE_DESKTOP_RENDER_SCALE=1.5 ./bin/start-desktop
```

Quality defaults to 9 and compression to 0 for the direct Tailscale/LAN path.
Use `?scale=1`, `?scale=1.25`, or `?scale=1.5` in the URL to change resolution
for one connection. For a compression comparison, try `#compression=0`,
`#compression=1`, and `#compression=2` without changing the scale. Valid
compression levels are 0–9; higher levels trade host CPU time for less traffic.
The virtual Cinnamon session uses its 2D mode without shadows or visible
animation delays while retaining a 60 FPS ceiling.

Firefox launched from the virtual Cinnamon menu automatically uses an isolated
profile under `~/.local/share/remote-desktop/firefox-profile`, allowing it to
run alongside Firefox on the physical desktop. Use Firefox Sync if both
profiles should share browser data.

The page includes native scale, reconnect and clipboard controls. The
clipboard panel receives Linux text and can send text pasted from iPadOS back
to Linux without logging or persisting it. On iPad, use Safari's **Add to Home
Screen** action for a fullscreen web-app launch. The client follows
`visualViewport`, including orientation and virtual-keyboard changes, without
caching an offline copy of the remote application.

Run the local geometry check:

```sh
./test/smoke.sh
```

Both VNC and HTTP/WebSocket listen on loopback, and Xvnc requires VNC
authentication. Do not place the password file in this repository.

## Private iPad access

After Tailscale is installed and connected on Linux and iPadOS, bind noVNC
only to this host's Tailscale address:

```sh
REMOTE_DESKTOP_WEB_BIND=$(tailscale ip -4) ./bin/start-desktop
```

The launcher rejects wildcard, LAN and non-local Tailscale bind addresses.
VNC itself remains on loopback.

## User service

Link the launcher into your local bin directory, install the user unit, then
replace a manually started session:

```sh
mkdir -p ~/.local/bin
ln -sfn "$(pwd)/bin/start-tailscale-desktop" ~/.local/bin/start-tailscale-desktop
install -Dm644 systemd/remote-desktop.service \
    ~/.config/systemd/user/remote-desktop.service
systemctl --user daemon-reload
systemctl --user enable --now remote-desktop.service
loginctl enable-linger "$USER"
```

Normal operation does not require root. Useful commands:

```sh
systemctl --user status remote-desktop.service
journalctl --user -u remote-desktop.service -f
systemctl --user restart remote-desktop.service
systemctl --user stop remote-desktop.service
```

The unit determines the current Tailscale IPv4, allows only one launcher
instance, restarts after failures, and shuts down the complete virtual session
as one control group. User lingering lets it start after boot without waiting
for an interactive login.

Uninstall it with:

```sh
systemctl --user disable --now remote-desktop.service
loginctl disable-linger "$USER"
rm ~/.config/systemd/user/remote-desktop.service
systemctl --user daemon-reload
```
