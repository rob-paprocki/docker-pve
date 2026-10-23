#!/usr/bin/env bash
#
# docker-stack-vm.sh — provision a Debian 13 VM on Proxmox VE pre-loaded with
# Docker + Dockge + Portainer + Watchtower.
#
# Adapted from the community-scripts/ProxmoxVE helper-script pattern
# (https://github.com/community-scripts/ProxmoxVE) — the whiptail UI,
# get_valid_nextid helper, and api.func sourcing come from that project.
#
# Copyright (c) 2021-2025 community-scripts ORG
# Copyright (c) 2025 Rob Paprocki
# Co-Author: Google Gemini
# License: MIT (see LICENSE)
#
# WARNING: this script sources community-scripts/ProxmoxVE main-branch bash
# at runtime (api.func, for anonymous telemetry). The README documents the
# trust model; set DIAGNOSTICS=no in the environment to disable the uploads.

# Pinned to a specific commit so a compromise or breaking change on main
# cannot land here silently. Verified to carry post_to_api_vm and
# post_update_to_api (the only two functions this script calls). Bump
# deliberately after reviewing the diff on community-scripts/ProxmoxVE.
API_FUNC_REF="${API_FUNC_REF:-500a860faf7295e6dad20670d05e6400d18f66b0}"
API_FUNC_SRC=$(curl -fsSL "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/${API_FUNC_REF}/misc/api.func") \
  || { echo "ERROR: could not fetch community-scripts/ProxmoxVE api.func at ${API_FUNC_REF}" >&2; exit 1; }
[ -n "$API_FUNC_SRC" ] || { echo "ERROR: api.func fetch returned empty payload" >&2; exit 1; }
source /dev/stdin <<< "$API_FUNC_SRC"
unset API_FUNC_SRC

