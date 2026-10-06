# Performance baseline

Measured 2026-09-29 with `test/bench.sh` on the host (Linux Mint 22.3,
12 threads, GTX 1650 unused by the session). The client was headless Firefox
on the same machine through `127.0.0.1`, so these numbers exclude the network
and iPad decoding and include Firefox competing for host CPU.

Viewport: 1180×820 CSS px (iPad 10th gen landscape). VS Code opened
`rfb.js` maximised in the virtual session.

- **probe**: click-to-pixel latency against `bin/latency-probe`, 40 samples,
  measured when the pixel reaches the visible canvas (the display refresh adds
  up to one more frame).
- **scroll**: 30 wheel notches/s over VS Code for 10 s; frames/s and data
  received by the client.
- **CPU**: percent of one core per process group during the scroll.

## Current defaults (quality 9, compression 0) by render scale

| Scale | Remote | Probe p50 / p95 | Scroll fps | Scroll MB/s | Cinnamon CPU | Xvnc CPU |
|---|---|---|---|---|---|---|
| 1    | 1180×820  | 69 / 94 ms  | 24.5 | 16.6 | 89 %  | 28 % |
| 1.25 | 1475×852¹ | 65 / 100 ms | 24.9 | 16.5 | 152 % | 29 % |
| 1.5  | 1770×1230 | 66 / 101 ms | 19.4 | 18.3 | 185 % | 32 % |

¹ Firefox reported a 1180×682 viewport in this run. A later run at the
correct 1475×1025 gave 75 / 108 ms, 20.6 fps and 17.4 MB/s.

## Encoder parameters at scale 1.25

| Hash parameters | Probe p50 / p95 | Scroll fps | Scroll MB/s |
|---|---|---|---|
| defaults (`compression=0&quality=9`) | 75 / 108 ms | 20.6 | 17.4 |
| `compression=1`                      | 74 / 101 ms | 20.0 | 16.6 |
| `compression=2`                      | 14 / 32 ms  | 24.3 | 14.3 |
| `compression=6`                      | 14 / 32 ms  | 22.8 | 13.4 |
| `quality=6`                          | 31 / 60 ms  | 27.5 | 7.7  |
| `compression=2&quality=8`            | – (probe not found) | 51.1 | 7.8 |
| `compression=2&quality=6`            | 14–15 / 31–45 ms | 51.2 | 5.6 |

Control: bare Xvnc without Cinnamon, defaults, scale 1: probe 11 / 15 ms.

## Findings

1. Compression levels 0 and 1 add about 60 ms of input-to-pixel latency in
   the Cinnamon session; level 2 or higher removes it. The cause inside the
   TigerVNC/noVNC pipeline is not yet identified.
2. Quality 9 costs about 14–17 MB/s (≈120–140 Mbit/s) while scrolling. That
   saturates typical Wi-Fi and remote Tailscale paths. Quality 8 halves it and
   doubles the scroll frame rate locally. Text clarity at quality 8 and 6
   still has to be judged on the iPad.
3. The session renders through `llvmpipe`. Cinnamon's compositor is the
   largest server cost while scrolling and grows with pixel count
   (89 % → 185 % of a core from scale 1 to 1.5); render scale barely changes
   latency.
4. Idle sessions send no data (VS Code unfocused, cursor not blinking).

## Pending

- Same measurements from the iPad (`?stats=1`, *Probe latency* button) on
  home Wi-Fi and on another network; `tailscale ping` direct vs DERP.
- The probe occasionally is not detected (VS Code window mapped over it);
  rerun when `probe` is null.
