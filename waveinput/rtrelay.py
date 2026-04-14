#!/usr/bin/env python3
"""
Real-time audio relay with clock-drift correction for LMS waveinput.

Reads audio from stdin (parec output) in a background thread and relays it to
stdout (LMS). Two problems are addressed:

  1. Buffer accumulation: if LMS reads slowly during multiroom resync, parec's
     output would pile up. The input thread caps the buffer at MAX_BUFFER_MS
     by discarding the oldest samples.

  2. Clock drift: PulseAudio virtual sinks run slightly faster or slower than
     the system wall-clock (~0.1%). Over time this shifts audio timestamps and
     causes audio/video desync.
     Fix: each output chunk is resampled to a slightly different length using a
     P-controller that keeps (audio_bytes_sent / bytes_per_sec) == wall_clock.
     Adjustment is always < MAX_RATE_ADJUST (default ±2%), well below the
     audible threshold for linear interpolation (~5%).

Log file: /tmp/rtrelay.log
"""

import sys
import time
import threading
import logging
import numpy as np

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
SAMPLE_RATE    = 44100
CHANNELS       = 2
BYTES_PER_SAMPLE = 2                                      # s16le
BYTES_PER_FRAME  = CHANNELS * BYTES_PER_SAMPLE            # 4
BYTES_PER_SEC    = SAMPLE_RATE * BYTES_PER_FRAME          # 176400

CHUNK_MS         = 10
FRAMES_PER_CHUNK = SAMPLE_RATE * CHUNK_MS // 1000        # 441
CHUNK_SIZE       = FRAMES_PER_CHUNK * BYTES_PER_FRAME    # 1764 bytes

MAX_BUFFER_MS    = 2000           # discard input if buffer exceeds this
MAX_BUFFER       = BYTES_PER_SEC * MAX_BUFFER_MS // 1000

# P-controller for clock drift correction
Kp               = 0.3           # proportional gain
MAX_RATE_ADJUST  = 0.02          # clamp to ±2% — well below audible threshold

LOG_INTERVAL_S   = 10
STALL_WARN_MS    = 50
LOG_FILE         = "/tmp/rtrelay.log"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log = logging.getLogger("rtrelay")
log.setLevel(logging.DEBUG)
fmt = logging.Formatter("%(asctime)s %(levelname)-5s %(message)s",
                        datefmt="%Y-%m-%d %H:%M:%S")
for handler in (logging.FileHandler(LOG_FILE), logging.StreamHandler(sys.stderr)):
    handler.setFormatter(fmt)
    log.addHandler(handler)

# ---------------------------------------------------------------------------
# Shared state
# ---------------------------------------------------------------------------
buf  = bytearray()
lock = threading.Lock()
eof  = threading.Event()

stats = {
    "bytes_sent"       : 0,   # resampled bytes actually written to LMS
    "total_dropped_ms" : 0,
    "drop_events"      : 0,
    "total_stalls"     : 0,
    "max_buffer_ms"    : 0,
    "max_rate_adjust"  : 0.0, # peak rate adjustment magnitude this interval
}


# ---------------------------------------------------------------------------
# Resampler — linear interpolation, stereo s16le
# ---------------------------------------------------------------------------
def resample_chunk(data: bytes, target_frames: int) -> bytes:
    """Resample raw s16le stereo PCM to target_frames via linear interpolation."""
    src_frames = len(data) // BYTES_PER_FRAME
    if src_frames == target_frames:
        return data
    samples = np.frombuffer(data, dtype='<i2').reshape(src_frames, 2).astype(np.float32)
    x_src = np.arange(src_frames, dtype=np.float32)
    x_dst = np.linspace(0, src_frames - 1, target_frames, dtype=np.float32)
    left  = np.interp(x_dst, x_src, samples[:, 0]).astype('<i2')
    right = np.interp(x_dst, x_src, samples[:, 1]).astype('<i2')
    return np.column_stack([left, right]).tobytes()