function header_info() {
  clear
  cat <<"EOF"

 /$$$$$$$                                 /$$                           /$$   /$$ /$$      /$$
| $$__  $$                               | $$                          | $$  | $$| $$$    /$$$
| $$  \ $$  /$$$$$$   /$$$$$$$| $$   /$$  /$$$$$$   /$$$$$$         | $$  | $$| $$$$  /$$$$
| $$  | $$ /$$__  $$ /$$_____/| $$  /$$/ /$$__  $$ /$$__  $$        |  $$ / $$/| $$ $$/$$ $$
| $$  | $$| $$  \ $$| $$      | $$$$$$/ | $$$$$$$$| $$  \__/         \  $$ $$/ | $$  $$$| $$
| $$  | $$| $$  | $$| $$      | $$_  $$ | $$_____/| $$                \  $$$/  | $$\  $ | $$
| $$$$$$$/|  $$$$$$/|  $$$$$$$| $$ \  $$|  $$$$$$$| $$                 \  $/   | $$ \/  | $$
|_______/  \______/  \_______/|__/  \__/ \_______/|__/                  \_/    |__/     |__/

EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
MAC="$GEN_MAC"
VLAN=""
MTU=""
CPU_TYPE=""
METHOD=""
NSAPP="docker-vm"
var_os="debian"
var_version="13"
DISK_SIZE="25G"
SCRIPT_VERSION="2025.10"

# Container image tags, bumpable in one place.
DOCKGE_TAG="${DOCKGE_TAG:-1.5.0}"
PORTAINER_CE_TAG="${PORTAINER_CE_TAG:-2.45.3}"
PORTAINER_AGENT_TAG="${PORTAINER_AGENT_TAG:-2.45.3}"
# containrrr/watchtower was archived December 2025; nicholas-fedor is the
# active community fork, drop-in compatible on env/labels.
WATCHTOWER_IMAGE="${WATCHTOWER_IMAGE:-ghcr.io/nicholas-fedor/watchtower}"
WATCHTOWER_TAG="${WATCHTOWER_TAG:-v1.23.2}"
# docker-socket-proxy fronts the monitor-only Portainer-scope watchtower
# below so that a compromise there cannot reach the raw Docker socket.
# POST is left off; CONTAINERS/IMAGES are on for read. Residual risk:
# CVE-2026-78122 (GET /containers/{id}/archive|export|logs|top leak when
# CONTAINERS=1) — still strictly better than a raw socket; fix tracked at
# Tecnativa/docker-socket-proxy PR #183.
SOCKET_PROXY_IMAGE="${SOCKET_PROXY_IMAGE:-ghcr.io/tecnativa/docker-socket-proxy}"
SOCKET_PROXY_TAG="${SOCKET_PROXY_TAG:-0.5.0}"

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")
BFR="\\r\\033[K"
HOLD=" "
TAB="  "

CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"
OS="${TAB}🖥️${TAB}${CL}"
CONTAINERTYPE="${TAB}📦${TAB}${CL}"
DISKSIZE="${TAB}💾${TAB}${CL}"
CPUCORE="${TAB}🧠${TAB}${CL}"
RAMSIZE="${TAB}🛠️${TAB}${CL}"
CONTAINERID="${TAB}🆔${TAB}${CL}"
HOSTNAME="${TAB}🏠${TAB}${CL}"
BRIDGE="${TAB}🌉${TAB}${CL}"
GATEWAY="${TAB}🌐${TAB}${CL}"
DEFAULT="${TAB}⚙️${TAB}${CL}"
MACADDRESS="${TAB}🔗${TAB}${CL}"
VLANTAG="${TAB}🏷️${TAB}${CL}"
CREATING="${TAB}🚀${TAB}${CL}"
ADVANCED="${TAB}🧩${TAB}${CL}"
CLOUD="${TAB}☁️${TAB}${CL}"

THIN="discard=on,ssd=1,"
set -Eeuo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"; exit 130' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"; exit 143' SIGTERM
function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  post_update_to_api "failed" "${command}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    if lvs --noheadings -o lv_name | grep -qE "(^|[-_])${try_id}($|[-_])"; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

function cleanup_vmid() {
  if [ -n "${VMID:-}" ] && qm status "$VMID" &>/dev/null; then
    qm stop "$VMID" &>/dev/null || true
    qm destroy "$VMID" &>/dev/null || true
  fi
}

function cleanup() {
  popd &>/dev/null || true
  command -v post_update_to_api &>/dev/null && post_update_to_api "done" "none" || true
  [ -n "${TEMP_DIR:-}" ] && rm -rf "$TEMP_DIR"
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Docker VM with Dockge & Portainer" --yesno "This will create a New Docker VM with Dockge and Portainer pre-installed. Proceed?" 10 68; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

function msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "Please run this script as root."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

pve_check() {
  local PVE_VER
  PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"
  if [[ "$PVE_VER" =~ ^8\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 9)); then
      msg_error "This version of Proxmox VE is not supported."
      exit 1
    fi
    return 0
  fi
  if [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 9)); then
      msg_error "This version of Proxmox VE is not supported."
      exit 1
    fi
    return 0
  fi
  msg_error "This version of Proxmox VE is not supported."
  exit 1
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n ${INFO} This script will not work with PiMox! \n"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:+x}" ]; then
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH. Would you like to proceed?" 10 62; then
        echo "you've been warned"
      else
        clear
        exit
      fi
    fi
  fi
}

function exit-script() {
  clear
  echo -e "\n${CROSS}${RD}User exited script${CL}\n"
  exit
}

