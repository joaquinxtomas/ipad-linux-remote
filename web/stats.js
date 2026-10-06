// Opt-in measurement overlay (?stats=1). Records only timings and sizes, never
// input or screen content.
import RFB from './core/rfb.js';

const probeColors = [[255, 0, 255], [0, 255, 0]];
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function percentile(values, p) {
    const sorted = [...values].sort((a, b) => a - b);
    return sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
}

function summarize(values) {
    if (values.length === 0) return null;
    const round = (value) => Math.round(value * 10) / 10;
    return {
        n: values.length,
        min: round(Math.min(...values)),
        p50: round(percentile(values, 0.5)),
        p95: round(percentile(values, 0.95)),
        max: round(Math.max(...values)),
    };
}

function colorIndex(data, offset = 0) {
    return probeColors.findIndex((color) => color.every(
        (value, channel) => Math.abs(value - data[offset + channel]) < 60,
    ));
}

export class Stats {
    constructor() {
        this.frames = 0;
        this.bytes = 0;
        this.onFrame = null;
        this.disconnectedAt = null;
        this.reconnectMs = null;
        this.probeResult = null;
        this.last = { time: performance.now(), frames: 0, bytes: 0 };

        this.hud = document.createElement('div');
        this.hud.style.cssText = 'position:fixed;z-index:2;left:8px;bottom:8px;'
            + 'padding:6px 9px;border-radius:7px;background:#000c;color:#fff;'
            + 'font:12px ui-monospace,monospace;white-space:pre';
        this.text = document.createElement('div');
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = 'Probe latency';
        button.addEventListener('click', () => this.probe(30));
        this.hud.append(this.text, button);
        document.body.append(this.hud);
        setInterval(() => this.render(), 1000);
    }

    attach(rfb) {
        this.rfb = rfb;
        if (this.disconnectedAt !== null) {
            this.reconnectMs = Math.round(performance.now() - this.disconnectedAt);
            this.disconnectedAt = null;
        }
        const display = rfb._display;
        const flip = display.flip.bind(display);
        display.flip = (fromQueue) => {
            const queued = display._renderQ.length !== 0 && !fromQueue;
            flip(fromQueue);
            if (queued) return;
            this.frames++;
            this.onFrame?.();
        };
        rfb._sock._websocket.addEventListener('message', (event) => {
            this.bytes += event.data.byteLength ?? event.data.length ?? 0;
        });
    }

    disconnected() {
        this.disconnectedAt ??= performance.now();
    }

    render() {
        const now = performance.now();
        const seconds = (now - this.last.time) / 1000;
        const fps = (this.frames - this.last.frames) / seconds;
        const kbps = (this.bytes - this.last.bytes) / 1024 / seconds;
        this.last = { time: now, frames: this.frames, bytes: this.bytes };
        const canvas = this.rfb?._canvas;
        const probe = this.probeResult
            ? `${this.probeResult.p50} / ${this.probeResult.p95} ms (n=${this.probeResult.n})`
            : '–';
        this.text.textContent = [
            `frames  ${fps.toFixed(1)}/s`,
            `network ${kbps.toFixed(0)} KB/s`,
            `remote  ${canvas ? `${canvas.width}×${canvas.height}` : '–'}`,
            `view    ${Math.round(innerWidth)}×${Math.round(innerHeight)} @${devicePixelRatio}x`,
            `probe   p50/p95 ${probe}`,
            `reconn  ${this.reconnectMs ?? '–'} ms`,
        ].join('\n');
    }

    pixel(x, y) {
        return this.rfb._canvas.getContext('2d').getImageData(x, y, 1, 1).data;
    }

    findProbe() {
        const canvas = this.rfb._canvas;
        const { width, height } = canvas;
        const data = canvas.getContext('2d').getImageData(0, 0, width, height).data;
        for (const wanted of [0, 1]) {
            let count = 0, sumX = 0, sumY = 0;
            for (let y = 0; y < height; y += 2) {
                for (let x = 0; x < width; x += 2) {
                    if (colorIndex(data, (y * width + x) * 4) !== wanted) continue;
                    count++;
                    sumX += x;
                    sumY += y;
                }
            }
            if (count >= 50) {
                return { x: Math.round(sumX / count), y: Math.round(sumY / count) };
            }
        }
        return null;
    }

    // Click-to-photon latency against bin/latency-probe, measured when the
    // changed pixel reaches the visible canvas (excludes the final display
    // refresh of at most one frame).
    async probe(samples) {
        const target = this.rfb && this.findProbe();
        if (!target) {
            this.probeResult = null;
            this.text.textContent = 'probe window not found (run bin/latency-probe)';
            return null;
        }
        const latencies = [];
        let timeouts = 0;
        for (let i = 0; i < samples; i++) {
            await sleep(150 + Math.random() * 150);
            const before = colorIndex(this.pixel(target.x, target.y));
            const start = performance.now();
            const latency = await new Promise((resolve) => {
                const timer = setTimeout(() => {
                    this.onFrame = null;
                    resolve(null);
                }, 2000);
                this.onFrame = () => {
                    const now = colorIndex(this.pixel(target.x, target.y));
                    if (now < 0 || now === before) return;
                    clearTimeout(timer);
                    this.onFrame = null;
                    resolve(performance.now() - start);
                };
                RFB.messages.pointerEvent(this.rfb._sock, target.x, target.y, 1);
                RFB.messages.pointerEvent(this.rfb._sock, target.x, target.y, 0);
            });
            if (latency === null) timeouts++;
            else latencies.push(latency);
        }
        this.probeResult = summarize(latencies);
        if (this.probeResult) this.probeResult.timeouts = timeouts;
        this.render();
        return this.probeResult;
    }

    async measure(action) {
        const start = { time: performance.now(), frames: this.frames, bytes: this.bytes };
        await action();
        const seconds = (performance.now() - start.time) / 1000;
        return {
            seconds: Math.round(seconds * 10) / 10,
            fps: Math.round((this.frames - start.frames) / seconds * 10) / 10,
            kbps: Math.round((this.bytes - start.bytes) / 1024 / seconds),
        };
    }

    // Wheel notches over the centre of the remote screen: half down, half up.
    async scroll(seconds, rate = 30) {
        const canvas = this.rfb._canvas;
        const x = Math.floor(canvas.width / 2);
        const y = Math.floor(canvas.height / 2);
        const notches = seconds * rate;
        for (let i = 0; i < notches; i++) {
            const button = i < notches / 2 ? 1 << 4 : 1 << 3;
            RFB.messages.pointerEvent(this.rfb._sock, x, y, button);
            RFB.messages.pointerEvent(this.rfb._sock, x, y, 0);
            await sleep(1000 / rate);
        }
    }

    // Unattended run used by test/bench.sh; phases are marked on the console
    // so the host can sample CPU usage for each of them.
    async bench() {
        const mark = (name) => console.log(`BENCH mark ${name}`);
        await sleep(5000);
        const canvas = this.rfb._canvas;
        mark('probe-start');
        const probe = await this.probe(40);
        mark('probe-end');
        await sleep(1000);
        mark('idle-start');
        const idle = await this.measure(() => sleep(10000));
        mark('idle-end');
        mark('scroll-start');
        const scroll = await this.measure(() => this.scroll(10));
        mark('scroll-end');
        const result = {
            remote: `${canvas.width}x${canvas.height}`,
            viewport: `${innerWidth}x${innerHeight}`,
            probe,
            idle,
            scroll,
        };
        console.log(`BENCH result ${JSON.stringify(result)}`);
    }
}
