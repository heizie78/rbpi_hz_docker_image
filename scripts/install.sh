#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/home/pi/rbpi-hz-docker-image"
LOG_DIR="${BASE_DIR}/logs"
LOG_FILE="${LOG_DIR}/install.log"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"
TOTAL_STEPS=12
STEP=0

# Progress indicator for console output.
step() {
  STEP=$((STEP + 1))
  echo "[${STEP}/${TOTAL_STEPS}] $*"
}

# Timestamped logging for console and log file.
log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

# Root privileges are required for system changes.
require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "This script must be run as root. Use: sudo ./scripts/install.sh"
    exit 1
  fi
}

# Print current container status and known port mappings.
show_services() {
  echo ""
  echo "Service status and ports:"
  for svc in n8n homeassistant pihole; do
    local id status ports
    id="$(docker compose -f "${COMPOSE_FILE}" ps -q "${svc}" 2>/dev/null || true)"
    if [[ -n "${id}" ]]; then
      status="$(docker inspect -f '{{.State.Status}}' "${id}" 2>/dev/null || true)"
    else
      status="not created"
    fi
    case "${svc}" in
      n8n) ports="5678/tcp" ;;
      homeassistant) ports="8123/tcp (host network)" ;;
      pihole) ports="53/tcp+udp, 8080/tcp" ;;
    esac
    printf "- %-14s %-12s %s\n" "${svc}" "${status}" "${ports}"
  done
  echo ""
}

# Basic HTTP health checks for the services.
health_checks() {
  echo ""
  echo "Health checks:"
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 3 http://localhost:5678 >/dev/null 2>&1 \
      && echo "- n8n            OK (http://localhost:5678)" \
      || echo "- n8n            NOT READY (http://localhost:5678)"
    curl -fsS --max-time 3 http://localhost:8123 >/dev/null 2>&1 \
      && echo "- homeassistant  OK (http://localhost:8123)" \
      || echo "- homeassistant  NOT READY (http://localhost:8123)"
    curl -fsS --max-time 3 http://localhost:8080/admin >/dev/null 2>&1 \
      && echo "- pihole         OK (http://localhost:8080/admin)" \
      || echo "- pihole         NOT READY (http://localhost:8080/admin)"
  else
    echo "- curl not available; skipping HTTP checks."
  fi
  echo ""
}

# Require root before writing to system paths.
require_root

# Prepare log folder early so all output is captured.
step "Preparing directories and logging"
mkdir -p "${LOG_DIR}"
touch "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

log "Install started"
log "Repo root: ${REPO_ROOT}"
log "Compose file: ${COMPOSE_FILE}"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  log "ERROR: docker-compose.yml not found in repo root."
  exit 1
fi

# Install packages required for Docker installation and locale handling.
step "Installing prerequisites (curl, ca-certificates, locales)"
apt-get update -y
apt-get install -y curl ca-certificates locales

# Set system timezone.
step "Setting timezone to Europe/Berlin"
timedatectl set-timezone Europe/Berlin

# Set system locale.
step "Setting locale to de_DE.UTF-8"
sed -i 's/^# *\(de_DE.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
update-locale LANG=de_DE.UTF-8

# Install Docker using the official convenience script.
step "Installing Docker via official script"
curl -fsSL https://get.docker.com | sh

# Enable Docker to start on boot and start it immediately.
step "Enabling Docker service on boot"
systemctl enable --now docker

# Install the Docker Compose plugin (docker compose).
step "Installing Docker Compose plugin"
apt-get install -y docker-compose-plugin

docker compose version

# Allow user 'pi' to use Docker without sudo.
step "Adding user 'pi' to docker group"
usermod -aG docker pi
log "User 'pi' added to docker group. A logout/login is required for group changes to take effect."

# Create persistent data directories and set ownership.
step "Creating data directories"
mkdir -p "${BASE_DIR}/data/n8n" \
  "${BASE_DIR}/data/homeassistant" \
  "${BASE_DIR}/data/pihole" \
  "${BASE_DIR}/data/dnsmasq"
chown -R pi:pi "${BASE_DIR}"

# Start the container stack using the repo's compose file.
step "Starting Docker Compose stack"
docker compose -f "${COMPOSE_FILE}" up -d

# Install and enable the reboot service and timer.
step "Installing reboot systemd service and timer"
install -m 0644 "${REPO_ROOT}/systemd/reboot.service" /etc/systemd/system/reboot.service
install -m 0644 "${REPO_ROOT}/systemd/reboot.timer" /etc/systemd/system/reboot.timer
systemctl daemon-reload
systemctl enable --now reboot.timer

# Show current service status and port mapping.
step "Reporting service status"
show_services
health_checks

log "Install completed"