function default_settings() {
  VMID=$(get_valid_nextid)
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_CACHE=""
  DISK_SIZE="25G"
  HN="docker"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="4096"
  BRG="vmbr0"
  START_VM="yes"
  NOTIFICATION_URL=""
  METHOD="default"
  ENABLE_ROOT_SSH="no"
  ENABLE_IPV6="yes"
  AUTHORIZED_KEY=""
  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}i440fx${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  if ROOT_PASSWORD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Set a root password for the VM" 10 60 --title "ROOT PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$ROOT_PASSWORD" ]; then
      whiptail --msgbox "A password is required to continue." 10 60
      exit-script
    fi
    echo -e "${INFO}${BOLD}${DGN}Root password is set.${CL}"
  else
    exit-script
  fi
  # Default-mode reuses the root password for the Portainer admin to avoid
  # a second prompt. Advanced mode asks separately.
  PORTAINER_ADMIN_PASSWORD="$ROOT_PASSWORD"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Docker VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $VMID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VMID" ]; then
        VMID=$(get_valid_nextid)
      fi
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
      break
    else
      exit-script
    fi
  done

  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 "i440fx" "" ON "q35" "" OFF 3>&1 1>&2 2>&3); then
    FORMAT=",efitype=4m"
    if [ "$MACH" = q35 ]; then
      MACHINE=" -machine q35"
    else
      MACHINE=""
    fi
    echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
  else
    exit-script
  fi

  if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB" 8 58 "$DISK_SIZE" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
    if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
      DISK_SIZE="${DISK_SIZE}G"
    elif ! [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]]; then
      echo -e "${CROSS}${RD}Invalid Disk Size.${CL}"
      exit-script
    fi
    echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 docker --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    HN=${VM_NAME:-docker}
    HN=$(echo ${HN,,} | tr -d ' ')
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
  else
    exit-script
  fi

  CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3) || exit-script
  CORE_COUNT=${CORE_COUNT:-2}
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"

  RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 4096 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3) || exit-script
  RAM_SIZE=${RAM_SIZE:-4096}
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"

  BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3) || exit-script
  BRG=${BRG:-vmbr0}
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"

  if MAC=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set MAC Address (leave blank for auto)" 8 58 "$GEN_MAC" --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$MAC" ]; then
      MAC="$GEN_MAC"
    fi
  else
    exit-script
  fi
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "IPv6" --yesno "Enable IPv6?" 10 58); then
    ENABLE_IPV6="yes"
  else
    ENABLE_IPV6="no"
  fi
  echo -e "${GATEWAY}${BOLD}${DGN}IPv6 Enabled: ${BGN}$ENABLE_IPV6${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Network: ${BGN}DHCP${CL} (set a reservation on your DHCP server, or edit the VM after boot)"

  if NOTIFICATION_URL=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter Watchtower Notification URL (optional)\nShoutrrr URL, any scheme: ntfy://, gotify://, discord://, telegram://, smtp://.\nExample: ntfy://ntfy.example.com/updates" 11 78 --title "NOTIFICATION URL" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
     if [ -z "$NOTIFICATION_URL" ]; then
        echo -e "${INFO}${BOLD}${DGN}No notification URL provided.${CL}"
     else
        echo -e "${INFO}${BOLD}${DGN}Notification URL set.${CL}"
     fi
  else
    exit-script
  fi

  if ROOT_PASSWORD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Set a root password for the VM" 10 60 --title "ROOT PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$ROOT_PASSWORD" ]; then
      whiptail --msgbox "A password is required to continue." 10 60
      exit-script
    fi
    echo -e "${INFO}${BOLD}${DGN}Root password is set.${CL}"
  else
    exit-script
  fi

  # Portainer admin pre-seed closes the first-boot race where anyone on the
  # network can reach http://${HN}:9443 before you do and claim the admin
  # account. --admin-password-file reads this file as plaintext at first
  # start only; it is ignored once an admin exists.
  if PORTAINER_ADMIN_PASSWORD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Set a Portainer admin password (pre-seeded; closes the 5-min first-boot race)" 10 72 --title "PORTAINER ADMIN PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$PORTAINER_ADMIN_PASSWORD" ]; then
      whiptail --msgbox "A Portainer admin password is required." 10 60
      exit-script
    fi
    # Portainer rejects admin passwords shorter than 12 characters at first-boot.
    if [ "${#PORTAINER_ADMIN_PASSWORD}" -lt 12 ]; then
      whiptail --msgbox "Portainer requires the admin password to be at least 12 characters." 10 60
      exit-script
    fi
    echo -e "${INFO}${BOLD}${DGN}Portainer admin password is set.${CL}"
  else
    exit-script
  fi

  # Optional SSH public key for the 'deploy' user (and root, when root SSH is
  # enabled below). Keeping it empty leaves password-only auth in place.
  if AUTHORIZED_KEY=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Paste an SSH public key for the 'deploy' user (optional, leave blank to skip).\nExample: ssh-ed25519 AAAA... user@host" 11 78 --title "SSH AUTHORIZED KEY" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    AUTHORIZED_KEY=$(echo "$AUTHORIZED_KEY" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [ -z "$AUTHORIZED_KEY" ]; then
      echo -e "${INFO}${BOLD}${DGN}No SSH authorized key provided.${CL}"
    elif ! [[ "$AUTHORIZED_KEY" =~ ^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)\  ]]; then
      whiptail --msgbox "That does not look like an OpenSSH public key (expected 'ssh-ed25519 AAAA...' or similar). Leaving SSH key empty." 10 72
      AUTHORIZED_KEY=""
    else
      echo -e "${INFO}${BOLD}${DGN}SSH authorized key set.${CL}"
    fi
  else
    exit-script
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ROOT SSH LOGIN" --yesno "Allow root login via SSH?" 10 58 --defaultno); then
    ENABLE_ROOT_SSH="yes"
  else
    ENABLE_ROOT_SSH="no"
  fi
  echo -e "${GATEWAY}${BOLD}${DGN}Allow root SSH login: ${BGN}${ENABLE_ROOT_SSH}${CL}"

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    START_VM="yes"
  else
    START_VM="no"
  fi
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}$START_VM${CL}"

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Ready to create the VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Docker VM with Dockge & Portainer using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}
check_root
arch_check
pve_check
ssh_check