# ---------------------------------------------------------------------------
# Input thread — drains parec, discards excess
# ---------------------------------------------------------------------------
def drain_input():
    while True:
        data = sys.stdin.buffer.read(CHUNK_SIZE)
        if not data:
            eof.set()
            return
        with lock:
            buf.extend(data)
            buf_ms = len(buf) * 1000 // BYTES_PER_SEC
            if buf_ms > stats["max_buffer_ms"]:
                stats["max_buffer_ms"] = buf_ms
            if len(buf) > MAX_BUFFER:
                trim    = len(buf) - MAX_BUFFER
                dropped = trim * 1000 // BYTES_PER_SEC
                del buf[:trim]
                stats["total_dropped_ms"] += dropped
                stats["drop_events"]      += 1
                log.warning(f"DROP  buffer was {buf_ms}ms → dropped {dropped}ms "
                            f"(total: {stats['drop_events']} events, "
                            f"{stats['total_dropped_ms']}ms)")


threading.Thread(target=drain_input, daemon=True, name="drain").start()
log.info(f"rtrelay started  Kp={Kp}  MAX_RATE={MAX_RATE_ADJUST*100:.0f}%  "
         f"MAX_BUFFER={MAX_BUFFER_MS}ms  log={LOG_FILE}")

# ---------------------------------------------------------------------------
# Main loop — resample + write to LMS
# ---------------------------------------------------------------------------
out        = sys.stdout.buffer
last_stats = time.monotonic()
wall_start = time.monotonic()

try:
    while not eof.is_set():
        with lock:
            if len(buf) >= CHUNK_SIZE:
                raw_chunk = bytes(buf[:CHUNK_SIZE])
                buf_ms    = len(buf) * 1000 // BYTES_PER_SEC
                del buf[:CHUNK_SIZE]
            else:
                raw_chunk = None
                buf_ms    = 0

        if raw_chunk:
            # --- P-controller: keep audio_time == wall_time ---
            with lock:
                audio_time_s = stats["bytes_sent"] / BYTES_PER_SEC
            wall_time_s  = time.monotonic() - wall_start
            drift_s      = audio_time_s - wall_time_s   # + ahead  − behind

            # rate_adjust > 0 → more frames (speed up) when behind
            # rate_adjust < 0 → fewer frames (slow down) when ahead
            rate_adjust   = max(-MAX_RATE_ADJUST,
                                min(MAX_RATE_ADJUST, -drift_s * Kp))
            target_frames = max(1, round(FRAMES_PER_CHUNK * (1 + rate_adjust)))
            chunk         = resample_chunk(raw_chunk, target_frames)

            t0 = time.monotonic()
            out.write(chunk)   # may block if LMS reads slowly
            out.flush()
            stall_ms = (time.monotonic() - t0) * 1000

            with lock:
                stats["bytes_sent"] += len(chunk)
                adj_abs = abs(rate_adjust)
                if adj_abs > stats["max_rate_adjust"]:
                    stats["max_rate_adjust"] = adj_abs

            if stall_ms > STALL_WARN_MS:
                with lock:
                    stats["total_stalls"] += 1
                log.warning(f"STALL LMS blocked for {stall_ms:.0f}ms  "
                            f"buffer={buf_ms}ms  stalls={stats['total_stalls']}")
        else:
            time.sleep(0.001)

        # --- Periodic stats ---
        now = time.monotonic()
        if now - last_stats >= LOG_INTERVAL_S:
            with lock:
                sent_s       = stats["bytes_sent"] / BYTES_PER_SEC
                peak_buf     = stats["max_buffer_ms"]
                peak_rate    = stats["max_rate_adjust"]
                stats["max_buffer_ms"]  = 0
                stats["max_rate_adjust"] = 0.0
            elapsed_s    = now - wall_start
            pipe_drift_ms = (sent_s - elapsed_s) * 1000
            log.info(f"STATS buffer={buf_ms}ms  peak_buf={peak_buf}ms  "
                     f"pipe_drift={pipe_drift_ms:+.0f}ms  "
                     f"peak_rate={peak_rate*100:+.2f}%  "
                     f"stalls={stats['total_stalls']}  "
                     f"drops={stats['drop_events']} ({stats['total_dropped_ms']}ms)  "
                     f"sent={sent_s:.1f}s")
            last_stats = now

except (BrokenPipeError, KeyboardInterrupt):
    with lock:
        log.info(f"rtrelay stopped  stalls={stats['total_stalls']}  "
                 f"drops={stats['drop_events']} ({stats['total_dropped_ms']}ms total)")
