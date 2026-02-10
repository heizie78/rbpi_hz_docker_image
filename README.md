# rbpi_hz_docker_image

Turn a fresh Raspberry Pi OS install into a Docker-based stack with:
- n8n
- Home Assistant
- Pi-hole

It also configures timezone/locale and installs a scheduled reboot timer.

## Requirements
- Raspberry Pi OS (latest recommended)
- User `pi`
- Internet access during installation

## What gets installed
- Docker Engine (official `get.docker.com` script)
- Docker Compose plugin (`docker compose`)
- systemd reboot timer (default: Sunday 03:00)

## Ports
- n8n: `5678/tcp`
- Home Assistant: `8123/tcp` (host network)
- Pi-hole: `53/tcp+udp`, Web UI `8080/tcp`

## Data directories
All persistent data lives under:
- `/home/pi/rbpi-hz-docker-image/data/`
  - `n8n/`
  - `homeassistant/`
  - `pihole/`
  - `dnsmasq/`

Logs are written to:
- `/home/pi/rbpi-hz-docker-image/logs/`

## Install
Run as root:
```bash
sudo ./scripts/install.sh
```

## Update
Interactive mode:
```bash
sudo ./scripts/update.sh
```

Non-interactive mode (auto-updates images, keeps reboot timer unchanged):
```bash
sudo ./scripts/update.sh --non-interactive
```

Auto-yes mode (updates Docker engine if available, auto-updates images, keeps reboot timer unchanged):
```bash
sudo ./scripts/update.sh --yes
```

Auto-no mode (skips all updates, keeps reboot timer unchanged):
```bash
sudo ./scripts/update.sh --no
```

## Reboot schedule
The reboot timer is a systemd timer:
- Service: `reboot.service`
- Timer: `reboot.timer`

The update script can change the schedule interactively.

## Notes
- After installation, user `pi` is added to the `docker` group. A logout/login is required for this to take effect.
- Pi-hole default web password is set in `docker-compose.yml` as `WEBPASSWORD=changeme`. Change it before use.

## Troubleshooting
- Check install/update logs in `/home/pi/rbpi-hz-docker-image/logs/`
- Check container status:
  ```bash
  docker compose ps
  ```
- Both scripts print a basic HTTP health check for all services.