msg_info "Detecting Timezone from host"
TIMEZONE=$(timedatectl show -p Timezone --value 2>/dev/null | tr -d '[:space:]')
if [ -z "$TIMEZONE" ]; then
    TIMEZONE=$(tr -d '[:space:]' </etc/timezone 2>/dev/null || true)
fi
# Reject anything that is not a plausible IANA tz identifier.
if ! [[ "$TIMEZONE" =~ ^[A-Za-z]+(/[A-Za-z_+-]+)+$ || "$TIMEZONE" == "UTC" ]]; then
    msg_error "Could not read a valid host timezone. Defaulting to UTC."
    TIMEZONE="Etc/UTC"
else
    msg_ok "Timezone detected as ${CL}${BL}$TIMEZONE${CL}"
fi

start_script
post_to_api_vm

msg_info "Validating Storage"
while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist "Which storage pool would you like to use?" 16 $(($MSG_MAX_LENGTH + 23)) 6 "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
msg_info "Retrieving the URL for the Debian 13 Qcow2 Disk Image"
URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-$(dpkg --print-architecture).qcow2"
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

# Integrity check against the published SHA512SUMS (not authenticity:
# Debian's cloud team does not sign per-distribution images consistently,
# so a GPG verify would be security theatre here). Protects against on-disk
# corruption and partial downloads; HTTPS covers the authenticity leg.
msg_info "Verifying ${FILE} integrity (SHA512SUMS)"
SUMS_URL="$(dirname "$URL")/SHA512SUMS"
curl -fsSL -o SHA512SUMS "$SUMS_URL" \
  || { msg_error "Could not fetch SHA512SUMS from ${SUMS_URL}"; exit 1; }
# -F ' ' then $1 anchors the exact filename, no partial matches.
expected_sum=$(awk -v f="$FILE" '$2 ~ ("^[*]?" f "$") {print $1; exit}' SHA512SUMS)
if [ -z "$expected_sum" ]; then
  msg_error "SHA512SUMS has no entry for ${FILE} — refusing to continue"
  exit 1
fi
actual_sum=$(sha512sum "$FILE" | awk '{print $1}')
if [ "$expected_sum" != "$actual_sum" ]; then
  msg_error "SHA512 mismatch for ${FILE} — refusing to continue"
  exit 1
fi
msg_ok "Verified ${FILE} integrity"

STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  THIN=""
  ;;
