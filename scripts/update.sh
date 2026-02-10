#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/home/pi/rbpi-hz-docker-image"
LOG_DIR="${BASE_DIR}/logs"
LOG_FILE="${LOG_DIR}/update.log"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"
TIMER_FILE="/etc/systemd/system/reboot.timer"
TOTAL_STEPS=9
STEP=0
NON_INTERACTIVE=0
AUTO_YES=0
AUTO_NO=0

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
    echo "This script must be run as root. Use: sudo ./scripts/update.sh"
    exit 1
  fi
}

# Simple yes/no prompt for interactive mode.
ask_yes_no() {
  local prompt="$1"
  local reply
  read -r -p "${prompt} [y/N]: " reply
  case "${reply}" in
    y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

# Normalize weekday input to systemd abbreviations.
normalize_day() {
  local input="$1"
  case "${input,,}" in
    mon|monday) echo "Mon" ;;
    tue|tues|tuesday) echo "Tue" ;;
    wed|wednesday) echo "Wed" ;;
    thu|thur|thurs|thursday) echo "Thu" ;;
    fri|friday) echo "Fri" ;;
    sat|saturday) echo "Sat" ;;
    sun|sunday) echo "Sun" ;;
    *) echo "" ;;
  esac
}

# Validate 24h time in HH:MM format.
valid_time() {
  local t="$1"
  [[ "${t}" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]
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

for arg in "$@"; do
  case "${arg}" in
    --non-interactive) NON_INTERACTIVE=1 ;;
    --yes) NON_INTERACTIVE=1; AUTO_YES=1 ;;
    --no) NON_INTERACTIVE=1; AUTO_NO=1 ;;
    *)
      echo "Unknown argument: ${arg}"
      echo "Usage: sudo ./scripts/update.sh [--non-interactive|--yes|--no]"
      exit 1
      ;;
  esac
done

# Prepare log folder early so all output is captured.
step "Preparing directories and logging"
mkdir -p "${LOG_DIR}"
touch "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

log "Update started"
log "Repo root: ${REPO_ROOT}"
log "Compose file: ${COMPOSE_FILE}"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  log "ERROR: docker-compose.yml not found in repo root."
  exit 1
fi

# Ensure Docker and Docker Compose are available.
step "Checking Docker availability"
command -v docker >/dev/null 2>&1 || { log "ERROR: docker not found."; exit 1; }
docker compose version >/dev/null 2>&1 || { log "ERROR: docker compose plugin not found."; exit 1; }

# Docker engine updates are checked in interactive mode or --yes mode.
step "Checking Docker engine updates (interactive/--yes)"
if [[ "${NON_INTERACTIVE}" -eq 0 || "${AUTO_YES}" -eq 1 ]]; then
  apt-get update -y
  if dpkg -s docker-ce >/dev/null 2>&1; then
    installed="$(dpkg-query -W -f='${Version}' docker-ce)"
    candidate="$(apt-cache policy docker-ce | awk '/Candidate:/ {print $2}')"
    if [[ -n "${candidate}" && "${candidate}" != "(none)" && "${candidate}" != "${installed}" ]]; then
      log "Docker update available: ${installed} -> ${candidate}"
      if [[ "${AUTO_YES}" -eq 1 ]] || ask_yes_no "Update Docker engine now?"; then
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      else
        log "Docker engine update skipped by user."
      fi
    else
      log "Docker engine is up to date (${installed})."
    fi
  else
    log "Docker CE package not found; skipping engine update check."
  fi
else
  log "Non-interactive mode: skipping Docker engine update check."
fi

# Update n8n image and restart service if selected.
step "Updating n8n (if selected)"
if [[ "${AUTO_NO}" -eq 1 ]]; then
  log "n8n update skipped (auto-no)."
elif [[ "${NON_INTERACTIVE}" -eq 1 ]] || ask_yes_no "Check and update n8n image?"; then
  docker compose -f "${COMPOSE_FILE}" pull n8n
  docker compose -f "${COMPOSE_FILE}" up -d n8n
