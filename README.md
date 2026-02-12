# rbpi_hz_docker_image

Turn a fresh Raspberry Pi OS install into a Docker-based stack with:
- n8n
- Home Assistant
- Pi-hole

It also configures optional system settings (network, hostname, timezone, locale) and installs a scheduled reboot timer.

## Requirements
- Raspberry Pi OS (latest recommended)
- User `pi`
- Internet access during installation/update
- `sudo` access

## Recommended way to get this project on the Pi
Use `git` (recommended), because updates are simple and transparent (`git pull`).

```bash
cd /home/pi
git clone https://github.com/heizie78/rbpi_hz_docker_image.git
cd rbpi_hz_docker_image
```

### Why `git` is better than `curl` here
- Easy updates later (`git pull`)
- Full change history and rollback options
- Fits the update workflow of this project

### `curl` fallback (only if you do not want `git`)
This works, but future updates are more manual.

```bash
cd /home/pi
curl -L https://github.com/heizie78/rbpi_hz_docker_image/archive/refs/heads/main.tar.gz -o rbpi_hz_docker_image.tar.gz
tar -xzf rbpi_hz_docker_image.tar.gz
cd rbpi_hz_docker_image-main
```

## What the scripts do (in detail)

### `scripts/install.sh`
Runs a full initial setup:
1. Installs prerequisites: `curl`, `ca-certificates`, `locales`
2. Runs interactive system configuration from `scripts/lib/system_config.sh`
3. Installs Docker Engine via official `https://get.docker.com`
4. Enables/starts Docker service
5. Installs Docker Compose plugin (`docker compose`)
6. Adds user `pi` to `docker` group
7. Creates persistent data directories under `/home/pi/rbpi-hz-docker-image/data`
8. Starts stack from local `docker-compose.yml`
9. Installs and enables reboot timer (`systemd/reboot.service`, `systemd/reboot.timer`)
10. Prints service status + HTTP health checks

### `scripts/update.sh`
Runs maintenance and image updates:
1. Verifies Docker/Compose availability
2. Interactive mode: optionally runs the same system configuration helper
3. Interactive or `--yes`: checks/updates Docker Engine packages if available
4. Updates selected container images (`n8n`, `homeassistant`, `pihole`)
5. Interactive mode: can change reboot schedule (`OnCalendar=...`)
6. Prints service status + HTTP health checks

Modes:
- Interactive:
  ```bash
  sudo ./scripts/update.sh
  ```
- Non-interactive (update images, keep system settings and reboot timer unchanged):
  ```bash
  sudo ./scripts/update.sh --non-interactive
  ```
- Auto-yes (non-interactive + Docker engine update if available):
  ```bash
  sudo ./scripts/update.sh --yes
  ```
- Auto-no (skip all image updates):
  ```bash
  sudo ./scripts/update.sh --no
  ```

### `scripts/lib/system_config.sh`
Shared interactive helpers for install/update:
- Optional static IPv4 for `eth0` and/or `wlan0`
  - Uses NetworkManager (`nmcli`) if available
  - Falls back to `/etc/dhcpcd.conf` block update otherwise
- Optional hostname change (`hostnamectl` + `/etc/hosts`)
- Optional timezone change (`timedatectl`)
- Optional locale change (`locale-gen`, `update-locale`)

Defaults in prompts:
- Timezone: `Europe/Berlin`
- Locale: `de_DE.UTF-8`

## What gets installed/changed

### Software/packages
- Docker Engine (official convenience script)
- Docker Compose plugin
- `curl`, `ca-certificates`, `locales`

### Containers and ports
- n8n: `5678/tcp`
- Home Assistant: `8123/tcp` (host network mode)
- Pi-hole: `53/tcp+udp`, web UI on `8080/tcp`

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
- Timezone/locale settings

## Install
Run as root from inside this repo:

```bash
sudo ./scripts/install.sh
```

## Best practice: scripts via Git, data via backup sync
Use `git` for project files and `rsync`/`scp` for runtime data.

Example backup to another Linux host:
```bash
rsync -aH --delete /home/pi/rbpi-hz-docker-image/data/ user@backup-host:/backups/rbpi-hz/data/
rsync -aH --delete /home/pi/rbpi-hz-docker-image/logs/ user@backup-host:/backups/rbpi-hz/logs/
```

Example restore:
```bash
rsync -aH /backups/rbpi-hz/data/ /home/pi/rbpi-hz-docker-image/data/
rsync -aH /backups/rbpi-hz/logs/ /home/pi/rbpi-hz-docker-image/logs/
```

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
- The scripts use local repo files (`docker-compose.yml`, `systemd/*`), so this repo directory must exist on the Pi when you run them.

## Troubleshooting
- Check logs:
  - `/home/pi/rbpi-hz-docker-image/logs/install.log`
  - `/home/pi/rbpi-hz-docker-image/logs/update.log`
- Check container status:
  ```bash
  docker compose ps
  ```
- Both scripts print basic HTTP health checks for all services.