esac
for i in 0 1; do
  disk_name="vm-${VMID}-disk-${i}${DISK_EXT:-}"
  disk_ref="${STORAGE}:${DISK_REF:-}${disk_name}"
  declare "DISK${i}=${disk_name}"
  declare "DISK${i}_REF=${disk_ref}"
done
unset disk_name disk_ref

if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing Pre-Requisite libguestfs-tools"
  apt-get -qq update >/dev/null
  apt-get -qq install libguestfs-tools lsb-release -y >/dev/null
  msg_ok "Installed libguestfs-tools successfully"
fi

msg_info "Creating Docker stack configuration files"
# Dockge Compose File
#
# Two Watchtower instances with distinct scopes:
#   - watchtower (scope=dockge) auto-updates Dockge, itself, and the stacks
#     Dockge manages. Needs the raw Docker socket because container updates
#     require POST /containers/create (recreate), which the socket proxy
#     would also have to allow — so the proxy would not meaningfully reduce
#     this instance's authority.
#   - watchtower-portainer (scope=portainer, --monitor-only) ONLY notifies
#     when Portainer or portainer-agent have an update available. Because
#     it never writes, it talks to the Docker API through docker-socket-
#     proxy with POST=0 — so even a full compromise cannot create or
#     recreate containers.
cat <<EOF >"$TEMP_DIR/dockge-compose.yml"
name: dockge
services:
  dockge:
    image: louislam/dockge:${DOCKGE_TAG}
    container_name: dockge
    restart: unless-stopped
    ports:
      - 5001:5001
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - /opt/stacks:/opt/stacks
    environment:
      - DOCKGE_STACKS_DIR=/opt/stacks
      - TZ=${TIMEZONE}
    labels:
      - com.centurylinklabs.watchtower.scope=dockge
  watchtower:
    image: ${WATCHTOWER_IMAGE}:${WATCHTOWER_TAG}
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_NOTIFICATION_URL=${NOTIFICATION_URL}
      - WATCHTOWER_NOTIFICATIONS_HOSTNAME=${HN}
      - WATCHTOWER_NOTIFICATION_TITLE_TAG=Dockge
      - WATCHTOWER_SCOPE=dockge
      - TZ=${TIMEZONE}
    command: --schedule "0 0 4 * * *" --cleanup
    labels:
      - com.centurylinklabs.watchtower.scope=dockge
  # Read-only Docker API facade: only CONTAINERS and IMAGES are exposed, and
  # POST is denied, so clients talking through this proxy can inspect but
  # not create, start, stop, or remove anything. Sits on an internal
  # (egressless) bridge so only services on that network can reach it.
  docker-socket-proxy:
    image: ${SOCKET_PROXY_IMAGE}:${SOCKET_PROXY_TAG}
    container_name: docker-socket-proxy
    restart: unless-stopped
    privileged: true
    environment:
      - CONTAINERS=1
      - IMAGES=1
      - POST=0
      - TZ=${TIMEZONE}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - socket-proxy
    # Deliberately unscoped: pin and bump this one manually. Running the
    # updater through the thing it is updating would guarantee an outage.
  watchtower-portainer:
    image: ${WATCHTOWER_IMAGE}:${WATCHTOWER_TAG}
    container_name: watchtower-portainer
    restart: unless-stopped
    depends_on:
      - docker-socket-proxy
    environment:
      - DOCKER_HOST=tcp://docker-socket-proxy:2375
      - WATCHTOWER_NOTIFICATION_URL=${NOTIFICATION_URL}
      - WATCHTOWER_NOTIFICATIONS_HOSTNAME=${HN}
      - WATCHTOWER_NOTIFICATION_TITLE_TAG=Portainer
      - WATCHTOWER_SCOPE=portainer
      - WATCHTOWER_MONITOR_ONLY=true
      - TZ=${TIMEZONE}
    # 05:30 so notifications land after the 04:00 dockge-scope run.
    command: --schedule "0 30 5 * * *"
    networks:
      - socket-proxy
      - default
    labels:
      - com.centurylinklabs.watchtower.scope=portainer
networks:
  socket-proxy:
    driver: bridge
    internal: true
EOF

