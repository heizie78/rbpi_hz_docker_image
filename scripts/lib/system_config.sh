#!/usr/bin/env bash

# Shared interactive system configuration helpers for install/update scripts.

log_info() {
  if declare -F log >/dev/null 2>&1; then
    log "$*"
  else
    echo "$*"
  fi
}

ask_yes_no_default() {
  local prompt="$1"
  local default_answer="${2:-N}"
  local suffix
  local reply

  if [[ "${default_answer}" == "Y" ]]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi

  while true; do
    read -r -p "${prompt} ${suffix}: " reply
    reply="${reply,,}"
    if [[ -z "${reply}" ]]; then
      [[ "${default_answer}" == "Y" ]] && return 0 || return 1
    fi
    case "${reply}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "Please answer with y or n." ;;
    esac
  done
}

prompt_with_default() {
  local prompt="$1"
  local default_value="$2"
  local input
  read -r -p "${prompt} [${default_value}]: " input
  if [[ -z "${input}" ]]; then
    echo "${default_value}"
  else
    echo "${input}"
  fi
}

valid_ipv4() {
  local ip="$1"
  local octet
  if [[ ! "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    return 1
  fi
  IFS='.' read -r -a octets <<< "${ip}"
  for octet in "${octets[@]}"; do
    if ((octet < 0 || octet > 255)); then
      return 1
    fi
  done
  return 0
}

valid_hostname() {
  local hostname="$1"
  [[ "${hostname}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,62}[a-zA-Z0-9])?$ ]]
}

interface_exists() {
  local iface="$1"
  ip link show dev "${iface}" >/dev/null 2>&1
}

get_interface_ipv4() {
  local iface="$1"
  ip -4 -o addr show dev "${iface}" scope global 2>/dev/null | awk '{print $4}' | head -n1 | cut -d/ -f1
}

get_interface_prefix() {
  local iface="$1"
  ip -4 -o addr show dev "${iface}" scope global 2>/dev/null | awk '{print $4}' | head -n1 | cut -d/ -f2
}

get_interface_gateway() {
  local iface="$1"
  ip route show default dev "${iface}" 2>/dev/null | awk '{print $3}' | head -n1
}

get_resolver_dns_csv() {
  awk '/^nameserver / {print $2}' /etc/resolv.conf 2>/dev/null | paste -sd, -
}

get_current_hostname() {
  hostnamectl --static 2>/dev/null || hostname
}

get_current_timezone() {
  timedatectl show -p Timezone --value 2>/dev/null || true
}

get_current_locale() {
  local locale_value
  locale_value="$(localectl status 2>/dev/null | awk -F= '/System Locale:/ {print $2}' | awk '{print $1}' | sed 's/^LANG=//')"
  if [[ -z "${locale_value}" ]]; then
    locale_value="$(locale | awk -F= '/^LANG=/{print $2}' | head -n1)"
  fi
  echo "${locale_value}"
}

apply_hostname() {
  local target_hostname="$1"
  local current_hostname
  current_hostname="$(get_current_hostname)"

  if [[ "${target_hostname}" == "${current_hostname}" ]]; then
    log_info "Hostname already set to ${current_hostname}; skipping."
    return 0
  fi

  hostnamectl set-hostname "${target_hostname}"
  if grep -qE '^127\.0\.1\.1[[:space:]]+' /etc/hosts; then
    sed -i "s/^127\\.0\\.1\\.1[[:space:]].*/127.0.1.1\t${target_hostname}/" /etc/hosts
  else
    echo -e "127.0.1.1\t${target_hostname}" >> /etc/hosts
  fi
  log_info "Hostname updated: ${current_hostname} -> ${target_hostname}"
}

apply_timezone() {
  local target_timezone="$1"
  local current_timezone
  current_timezone="$(get_current_timezone)"

  if [[ "${target_timezone}" == "${current_timezone}" ]]; then
    log_info "Timezone already set to ${current_timezone}; skipping."
    return 0
  fi

  timedatectl set-timezone "${target_timezone}"
  log_info "Timezone updated: ${current_timezone:-unknown} -> ${target_timezone}"
}

apply_locale() {
  local target_locale="$1"
  local current_locale
  current_locale="$(get_current_locale)"

  if [[ "${target_locale}" == "${current_locale}" ]]; then
    log_info "Locale already set to ${current_locale}; skipping."
    return 0
  fi

  if grep -qE "^# *${target_locale} UTF-8" /etc/locale.gen; then
    sed -i "s/^# *\\(${target_locale} UTF-8\\)/\\1/" /etc/locale.gen
  elif ! grep -qE "^${target_locale} UTF-8" /etc/locale.gen; then
    echo "${target_locale} UTF-8" >> /etc/locale.gen
  fi

  locale-gen "${target_locale}"
  update-locale LANG="${target_locale}"
  log_info "Locale updated: ${current_locale:-unknown} -> ${target_locale}"
}

apply_static_ip_dhcpcd() {
  local iface="$1"
  local target_ip="$2"
  local dhcpcd_file="/etc/dhcpcd.conf"
  local prefix
  local gateway
  local dns_servers
  local block_start="# BEGIN RBPI_HZ_STATIC_${iface}"
  local block_end="# END RBPI_HZ_STATIC_${iface}"
  local timestamp
  local existing_block
  local desired_block

  if [[ ! -f "${dhcpcd_file}" ]]; then
    log_info "dhcpcd config (${dhcpcd_file}) not found; static IP for ${iface} skipped."
    return 0
  fi

  prefix="$(get_interface_prefix "${iface}")"
  gateway="$(get_interface_gateway "${iface}")"
  dns_servers="$(get_resolver_dns_csv)"
  [[ -z "${prefix}" ]] && prefix="24"

  desired_block="${block_start}
interface ${iface}
static ip_address=${target_ip}/${prefix}"
  if [[ -n "${gateway}" ]]; then
    desired_block="${desired_block}
static routers=${gateway}"
  fi
  if [[ -n "${dns_servers}" ]]; then
    desired_block="${desired_block}
static domain_name_servers=${dns_servers}"
  fi
  desired_block="${desired_block}
${block_end}"

  existing_block="$(sed -n "/^${block_start}$/,/^${block_end}$/p" "${dhcpcd_file}")"
  if [[ "${existing_block}" == "${desired_block}" ]]; then
    log_info "Static IP for ${iface} already configured in dhcpcd; skipping."
    return 0
  fi

  timestamp="$(date +%Y%m%d%H%M%S)"
  cp -a "${dhcpcd_file}" "${dhcpcd_file}.bak.${timestamp}"

  sed -i "/^${block_start}$/,/^${block_end}$/d" "${dhcpcd_file}"
  printf "\n%s\n" "${desired_block}" >> "${dhcpcd_file}"

  if systemctl list-unit-files dhcpcd.service >/dev/null 2>&1; then
    if ! systemctl restart dhcpcd; then
      log_info "Could not restart dhcpcd automatically. Reboot may be required."
    fi
  else
    log_info "dhcpcd service not available. Reboot may be required."
  fi

  log_info "Static IP for ${iface} configured in dhcpcd: ${target_ip}/${prefix}"
}

apply_static_ip_nmcli() {
  local iface="$1"
  local target_ip="$2"
  local connection_name
  local prefix
  local gateway
  local dns_servers
  local current_addresses

  connection_name="$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v d="${iface}" '$2==d {print $1; exit}')"
  if [[ -z "${connection_name}" ]]; then
    return 1
  fi

  prefix="$(get_interface_prefix "${iface}")"
  gateway="$(get_interface_gateway "${iface}")"
  dns_servers="$(nmcli -g IP4.DNS device show "${iface}" 2>/dev/null | paste -sd, -)"
  [[ -z "${dns_servers}" ]] && dns_servers="$(get_resolver_dns_csv)"
  [[ -z "${prefix}" ]] && prefix="24"

  current_addresses="$(nmcli -g ipv4.addresses connection show "${connection_name}" 2>/dev/null || true)"
  if grep -q "${target_ip}/${prefix}" <<< "${current_addresses}"; then
    log_info "Static IP for ${iface} already configured in NetworkManager; skipping."
    return 0
  fi

  nmcli connection modify "${connection_name}" ipv4.method manual ipv4.addresses "${target_ip}/${prefix}"
  if [[ -n "${gateway}" ]]; then
    nmcli connection modify "${connection_name}" ipv4.gateway "${gateway}"
  fi
  if [[ -n "${dns_servers}" ]]; then
    nmcli connection modify "${connection_name}" ipv4.dns "${dns_servers}"
  fi
  nmcli connection up "${connection_name}" >/dev/null

  log_info "Static IP for ${iface} configured in NetworkManager: ${target_ip}/${prefix}"
  return 0
}

apply_static_ip() {
  local iface="$1"
  local target_ip="$2"
  local current_ip

  if ! interface_exists "${iface}"; then
    log_info "Interface ${iface} not found; skipping static IP configuration."
    return 0
  fi

  current_ip="$(get_interface_ipv4 "${iface}")"
  if [[ -n "${current_ip}" && "${current_ip}" == "${target_ip}" ]]; then
    log_info "Interface ${iface} already uses ${target_ip}; skipping."
    return 0
  fi

  if command -v nmcli >/dev/null 2>&1; then
    if apply_static_ip_nmcli "${iface}" "${target_ip}"; then
      return 0
    fi
  fi

  apply_static_ip_dhcpcd "${iface}" "${target_ip}"
}

prompt_for_static_ip() {
  local iface="$1"
  local current_ip
  local target_ip

  if ! interface_exists "${iface}"; then
    log_info "Interface ${iface} not present; skipping question."
    return 0
  fi

  current_ip="$(get_interface_ipv4 "${iface}")"
  if ask_yes_no_default "Configure static IPv4 for ${iface}?" "N"; then
    if [[ -n "${current_ip}" ]]; then
      while true; do
        target_ip="$(prompt_with_default "Static IPv4 for ${iface}" "${current_ip}")"
        if valid_ipv4 "${target_ip}"; then
          break
        fi
        echo "Invalid IPv4 format. Example: 192.168.1.20"
      done
    else
      while true; do
        read -r -p "Static IPv4 for ${iface} (no current default available): " target_ip
        if valid_ipv4 "${target_ip}"; then
          break
        fi
        echo "Invalid IPv4 format. Example: 192.168.1.20"
      done
    fi

    if ask_yes_no_default "Apply ${target_ip} to ${iface}? This can interrupt network access." "N"; then
      apply_static_ip "${iface}" "${target_ip}"
    else
      log_info "Static IP change for ${iface} canceled by user."
    fi
  else
    log_info "Static IP configuration for ${iface} skipped."
  fi
}

run_interactive_system_configuration() {
  local hostname_default
  local timezone_target
  local locale_target
  local hostname_target

  prompt_for_static_ip "eth0"
  prompt_for_static_ip "wlan0"

  hostname_default="$(get_current_hostname)"
  if ask_yes_no_default "Change hostname?" "N"; then
    while true; do
      hostname_target="$(prompt_with_default "Hostname" "${hostname_default}")"
      if valid_hostname "${hostname_target}"; then
        break
      fi
      echo "Invalid hostname. Use letters, numbers and hyphen only."
    done
    apply_hostname "${hostname_target}"
  else
    log_info "Hostname unchanged."
  fi

  if ask_yes_no_default "Change timezone and locale?" "Y"; then
    timezone_target="$(prompt_with_default "Timezone" "Europe/Berlin")"
    locale_target="$(prompt_with_default "Locale" "de_DE.UTF-8")"
    apply_timezone "${timezone_target}"
    apply_locale "${locale_target}"
  else
    log_info "Timezone/locale unchanged."
  fi
}
