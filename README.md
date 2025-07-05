# Squeezebox Media Server Docker

A comprehensive Docker implementation of the Lyrion Music Server (formerly Squeezebox Media Server) with enhanced audio capabilities, including PulseAudio support and WaveInput plugin for streaming PC audio.

## Overview

This Docker container provides a complete setup for running Lyrion Music Server with additional features for audio streaming and integration. It's built on top of the official Lyrion Music Server image and includes support for various audio backends, making it ideal for home audio systems and multi-room setups.

## Features

- **Lyrion Music Server 9.0.3** - The latest stable version of the music server
- **PulseAudio Support** - Stream system audio directly to your Squeezebox players
- **Snapcast Integration** - Multi-room audio synchronization capabilities
- **WaveInput Plugin** - Custom plugin for PC audio streaming via ALSA
- **Multiple Audio Backends** - Support for both PulseAudio and Snapcast backends
- **Enhanced Audio Codecs** - Includes FAAD, FLAC, LAME, and SoX for comprehensive format support
- **Easy Configuration** - Environment variables for simple setup
- **Persistent Storage** - Volume mounts for configuration, logs, and music library

## Quick Start

### Using Docker Compose (Recommended)

1. Clone this repository:
   ```bash
   git clone https://github.com/niklasdoerfler/squeezebox-media-server-docker.git
   cd squeezebox-media-server-docker
   ```

2. Set your user ID (required for proper permissions):
   ```bash
   export UID=$(id -u)
   ```

3. Start the container:
   ```bash
   docker-compose up -d
   ```

4. Access the web interface at `http://localhost:9000`

### Using Docker Run

```bash
docker run -d \
  --name squeezebox-media-server \
  -p 9000:9000 \
  -p 9090:9090 \
  -p 3483:3483 \
  -p 3483:3483/udp \
  -v /path/to/music:/music \
  -v /path/to/config:/config \
  -v /etc/localtime:/etc/localtime:ro \
  --restart unless-stopped \
  niklasdoerfler/squeezebox-media-server-docker
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WAVIN_BACKEND` | `pulse` | Audio backend (`pulse` or `snap`) |
| `WAVIN_SNAPSERVER_HOST` | `pulse` | Snapcast server hostname |
| `WAVIN_PULSEAUDIO_SERVER` | `pulse` | PulseAudio server address |
| `PUID` | `1000` | User ID for file permissions |
| `PGID` | `1000` | Group ID for file permissions |
| `HTTP_PORT` | `9000` | Web interface port |
| `EXTRA_ARGS` | - | Additional arguments for slimserver.pl |

### Volume Mounts

| Container Path | Description |
|----------------|-------------|
| `/config` | Configuration files, preferences, logs, and cache |
| `/music` | Music library directory |
| `/playlist` | Playlist files |
| `/etc/localtime` | System timezone (read-only) |

### Exposed Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 9000 | TCP | Web interface |
| 9090 | TCP | Control interface |
| 3483 | TCP/UDP | SlimProto communication |

### Audio Backend Configuration

#### PulseAudio Backend (Default)
For streaming system audio through PulseAudio:

```yaml
environment:
  - WAVIN_BACKEND=pulse
  - PULSE_SERVER=unix:/tmp/pulseaudio.socket
  - PULSE_COOKIE=/tmp/pulseaudio.cookie
volumes:
  - /run/user/$UID/pulse:/run/user/$UID/pulse
```

#### Snapcast Backend
For multi-room audio synchronization:

```yaml
environment:
  - WAVIN_BACKEND=snap
  - WAVIN_SNAPSERVER_HOST=your-snapserver-host
```

## Setup Instructions

### Docker Compose Setup

1. **Create a docker-compose.yml file** (or use the provided one):

```yaml
version: "2.3"

services:
  lms:
    image: niklasdoerfler/squeezebox-media-server-docker
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /dev/shm:/dev/shm
      - /etc/machine-id:/etc/machine-id
      - /run/user/$UID/pulse:/run/user/$UID/pulse
      - /var/lib/dbus:/var/lib/dbus
      - squeezebox:/config
      - /path/to/your/music:/music
    environment:
      - PULSE_SERVER=unix:/tmp/pulseaudio.socket
      - PULSE_COOKIE=/tmp/pulseaudio.cookie
      - WAVIN_BACKEND=pulse
    user: $UID
    ports:
      - "9000:9000"
      - "9090:9090"
      - "3483:3483"
      - "3483:3483/udp"
    restart: unless-stopped
    init: true

volumes:
  squeezebox:
```