# Portainer Compose File with Agent.
# The agent exists so a remote Portainer can manage this VM via tcp/9001;
# the local portainer-ce would reach docker.sock directly either way.
# deploy.restart_policy is swarm-only — docker compose up ignores it — so
# the restart behaviour is set at the service level with `restart:`.
#
# --admin-password-file reads a PLAINTEXT password file at FIRST start and
# bcrypt-hashes it into the database. Once an admin exists the flag is
# ignored, so this closes the five-minute race where anyone on the network
# could reach :9443 and claim the admin account before you.
#
# scope=portainer labels pair with watchtower-portainer (monitor-only) in
# dockge-compose.yml: updates are detected and sent to the notification
# channel but never applied — Portainer stays on a pinned tag you bump.
cat <<EOF >"$TEMP_DIR/portainer-compose.yml"
name: portainer
services:
  portainer-agent:
    container_name: portainer-agent
    image: portainer/agent:${PORTAINER_AGENT_TAG}
    restart: unless-stopped
    ports:
      - 9001:9001
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    environment:
      - TZ=${TIMEZONE}
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 1024M
    labels:
      - com.centurylinklabs.watchtower.scope=portainer
  portainer:
    container_name: portainer
    image: portainer/portainer-ce:${PORTAINER_CE_TAG}
    restart: unless-stopped
    command: --admin-password-file=/run/secrets/portainer_admin_password
    ports:
      - 8000:8000
      - 9443:9443
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
      - /opt/portainer_secrets/portainer_admin_password:/run/secrets/portainer_admin_password:ro
    environment:
      - TZ=${TIMEZONE}
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 1024M
    labels:
      - com.centurylinklabs.watchtower.scope=portainer
volumes:
  portainer_data:
    name: portainer_data
EOF

# One-shot startup script
cat <<EOF >"$TEMP_DIR/initial-startup.sh"
#!/bin/bash
# Start Dockge Stack
cd /opt/stacks/dockge
/usr/bin/docker compose up -d
# Start Portainer Stack
cd /opt/stacks/portainer
/usr/bin/docker compose up -d
# Disable this service
systemctl disable initial-startup.service
EOF

