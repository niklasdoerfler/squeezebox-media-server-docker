# Squeezebox Media Server in Docker

Run [Logitech Media Server (aka Squeezebox Media Server aka Lyrion Music Server)](https://github.com/LMS-Community/slimserver) in a Docker container.

This image packages LMS with sensible defaults, optional PulseAudio passthrough, and a persistent data volume for your configuration, cache, and playlists.

- Image: `niklasdoerfler/squeezebox-media-server-docker`
- Example compose file: see `./docker-compose.yml` in this repository

## Features
- Ready-to-run LMS in a container
- Data persistence via a named volume mounted at `/srv/squeezebox`
- Exposes the standard LMS ports (9000, 9090, 3483/tcp+udp)
- Optional host audio output via PulseAudio socket passthrough
- Runs as your host user (UID) for seamless PulseAudio access

## Requirements
- Docker / Podman (latest stable)
- Optional: Docker Compose v2+
- Linux host with PulseAudio if you want local audio output from the container
- A user session running PulseAudio (for passthrough)

## Quick start (docker run)
The container needs ports and a persistent volume. For PulseAudio passthrough, it should run as your user and mount your PulseAudio runtime dir.

```bash
# Optional: create a named volume for LMS data
docker volume create squeezebox

# Run LMS
docker run -d \
  --name lms \
  --restart=always \
  -p 9000:9000 \
  -p 9090:9090 \
  -p 3483:3483 \
  -p 3483:3483/udp \
  -v /etc/localtime:/etc/localtime:ro \
  -v /dev/shm:/dev/shm \
  -v /etc/machine-id:/etc/machine-id \
  -v /var/lib/dbus:/var/lib/dbus \
  -v /run/user/$(id -u)/pulse:/run/user/$(id -u)/pulse \
  -v squeezebox:/srv/squeezebox \
  -e PULSE_SERVER=unix:/tmp/pulseaudio.socket \
  -e PULSE_COOKIE=/tmp/pulseaudio.cookie \
  -u $(id -u) \
  niklasdoerfler/squeezebox-media-server-docker
```

Then open the web UI at:
- http://localhost:9000

## Using docker-compose
An example compose file is provided at `./docker-compose.yml`. It builds or pulls the image, mounts the required volumes, sets environment for PulseAudio, runs as your user, and exposes the LMS ports.

- Compose up: `docker compose up -d`
- Compose down: `docker compose down`
- Follow logs: `docker compose logs -f`

If you need to change the user, export `UID` in your shell first (e.g., `export UID=$(id -u)`), or replace `$UID` with your numeric UID.

## Volumes and data persistence
- `/srv/squeezebox` (named volume `squeezebox` by default): stores LMS configuration, cache, state, and playlists.
- Do not store music inside the container. Instead, mount your music library from the host into the container (e.g., `-v /path/to/music:/music`) and configure that path in the LMS UI.

Example adding a music mount:
```yaml
# inside docker-compose.yml service:
# ...existing code...
    volumes:
      # ...existing code...
      - /path/to/your/music:/music:ro
# ...existing code...
```

## Ports
- 9000/tcp: Web UI and streaming
- 9090/tcp: CLI / telnet interface
- 3483/tcp, 3483/udp: SlimProto for player discovery/control

Ensure your firewall allows these ports if clients are on another host.

## Environment variables
- PULSE_SERVER: set to `unix:/tmp/pulseaudio.socket` for PulseAudio passthrough (as in the compose example).
- PULSE_COOKIE: set to `/tmp/pulseaudio.cookie` to allow the container to authenticate to the host PulseAudio daemon.

Note: The container expects the host PulseAudio socket and cookie to be accessible via the mounted runtime dir, which the image setup maps to `/tmp/pulseaudio.socket` and `/tmp/pulseaudio.cookie` inside the container.

## Running as your user (PulseAudio)
For PulseAudio passthrough to work:
- Run the container as your host user (use `-u $(id -u)` or `user: $UID` in compose).
- Mount your PulseAudio runtime dir: `/run/user/$UID/pulse` from the host to the same path in the container.
- Set `PULSE_SERVER` and `PULSE_COOKIE` as shown above.

If you do not need audio output or input from the container directly, you can omit the PulseAudio mounts, env vars, and user mapping.

## Custom Convert plugin: live PulseAudio streaming

With the Custom Convert plugin you can stream live audio from a PulseAudio source (e.g., a microphone or the system “monitor” of your speakers) directly through LMS to your players.

What it does:
- Defines a pseudo URL scheme (wavin://) that LMS can “play”.
- Uses parec or ffmpeg inside the container to capture a PulseAudio source and transcode it (e.g., to FLAC or MP3) in real time for LMS players.

Prerequisites:
- PulseAudio passthrough as shown above (mount /run/user/$UID/pulse, set PULSE_SERVER and PULSE_COOKIE, and run as your user).
- LMS Settings → Plugins → enable “Custom-Convert”.
- Capture tools inside the container: either pulseaudio-utils (for parec) and encoders (flac, lame), or ffmpeg.
  - If you need them, add to your image (example):
    # RUN apt-get update && apt-get install -y pulseaudio-utils flac lame ffmpeg && rm -rf /var/lib/apt/lists/*

Where to put configs:
- In this image, LMS preferences live under /srv/squeezebox/prefs (persistent).
- Create/edit:
/srv/squeezebox/prefs/custom-types.conf
/srv/squeezebox/prefs/custom-convert.conf

Example custom-types.conf:
```text
# Define a pseudo URL scheme "livepa://<source>"
livepa livepa url
```

Example custom-convert.conf (parec + FLAC and MP3 fallbacks):
```text
# Live PulseAudio → FLAC (for players supporting FLAC)
livepa flc * *
  [parec] --device="$FILE$" --format=s16le --rate=48000 --channels=2 | [flac] -cs --endian=little --sign=signed --channels=2 --sample-rate=48000 --bps=16 -

# Live PulseAudio → MP3 (for players without FLAC support)
livepa mp3 * *
  [parec] --device="$FILE$" --format=s16le --rate=44100 --channels=2 | [lame] -r -s 44.1 --bitwidth 16 -m j -b 192 - -
```

Alternative using ffmpeg (no parec needed):
```text
# FLAC
livepa flc * *
  [ffmpeg] -nostdin -f pulse -i "$FILE$" -f flac - | cat

# MP3
livepa mp3 * *
  [ffmpeg] -nostdin -f pulse -i "$FILE$" -f mp3 -b:a 192k - | cat
```

How to find your PulseAudio source name:
- On the host (same user as the container runs with): pactl list short sources
- Typical examples:
  - default
  - alsa_input.pci-0000_00_1f.3.analog-stereo
  - alsa_output.pci-0000_00_1f.3.analog-stereo.monitor

How to play the live stream:
- In LMS, add a Favorite with a URL like:
  - waavin://default
  - wavin://alsa_output.pci-0000_00_1f.3.analog-stereo.monitor
- Start playback of that Favorite on any player. Stop playback to end the capture.
- Note: The pipeline runs in the LMS container; ensure the required binaries are present.

## Upgrading
```bash
docker pull niklasdoerfler/squeezebox-media-server-docker
# If using compose
docker compose pull && docker compose up -d
# If using docker run
docker stop lms && docker rm lms
# re-run the docker run command; your data persists in the 'squeezebox' volume
```

## Security notes
- Port 9090 exposes the LMS CLI; avoid exposing it to untrusted networks.
- Consider binding to localhost only or restricting via firewall when appropriate.

## License
This repository’s code is provided under the license declared in the project (if any). Logitech Media Server itself is licensed under its respective upstream license.