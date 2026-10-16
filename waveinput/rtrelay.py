#!/usr/bin/env python3
"""
Real-time audio relay with clock-drift correction for LMS waveinput.

Reads audio from stdin (parec output) in a background thread and relays it to
stdout (LMS). Three problems are addressed:

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

  3. Input gaps: if parec temporarily delivers no data (e.g. after a stall
     recovery), the output is bridged with silence at real-time pace so LMS
     never underruns. When data resumes, the drift controller re-aligns.

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
SAMPLE_RATE      = 44100
CHANNELS         = 2
BYTES_PER_SAMPLE = 2                                    # s16le
BYTES_PER_FRAME  = CHANNELS * BYTES_PER_SAMPLE          # 4
BYTES_PER_SEC    = SAMPLE_RATE * BYTES_PER_FRAME        # 176400

CHUNK_MS         = 10
FRAMES_PER_CHUNK = SAMPLE_RATE * CHUNK_MS // 1000      # 441
CHUNK_SIZE       = FRAMES_PER_CHUNK * BYTES_PER_FRAME  # 1764 bytes
SILENCE_CHUNK    = bytes(CHUNK_SIZE)                    # pre-allocated zeros

MAX_BUFFER_MS    = 2000
MAX_BUFFER       = BYTES_PER_SEC * MAX_BUFFER_MS // 1000

# P-controller for clock drift correction
Kp               = 0.3
MAX_RATE_ADJUST  = 0.02         # clamp to ±2%
PIPE_LATENCY_MS  = 100          # target: keep this many ms of audio buffered ahead in LMS

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
    "bytes_sent"       : 0,
    "total_dropped_ms" : 0,
    "drop_events"      : 0,
    "total_stalls"     : 0,
    "max_buffer_ms"    : 0,
    "max_rate_adjust"  : 0.0,
    "total_silence_ms" : 0,
    "total_concealed_ms": 0,
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
# Fade-in helper — applied to first real chunk after a gap to avoid click
# ---------------------------------------------------------------------------
FADE_IN_FRAMES = 88   # 2ms at 44100 Hz — inaudible but eliminates discontinuity

def apply_fade_in(data: bytes) -> bytes:
    """Linearly fade in the first FADE_IN_FRAMES frames of a PCM chunk."""
    samples = np.frombuffer(data, dtype='<i2').reshape(-1, 2).copy()
    n = min(FADE_IN_FRAMES, len(samples))
    fade = np.linspace(0.0, 1.0, n, dtype=np.float32)
    samples[:n] = (samples[:n] * fade[:, None]).astype(np.int16)
    return samples.tobytes()


# ---------------------------------------------------------------------------
# Input thread — drains parec, discards excess
# ---------------------------------------------------------------------------
def drain_input():
    while True:
        data = sys.stdin.buffer.read1(CHUNK_SIZE)
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
         f"PIPE_LATENCY={PIPE_LATENCY_MS}ms  MAX_BUFFER={MAX_BUFFER_MS}ms  log={LOG_FILE}")

# ---------------------------------------------------------------------------
# Main loop — resample + write to LMS, bridge gaps with silence
# ---------------------------------------------------------------------------
out           = sys.stdout.buffer
last_stats    = time.monotonic()
wall_start    = time.monotonic()
silence_start = None   # set when bridging a gap
last_raw_chunk = SILENCE_CHUNK  # last real audio chunk, used for concealment


def write_chunk(chunk: bytes) -> float:
    """Write chunk to stdout, return stall duration in ms."""
    t0 = time.monotonic()
    out.write(chunk)
    out.flush()
    return (time.monotonic() - t0) * 1000


def current_drift() -> float:
    """Return drift vs target: positive = too far ahead, negative = not yet at PIPE_LATENCY_MS ahead."""
    with lock:
        audio_time_s = stats["bytes_sent"] / BYTES_PER_SEC
    return audio_time_s - (time.monotonic() - wall_start) - PIPE_LATENCY_MS / 1000


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
            # ---- Resume after a gap ----
            if silence_start is not None:
                gap_ms = (time.monotonic() - silence_start) * 1000
                if gap_ms >= 50:
                    log.info(f"GAP    ended after {gap_ms:.0f}ms, resuming audio")
                silence_start = None

            # ---- P-controller drift correction ----
            drift_s     = current_drift()
            rate_adjust = max(-MAX_RATE_ADJUST,
                              min(MAX_RATE_ADJUST, -drift_s * Kp))
            target_frames = max(1, round(FRAMES_PER_CHUNK * (1 + rate_adjust)))
            chunk         = resample_chunk(raw_chunk, target_frames)

            stall_ms = write_chunk(chunk)

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
            # ---- Buffer empty — bridge with silence at real-time pace ----
            # Short gaps (< 20ms) are PulseAudio's natural block delivery jitter
            # and are absorbed silently by the LMS/player buffers.
            # Only output silence for real gaps to keep the pipe alive.
            MAX_PIPE_GAP_MS = 20

            if silence_start is None:
                silence_start = time.monotonic()

            gap_so_far_ms = (time.monotonic() - silence_start) * 1000

            if gap_so_far_ms < MAX_PIPE_GAP_MS:
                time.sleep(0.001)
                continue

            drift_s = current_drift()
            if drift_s > 0:
                time.sleep(min(drift_s, MAX_PIPE_GAP_MS / 1000))

            stall_ms = write_chunk(SILENCE_CHUNK)

            with lock:
                stats["bytes_sent"]       += CHUNK_SIZE
                stats["total_silence_ms"] += CHUNK_MS

            if stall_ms > STALL_WARN_MS:
                with lock:
                    stats["total_stalls"] += 1
                log.warning(f"STALL (silence) LMS blocked for {stall_ms:.0f}ms  "
                            f"stalls={stats['total_stalls']}")

        # ---- Periodic stats ----
        now = time.monotonic()
        if now - last_stats >= LOG_INTERVAL_S:
            with lock:
                sent_s    = stats["bytes_sent"] / BYTES_PER_SEC
                peak_buf  = stats["max_buffer_ms"]
                peak_rate = stats["max_rate_adjust"]
                sil_ms    = stats["total_silence_ms"]
                stats["max_buffer_ms"]   = 0
                stats["max_rate_adjust"] = 0.0
            elapsed_s     = now - wall_start
            pipe_drift_ms = (sent_s - elapsed_s) * 1000
            gap_status    = f"  *** IN GAP {(now - silence_start)*1000:.0f}ms ***" if silence_start else ""
            log.info(f"STATS buffer={buf_ms}ms  peak_buf={peak_buf}ms  "
                     f"pipe_drift={pipe_drift_ms:+.0f}ms  "
                     f"peak_rate={peak_rate*100:+.2f}%  "
                     f"stalls={stats['total_stalls']}  "
                     f"drops={stats['drop_events']} ({stats['total_dropped_ms']}ms)  "
                     f"silence={sil_ms}ms  sent={sent_s:.1f}s{gap_status}")
            last_stats = now

except (BrokenPipeError, KeyboardInterrupt):
    with lock:
        log.info(f"rtrelay stopped  stalls={stats['total_stalls']}  "
                 f"drops={stats['drop_events']} ({stats['total_dropped_ms']}ms)  "
                 f"silence={stats['total_silence_ms']}ms total")