# systemd service file
cat <<EOF >"$TEMP_DIR/initial-startup.service"
[Unit]
Description=Initial Docker Stacks Startup
After=docker.service network-online.target
Requires=docker.service network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/initial-startup.sh
[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Docker stack configuration files successfully"

msg_info "Customizing Debian 13 Qcow2 Disk Image"

# Write the root password to a 0600 file inside the already-mode-0700
# $TEMP_DIR so it never appears on virt-customize's command line (which
# would leak via /proc/*/cmdline to any local non-root user) and so shell
# metacharacters in the password cannot inject into eval.
(
  umask 077
  printf '%s\n' "$ROOT_PASSWORD" > "$TEMP_DIR/rootpw"
  # Portainer admin password file: plaintext, no trailing newline (Portainer
  # reads the entire file as the password). 0600 inside 0700 $TEMP_DIR; the
  # final file inside the VM is uploaded with 0600 and lives under
  # /opt/portainer_secrets, outside Dockge's /opt/stacks view.
  printf '%s' "$PORTAINER_ADMIN_PASSWORD" > "$TEMP_DIR/portainer_admin_password"
)

# Build the virt-customize invocation as an argv array so each payload is
# passed verbatim — no string concatenation, no eval, no re-parsing.
# shellcheck disable=SC2054  # --install takes a comma-separated apt list; the commas are literal.
cmd=(
  virt-customize -q -a "$FILE"
  --root-password "file:$TEMP_DIR/rootpw"
  --install qemu-guest-agent,apt-transport-https,ca-certificates,curl,gnupg,lsb-release,openssh-server
  --hostname "$HN"
  --run-command 'mkdir -p /opt/stacks/dockge /opt/stacks/portainer /opt/portainer_secrets'
  --run-command 'chmod 0700 /opt/portainer_secrets'
  # Create a non-root user so paired stacks (e.g. qbittorrent-vpn-docker)
  # can run with PUID=1000/PGID=1000 instead of as root.
  --run-command 'id deploy >/dev/null 2>&1 || useradd -u 1000 -m -s /bin/bash deploy'
  --run-command 'getent group docker >/dev/null || groupadd docker; usermod -aG docker deploy || true'
  --upload "$TEMP_DIR/dockge-compose.yml:/opt/stacks/dockge/docker-compose.yml"
  --upload "$TEMP_DIR/portainer-compose.yml:/opt/stacks/portainer/docker-compose.yml"
  --upload "$TEMP_DIR/portainer_admin_password:/opt/portainer_secrets/portainer_admin_password"
  --chmod 0600:/opt/portainer_secrets/portainer_admin_password
  --upload "$TEMP_DIR/initial-startup.sh:/usr/local/bin/initial-startup.sh"
  --upload "$TEMP_DIR/initial-startup.service:/etc/systemd/system/initial-startup.service"
  --chmod 0755:/usr/local/bin/initial-startup.sh
)

if [ -n "$AUTHORIZED_KEY" ]; then
  # --ssh-inject appends to ~/.ssh/authorized_keys and handles perms/dir
  # creation for us. The 'string:' form passes the key verbatim; the key
  # was format-validated at prompt time so no shell meta risk here.
  cmd+=( --ssh-inject "deploy:string:${AUTHORIZED_KEY}" )
fi

if [ "$ENABLE_ROOT_SSH" == "yes" ]; then
  cmd+=( --run-command 'sed -i "s/^#*PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config' )
  if [ -n "$AUTHORIZED_KEY" ]; then
    cmd+=( --ssh-inject "root:string:${AUTHORIZED_KEY}" )
  fi
fi
if [ "$ENABLE_IPV6" == "no" ]; then
  cmd+=( --run-command 'printf "net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1\n" > /etc/sysctl.d/99-disable-ipv6.conf' )
fi

cmd+=(
  --run-command 'mkdir -p /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg'
  --run-command "echo 'deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian trixie stable' > /etc/apt/sources.list.d/docker.list"
  --run-command 'apt-get update -qq && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin'
  --run-command 'systemctl enable docker'
  --run-command 'systemctl enable initial-startup.service'
  --run-command 'echo -n > /etc/machine-id'
)

"${cmd[@]}" >/dev/null
rm -f "$TEMP_DIR/rootpw" "$TEMP_DIR/portainer_admin_password"

msg_ok "Customized image with Docker, Dockge, and Portainer successfully"

msg_info "Expanding root partition to use full disk space"
qemu-img create -f qcow2 expanded.qcow2 ${DISK_SIZE} >/dev/null 2>&1
virt-resize --expand /dev/sda1 ${FILE} expanded.qcow2 >/dev/null 2>&1
mv expanded.qcow2 ${FILE} >/dev/null 2>&1
msg_ok "Expanded image to full size"

msg_info "Creating the Docker VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags docker,dockge,portainer,debian13 -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${THIN}size=${DISK_SIZE} \
  -boot order=scsi0 \
  -serial0 socket >/dev/null

qm set $VMID --agent enabled=1 >/dev/null

DESCRIPTION=$(cat <<EOF
<div align='center'>
  <h2>Docker VM with Dockge & Portainer</h2>
  <p>This VM comes pre-configured with Docker, Dockge, and Portainer.</p>
  <hr>
  <p>Find the VM's IP in the 'Summary' tab once it's running.</p>
  <p>Access Dockge at: <strong><a href="http://${HN}:5001" target="_blank">http://${HN}:5001</a></strong></p>
  <p>Access Portainer at: <strong><a href="https://${HN}:9443" target="_blank">https://${HN}:9443</a></strong></p>
</div>
EOF
)
qm set "$VMID" -description "$DESCRIPTION" >/dev/null

msg_ok "Created Docker VM with Dockge & Portainer ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Docker VM"
  qm start $VMID
  msg_ok "Started Docker VM"
fi
post_update_to_api "done" "none"
msg_ok "Completed Successfully!\n"
