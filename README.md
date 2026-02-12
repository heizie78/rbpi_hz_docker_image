# rbpi_hz_docker_image

Provision a fresh Raspberry Pi OS installation with a Docker-based stack:
- n8n
- Home Assistant
- Pi-hole

The scripts can also apply optional system settings (network, hostname, timezone, locale) and install a scheduled reboot timer.

## Requirements
- Raspberry Pi OS (latest recommended)
- User `pi`
- Internet access during installation/update
- `sudo` access

## Get this project on the Pi
Clone with `git`:

```bash
cd /home/pi
git clone https://github.com/heizie78/rbpi_hz_docker_image.git
cd rbpi_hz_docker_image
```

## What gets installed/changed

### Software/packages
- Docker Engine (official convenience script)
- Docker Compose plugin
- `curl`, `ca-certificates`, `locales`

### Containers and ports
- n8n: `5678/tcp`
- Home Assistant: `8123/tcp` (host network mode)
- Pi-hole: `53/tcp+udp`, web UI: `8080/tcp`

### Persistent data and logs
- Data:
  - `/home/pi/rbpi-hz-docker-image/data/n8n`
  - `/home/pi/rbpi-hz-docker-image/data/homeassistant`
  - `/home/pi/rbpi-hz-docker-image/data/pihole`
  - `/home/pi/rbpi-hz-docker-image/data/dnsmasq`
- Logs:
  - `/home/pi/rbpi-hz-docker-image/logs/install.log`
  - `/home/pi/rbpi-hz-docker-image/logs/update.log`

### System files/services that may be modified
- `/etc/systemd/system/reboot.service`
- `/etc/systemd/system/reboot.timer` (default: Sunday `03:00`)
- `/etc/hosts` (if hostname is changed)
- `/etc/dhcpcd.conf` or NetworkManager connection profile (if static IP is configured)
- timezone/locale settings

## Install
Run from the repository root:

```bash
sudo ./scripts/install.sh
```

`install.sh` workflow:
1. Installs prerequisites: `curl`, `ca-certificates`, `locales`
2. Runs interactive system configuration:
   - Optional static IPv4 for `eth0` and/or `wlan0`
   - Optional hostname change
   - Optional timezone change (default prompt: `Europe/Berlin`)
   - Optional locale change (default prompt: `de_DE.UTF-8`)
3. Installs Docker Engine via official `https://get.docker.com`
4. Enables and starts Docker service
5. Installs Docker Compose plugin (`docker compose`)
6. Adds user `pi` to `docker` group
7. Creates data directories under `/home/pi/rbpi-hz-docker-image/data`
8. Starts the stack from `docker-compose.yml`
9. Installs and enables reboot timer (`reboot.service`, `reboot.timer`)
10. Prints service status and basic HTTP health checks

## Update
Interactive mode:
```bash
sudo ./scripts/update.sh
```

Non-interactive mode (updates images, keeps system settings and reboot timer unchanged):
```bash
sudo ./scripts/update.sh --non-interactive
```

Auto-yes mode (non-interactive + Docker engine update if available):
```bash
sudo ./scripts/update.sh --yes
```

Auto-no mode (skips all image updates):
```bash
sudo ./scripts/update.sh --no
```

`update.sh` workflow:
1. Verifies Docker and Compose availability
2. Interactive mode only: optional system configuration:
   - Optional static IPv4 for `eth0` and/or `wlan0`
   - Optional hostname change
   - Optional timezone change
   - Optional locale change
3. Interactive mode or `--yes`: checks and optionally updates Docker Engine packages
4. Updates selected images/services (`n8n`, `homeassistant`, `pihole`)
5. Interactive mode only: can change reboot timer schedule (`OnCalendar=...`)
6. Prints service status and basic HTTP health checks

In non-interactive modes (`--non-interactive`, `--yes`, `--no`), static IP, hostname, timezone, and locale remain unchanged.

## Reboot schedule
The timer is managed via systemd:
- Service: `reboot.service`
- Timer: `reboot.timer`

Default:
- `OnCalendar=Sun *-*-* 03:00:00`

It can be changed interactively in `scripts/update.sh`.

## Notes
- After installation, user `pi` is added to the `docker` group. Logout/login is required to apply group membership.
- Pi-hole default web password in `docker-compose.yml` is `WEBPASSWORD=changeme`. Change it before production use.
- The scripts use local repository files (`docker-compose.yml`, `systemd/*`), so this directory must exist on the Pi when they are executed.

## Troubleshooting
- Check logs:
  - `/home/pi/rbpi-hz-docker-image/logs/install.log`
  - `/home/pi/rbpi-hz-docker-image/logs/update.log`
- Check container status:
  ```bash
  docker compose ps
  ```
- Both scripts print basic HTTP health checks for all services.