else
  log "n8n update skipped."
fi

# Update Home Assistant image and restart service if selected.
step "Updating Home Assistant (if selected)"
if [[ "${AUTO_NO}" -eq 1 ]]; then
  log "Home Assistant update skipped (auto-no)."
elif [[ "${NON_INTERACTIVE}" -eq 1 ]] || ask_yes_no "Check and update Home Assistant image?"; then
  docker compose -f "${COMPOSE_FILE}" pull homeassistant
  docker compose -f "${COMPOSE_FILE}" up -d homeassistant
else
  log "Home Assistant update skipped."
fi

# Update Pi-hole image and restart service if selected.
step "Updating Pi-hole (if selected)"
if [[ "${AUTO_NO}" -eq 1 ]]; then
  log "Pi-hole update skipped (auto-no)."
elif [[ "${NON_INTERACTIVE}" -eq 1 ]] || ask_yes_no "Check and update Pi-hole image?"; then
  docker compose -f "${COMPOSE_FILE}" pull pihole
  docker compose -f "${COMPOSE_FILE}" up -d pihole
else
  log "Pi-hole update skipped."
fi

# Show current reboot schedule and optionally update it (interactive).
step "Showing reboot timer configuration"
current_calendar=""
if [[ -f "${TIMER_FILE}" ]]; then
  current_calendar="$(grep -E '^OnCalendar=' "${TIMER_FILE}" | head -n1 | cut -d= -f2-)"
else
  current_calendar="$(systemctl cat reboot.timer 2>/dev/null | grep -E '^OnCalendar=' | head -n1 | cut -d= -f2-)"
fi
log "Current reboot timer OnCalendar: ${current_calendar:-unknown}"

if [[ "${NON_INTERACTIVE}" -eq 0 ]]; then
  if ask_yes_no "Do you want to change the reboot schedule?"; then
    echo "Choose schedule type:"
    echo "1) Weekly"
    echo "2) Monthly"
    read -r -p "Select [1/2]: " schedule_choice

    if [[ "${schedule_choice}" == "1" ]]; then
      echo "Choose weekday: Mon Tue Wed Thu Fri Sat Sun"
      read -r -p "Weekday: " weekday_input
      weekday="$(normalize_day "${weekday_input}")"
      if [[ -z "${weekday}" ]]; then
        log "Invalid weekday. Aborting timer update."
      else
        read -r -p "Time (HH:MM, 24h): " time_input
        if valid_time "${time_input}"; then
          new_calendar="${weekday} *-*-* ${time_input}:00"
        else
          log "Invalid time format. Aborting timer update."
        fi
      fi
    elif [[ "${schedule_choice}" == "2" ]]; then
      read -r -p "Day of month (1-31): " dom_input
      if [[ "${dom_input}" =~ ^[0-9]+$ ]] && ((dom_input >= 1 && dom_input <= 31)); then
        read -r -p "Time (HH:MM, 24h): " time_input
        if valid_time "${time_input}"; then
          new_calendar="*-*-${dom_input} ${time_input}:00"
        else
          log "Invalid time format. Aborting timer update."
        fi
      else
        log "Invalid day of month. Aborting timer update."
      fi
    else
      log "Invalid schedule choice. Aborting timer update."
    fi

    if [[ -n "${new_calendar:-}" ]]; then
      if [[ ! -f "${TIMER_FILE}" ]]; then
        install -m 0644 "${REPO_ROOT}/systemd/reboot.timer" "${TIMER_FILE}"
      fi
      sed -i "s|^OnCalendar=.*|OnCalendar=${new_calendar}|" "${TIMER_FILE}"
      systemctl daemon-reload
      systemctl restart reboot.timer
      log "Reboot timer updated to: ${new_calendar}"
    fi
  else
    log "Reboot timer unchanged."
  fi
else
  log "Non-interactive mode: reboot timer unchanged."
fi

# Show current service status and port mapping.
step "Reporting service status"
show_services
health_checks

log "Update completed"
