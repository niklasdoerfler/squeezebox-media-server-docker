# Squeezebox Media Server Docker

![Docker Image Size](https://img.shields.io/docker/image-size/niklasdoerfler/squeezebox-media-server)
![GitHub repo stars](https://img.shields.io/github/stars/niklasdoerfler/squeezebox-media-server-docker)
![License](https://img.shields.io/github/license/niklasdoerfler/squeezebox-media-server-docker)

This project sets up the [Squeezebox Media Server](https://mysqueezebox.com/) (also known as Logitech Media Server) inside a Docker container for easy deployment and management.

---

## Features

- **Runs Logitech Squeezebox Media Server** in an isolated Docker container
- Clean, minimal, and production-ready setup
- Volume mapping for persistent configuration and music storage
- Easily configurable via environment variables
- Regular updates

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Configuration](#configuration)
- [Volumes](#volumes)
- [Environment Variables](#environment-variables)
- [Updating](#updating)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Requirements

- [Docker](https://docs.docker.com/get-docker/) (version 20.10+ recommended)
- (Optional) [Docker Compose](https://docs.docker.com/compose/)

---

## Getting Started

You can quickly get the Squeezebox Media Server running on your system with Docker:

```bash
docker pull niklasdoerfler/squeezebox-media-server
```

### Run with Docker

```bash
docker run -d \
  --name squeezebox \
  -p 9000:9000 \
  -p 3483:3483 \
  -p 3483:3483/udp \
  -v /path/to/config:/config \
  -v /path/to/music:/music \
  niklasdoerfler/squeezebox-media-server
```

### Run with Docker Compose

```yaml
version: "3"
services:
  squeezebox:
    image: niklasdoerfler/squeezebox-media-server
    container_name: squeezebox
    ports:
      - "9000:9000"
      - "3483:3483"
      - "3483:3483/udp"
    volumes:
      - /path/to/config:/config
      - /path/to/music:/music
    restart: unless-stopped
```

---

## Usage

- Access the Squeezebox web UI at: [http://localhost:9000](http://localhost:9000)
- Point your Squeezebox clients/players at your Docker host.

---

## Configuration

### Volumes

- `/config`  
  Stores Squeezebox Media Server configuration and cache. **Persistent data!**
- `/music`  
  Your music files.

### Ports

- `9000/tcp` – Web interface  
- `3483/tcp` and `3483/udp` – Squeezebox discovery and player connections

### Environment Variables

You can set the following environment variables (all optional):

| Variable         | Default  | Description                     |
|------------------|----------|---------------------------------|
| TZ               | UTC      | Timezone for the container      |
| PUID             | 1000     | User ID for container processes |
| PGID             | 1000     | Group ID for container processes|

Example:

```bash
-e TZ=Europe/Berlin \
-e PUID=1000 \
-e PGID=1000
```

---

## Updating

To update the container:

```bash
docker pull niklasdoerfler/squeezebox-media-server
docker stop squeezebox
docker rm squeezebox
# Re-run with the same options as above
```

---

## Troubleshooting

- **Log files** can be accessed via Docker logs:
  ```bash
  docker logs squeezebox
  ```
- Make sure your volume paths exist and are writable by the container.
- If your music is not visible, check permissions on your mapped `/music` directory.

---

## Contributing

Contributions, issues, and feature requests are welcome!

1. Fork this repository
2. Create your branch (`git checkout -b feature/thing`)
3. Commit your changes (`git commit -am 'Add new thing'`)
4. Push to the branch (`git push origin feature/thing`)
5. Open a Pull Request

---

## License

This project is [MIT licensed](./LICENSE).

---

## References

- [Logitech Media Server Wiki](https://wiki.slimdevices.com/)
- [Official Docker Documentation](https://docs.docker.com/)

---