2. **Set environment variables**:
   ```bash
   export UID=$(id -u)
   ```

3. **Start the services**:
   ```bash
   docker-compose up -d
   ```

### Docker Setup

1. **Build the image** (optional, if you want to build locally):
   ```bash
   docker build -t squeezebox-media-server .
   ```

2. **Run the container**:
   ```bash
   docker run -d \
     --name squeezebox-media-server \
     -p 9000:9000 \
     -p 9090:9090 \
     -p 3483:3483 \
     -p 3483:3483/udp \
     -v /path/to/your/music:/music \
     -v squeezebox-config:/config \
     -v /etc/localtime:/etc/localtime:ro \
     -e WAVIN_BACKEND=pulse \
     --restart unless-stopped \
     niklasdoerfler/squeezebox-media-server-docker
   ```

## Updating

### Docker Compose

```bash
docker-compose pull
docker-compose up -d
```

### Docker

```bash
docker pull niklasdoerfler/squeezebox-media-server-docker
docker stop squeezebox-media-server
docker rm squeezebox-media-server
# Run the container again with your original parameters
```

## Troubleshooting

### Common Issues

#### Web Interface Not Accessible
- Ensure port 9000 is not blocked by firewall
- Check if the container is running: `docker ps`
- Verify port mapping in your docker run command or docker-compose.yml

#### Audio Issues
- **PulseAudio problems**: Ensure PulseAudio is running on the host and the socket is accessible
- **Permission issues**: Check that the user ID matches between container and host
- **No audio devices**: Verify audio backend configuration in environment variables

#### Music Library Not Detected
- Check volume mount paths in your configuration
- Ensure the music directory has proper permissions
- Verify the path exists on the host system

#### Container Won't Start
- Check Docker logs: `docker logs squeezebox-media-server`
- Verify all required environment variables are set
- Ensure no port conflicts with other services

### Debugging

1. **Check container logs**:
   ```bash
   docker logs squeezebox-media-server
   ```

2. **Access container shell**:
   ```bash
   docker exec -it squeezebox-media-server /bin/bash
   ```

3. **Check server logs**:
   ```bash
   docker exec squeezebox-media-server tail -f /config/logs/server.log
   ```

### Performance Optimization

- Use SSD storage for the config volume for better performance
- Allocate sufficient CPU and memory resources
- Consider using host networking for better performance: `--network host`

## Contributing

We welcome contributions to improve this Docker image! Here's how you can help:

### Reporting Issues

1. Search existing issues to avoid duplicates
2. Use the issue template when creating new issues
3. Include relevant logs and system information
4. Provide steps to reproduce the problem

### Submitting Changes

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature-name`
3. Make your changes following the coding standards
4. Test your changes thoroughly
5. Update documentation as needed
6. Submit a pull request with a clear description

### Development Setup

1. Clone the repository
2. Make your changes
3. Build the image: `docker build -t squeezebox-test .`
4. Test locally: `docker run -d --name test-container squeezebox-test`
5. Verify functionality

### Code Style

- Follow existing code formatting
- Use meaningful commit messages
- Update documentation for any new features
- Add appropriate error handling

## License

This project is open source and available under the [MIT License](LICENSE). 

The Lyrion Music Server is licensed under the GPL. See the [official Lyrion Music Server repository](https://github.com/LMS-Community/slimserver) for more details.

## References

- [Lyrion Music Server (Official)](https://lyrion.org/)
- [Lyrion Music Server GitHub](https://github.com/LMS-Community/slimserver)
- [Docker Hub - Official LMS Images](https://hub.docker.com/r/lmscommunity/lyrionmusicserver)
- [Snapcast Project](https://github.com/badaix/snapcast)
- [PulseAudio Documentation](https://www.freedesktop.org/wiki/Software/PulseAudio/)

## Support

- **Documentation**: [Lyrion Music Server Wiki](https://lyrion.org/reference/)
- **Community Forum**: [Lyrion Community Forums](https://forums.lyrion.org/)
- **Issues**: [GitHub Issues](https://github.com/niklasdoerfler/squeezebox-media-server-docker/issues)

---

**Maintainer**: Niklas Dörfler <niklas@doerfler-el.de>

For questions specific to this Docker implementation, please open an issue on GitHub.