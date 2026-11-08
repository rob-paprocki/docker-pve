#!/usr/bin/env bash
#
# docker-stack-vm.sh — provision a Debian 13 VM on Proxmox VE pre-loaded with
# Docker + Dockhand (Dockge optional).
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
# Dockhand is the Docker manager and also applies image updates (a nightly
# environment-wide schedule seeded at first boot), so no Watchtower runs.
DOCKHAND_IMAGE="${DOCKHAND_IMAGE:-fnsys/dockhand}"
DOCKHAND_TAG="${DOCKHAND_TAG:-v1.0.57}"
# Dockge is optional (Advanced settings, off by default).
DOCKGE_TAG="${DOCKGE_TAG:-1.5.0}"

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
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Docker VM with Dockhand" --yesno "This will create a New Docker VM with Dockhand pre-installed. Proceed?" 10 68; then
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
  INSTALL_DOCKGE="no"
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
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Install Dockge: ${BGN}no${CL}"
  if ROOT_PASSWORD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Set a root password for the VM" 10 60 --title "ROOT PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$ROOT_PASSWORD" ]; then
      whiptail --msgbox "A password is required to continue." 10 60
      exit-script
    fi
    # Default mode reuses this password for the Dockhand admin, and Dockhand
    # rejects passwords shorter than 8 characters (first boot would then
    # leave Dockhand locked to 127.0.0.1), so enforce that here.
    if [ "${#ROOT_PASSWORD}" -lt 8 ]; then
      whiptail --msgbox "The root password is also used for the Dockhand admin, which needs at least 8 characters." 10 72
      exit-script
    fi
    echo -e "${INFO}${BOLD}${DGN}Root password is set.${CL}"
  else
    exit-script
  fi
  # Default-mode reuses the root password for the Dockhand admin to avoid
  # a second prompt. Advanced mode asks separately.
  DOCKHAND_ADMIN_PASSWORD="$ROOT_PASSWORD"
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

  if NOTIFICATION_URL=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter a notification URL for Dockhand's update results (optional)\nApprise-style: ntfys://, discord://, tgram://, gotify://, slack://, pover://.\nExample: ntfys://ntfy.example.com/updates" 11 78 --title "NOTIFICATION URL" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
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

  # Dockhand starts with authentication off and lets whoever reaches it
  # first create the admin. The first-boot script creates this admin and
  # enables authentication while Dockhand is still published on 127.0.0.1,
  # so there is no window for anyone on the network to claim it.
  if DOCKHAND_ADMIN_PASSWORD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Set the Dockhand admin password (user 'admin'; set before Dockhand is reachable)" 10 72 --title "DOCKHAND ADMIN PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$DOCKHAND_ADMIN_PASSWORD" ]; then
      whiptail --msgbox "A Dockhand admin password is required." 10 60
      exit-script
    fi
    # Dockhand rejects passwords shorter than 8 characters.
    if [ "${#DOCKHAND_ADMIN_PASSWORD}" -lt 8 ]; then
      whiptail --msgbox "Dockhand requires the admin password to be at least 8 characters." 10 60
      exit-script
    fi
    echo -e "${INFO}${BOLD}${DGN}Dockhand admin password is set.${CL}"
  else
    exit-script
  fi

  # Dockge is an optional second compose UI over the same /opt/stacks
  # folders. Off by default: Dockhand already covers it, and Dockge's
  # bundled Docker Compose recreates containers the host's Compose created.
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "DOCKGE" --yesno "Also install Dockge as a secondary compose UI (port 5001)?" 10 62 --defaultno); then
    INSTALL_DOCKGE="yes"
  else
    INSTALL_DOCKGE="no"
  fi
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Install Dockge: ${BGN}${INSTALL_DOCKGE}${CL}"

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
    echo -e "${CREATING}${BOLD}${DGN}Creating a Docker VM with Dockhand using the above advanced settings${CL}"
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
# Dockhand compose file. Dockhand lives in /opt/dockhand, outside the
# /opt/stacks folder it manages, and both are mounted at the same paths
# inside the container so compose files with relative paths resolve on the
# host. DOCKHAND_BIND (escaped below, so Compose reads it at run time) lets
# the first-boot script publish Dockhand on 127.0.0.1 only until its admin
# account exists and authentication is on.
cat <<EOF >"$TEMP_DIR/dockhand-compose.yml"
name: dockhand
services:
  dockhand:
    image: ${DOCKHAND_IMAGE}:${DOCKHAND_TAG}
    container_name: dockhand
    restart: unless-stopped
    ports:
      - \${DOCKHAND_BIND:-0.0.0.0}:3000:3000
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/dockhand/data:/opt/dockhand/data
      - /opt/stacks:/opt/stacks
    environment:
      - DATA_DIR=/opt/dockhand/data
      - STACKS_DIR=/opt/stacks
      - TZ=${TIMEZONE}
EOF

# Optional Dockge compose file (Advanced settings), over the same
# /opt/stacks folder. Dockhand's nightly update covers it like any other
# container, so it carries no updater of its own.
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
EOF

# Build-time values for the first-boot script; %q keeps them shell-safe.
printf 'VM_HOSTNAME=%q\nTIMEZONE=%q\n' "$HN" "$TIMEZONE" >"$TEMP_DIR/firstboot.env"

# First-boot script. Quoted heredoc: nothing in it is expanded here.
cat <<'EOF' >"$TEMP_DIR/initial-startup.sh"
#!/bin/bash
# First-boot provisioning, run by initial-startup.service until it succeeds.
#
# Dockhand starts with authentication disabled and lets whoever reaches it
# first create the admin account. To close that window it is first
# published on 127.0.0.1 only, configured and locked down through its API
# from here, and republished on the LAN only after an unauthenticated API
# call is refused. Any failure exits non-zero with Dockhand still on
# loopback; the unit stays enabled and retries on the next boot.
set -euo pipefail

# VM_HOSTNAME and TIMEZONE, written by docker-stack-vm.sh.
# shellcheck source=/dev/null
. /opt/dockhand/firstboot.env

API=http://127.0.0.1:3000/api
SECRETS=/opt/dockhand_secrets
UPDATE_CRON="0 4 * * *"

log() { echo "[initial-startup] $*"; }

# api METHOD PATH [JSON]: call the local Dockhand API and print the response
# body. The JSON body goes in on stdin so secrets never reach a command line.
# Fails on HTTP >= 400.
api() {
  local method=$1 path=$2 body=${3:-} out code
  out=$(mktemp)
  code=$(printf '%s' "$body" | curl -sS -o "$out" -w '%{http_code}' -X "$method" \
    -H 'Content-Type: application/json' --data-binary @- "$API$path") || code=000
  cat "$out"
  rm -f "$out"
  if [ "$code" -ge 400 ] || [ "$code" = 000 ]; then
    log "$method $path failed (HTTP $code)" >&2
    return 1
  fi
}

# py CODE [ARGS...]: run a small Python snippet (stdin = previous API reply).
py() { python3 -c "$1" "${@:2}"; }

# Optional Dockge (installed only when chosen in the wizard).
if [ -f /opt/stacks/dockge/compose.yaml ]; then
  (cd /opt/stacks/dockge && docker compose up -d)
fi

cd /opt/dockhand
DOCKHAND_BIND=127.0.0.1 docker compose up -d
for _ in $(seq 1 90); do
  curl -s -o /dev/null "$API/auth/settings" && break
  sleep 2
done

# Once authentication is on, anonymous API calls get 401: an earlier run
# finished seeding (it may have failed later, e.g. while republishing).
if [ "$(curl -s -o /dev/null -w '%{http_code}' "$API/environments")" = 401 ]; then
  log "Dockhand authentication is already enabled; skipping seeding."
else
  # 1. Local Docker environment (reused if an earlier partial run made it).
  ENV_ID=$(api GET /environments | py 'import json,sys
for e in json.load(sys.stdin):
    if e.get("connectionType") == "socket":
        print(e["id"]); break')
  if [ -z "$ENV_ID" ]; then
    ENV_ID=$(api POST /environments "$(py 'import json,sys; print(json.dumps({"name": sys.argv[1], "connectionType": "socket", "socketPath": "/var/run/docker.sock"}))' "$VM_HOSTNAME")" \
      | py 'import json,sys; print(json.load(sys.stdin)["id"])')
  fi
  log "Docker environment id: $ENV_ID"

  # 2. Scan /opt/stacks for stacks, and run schedules in local time.
  api POST /settings/general "$(py 'import json,sys; print(json.dumps({"externalStackPaths": ["/opt/stacks"], "defaultTimezone": sys.argv[1]}))' "$TIMEZONE")" >/dev/null

  # 3. Nightly update check that applies updates, unless the new image has
  #    more known vulnerabilities than the one it replaces.
  api POST "/environments/$ENV_ID/update-check" "$(py 'import json,sys; print(json.dumps({"enabled": True, "cron": sys.argv[1], "autoUpdate": True, "vulnerabilityCriteria": "more_than_current"}))' "$UPDATE_CRON")" >/dev/null
  log "Auto-update scheduled: '$UPDATE_CRON' ($TIMEZONE)"

  # 4. Optional notification channel for update results. A bad URL is
  #    logged, not fatal: it can be fixed later under Settings > Notifications.
  if [ -s "$SECRETS/notification_url" ] &&
    ! api GET /notifications | py 'import json,sys; sys.exit(0 if any(n.get("name") == "Update results" for n in json.load(sys.stdin)) else 1)'; then
    if NOTIF_ID=$(api POST /notifications "$(py 'import json,sys; print(json.dumps({"type": "apprise", "name": "Update results", "enabled": True, "config": {"urls": [open(sys.argv[1]).read().strip()]}}))' "$SECRETS/notification_url")" \
        | py 'import json,sys; print(json.load(sys.stdin)["id"])') &&
      api POST "/environments/$ENV_ID/notifications" '{"notificationId": '"$NOTIF_ID"', "enabled": true, "eventTypes": ["auto_update_success", "auto_update_failed", "auto_update_blocked"]}' >/dev/null; then
      log "Notification channel added."
    else
      log "WARNING: could not add the notification channel; add it in Dockhand under Settings > Notifications."
    fi
  fi

  # 5. Adopt stacks already in /opt/stacks (Dockge, when installed).
  STACKS_JSON=$(api POST /stacks/scan '{}' | py 'import json,sys
d = json.load(sys.stdin)
print(json.dumps({"stacks": [{"name": s["name"], "composePath": s["composePath"]} for s in d.get("discovered", [])], "environmentId": int(sys.argv[1])}))' "$ENV_ID")
  if [ "$(py 'import json,sys; print(len(json.loads(sys.argv[1])["stacks"]))' "$STACKS_JSON")" -gt 0 ]; then
    api POST /stacks/adopt "$STACKS_JSON" >/dev/null || log "WARNING: adopting existing stacks failed; use Stacks > Scan in Dockhand."
  fi

  # 6. Admin account, then authentication on. Last, so a failure above
  #    leaves nothing half locked.
  if ! api GET /users | py 'import json,sys; sys.exit(0 if any(u.get("username") == "admin" for u in json.load(sys.stdin)) else 1)'; then
    api POST /users "$(py 'import json,sys; print(json.dumps({"username": "admin", "password": open(sys.argv[1]).read()}))' "$SECRETS/admin_password")" >/dev/null
  fi
  api PUT /auth/settings '{"authEnabled": true, "defaultProvider": "local"}' >/dev/null
  log "Admin account created and authentication enabled."
fi

# Publish on the LAN only once the API refuses anonymous requests.
code=$(curl -s -o /dev/null -w '%{http_code}' "$API/environments")
if [ "$code" != 401 ]; then
  log "ERROR: anonymous API request returned HTTP $code, not 401; leaving Dockhand on 127.0.0.1."
  exit 1
fi
docker compose up -d
log "Dockhand published on port 3000."

rm -f "$SECRETS/admin_password" "$SECRETS/notification_url"
systemctl disable initial-startup.service
EOF

# systemd service file. The script disables it only after it succeeds, so a
# failed first boot is retried on the next one.
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
  # Dockhand admin password and optional notification URL for the
  # first-boot script: plaintext, no trailing newline. 0600 inside the 0700
  # $TEMP_DIR; uploaded 0600 into /opt/dockhand_secrets (0700), outside the
  # /opt/stacks view, and deleted by the first-boot script once Dockhand is
  # seeded.
  printf '%s' "$DOCKHAND_ADMIN_PASSWORD" > "$TEMP_DIR/dockhand_admin_password"
  printf '%s' "$NOTIFICATION_URL" > "$TEMP_DIR/notification_url"
)

# Build the virt-customize invocation as an argv array so each payload is
# passed verbatim — no string concatenation, no eval, no re-parsing.
# shellcheck disable=SC2054  # --install takes a comma-separated apt list; the commas are literal.
cmd=(
  virt-customize -q -a "$FILE"
  --root-password "file:$TEMP_DIR/rootpw"
  # git and python3-venv serve the paired qbittorrent-vpn-docker stack: its
  # README clones the repo into /opt/stacks, and its scripts/setup.sh builds
  # a Python venv for the env-editor. The Debian 13 nocloud image ships
  # python3 but neither of these (git otherwise only arrives as a docker-ce
  # Recommends), and without python3-venv setup.sh fails on first run.
  --install qemu-guest-agent,apt-transport-https,ca-certificates,curl,gnupg,lsb-release,openssh-server,git,python3-venv
  --hostname "$HN"
  --run-command 'mkdir -p /opt/stacks /opt/dockhand/data /opt/dockhand_secrets'
  --run-command 'chmod 0700 /opt/dockhand_secrets'
  # Create a non-root user so paired stacks (e.g. qbittorrent-vpn-docker)
  # can run with PUID=1000/PGID=1000 instead of as root.
  --run-command 'id deploy >/dev/null 2>&1 || useradd -u 1000 -m -s /bin/bash deploy'
  --run-command 'getent group docker >/dev/null || groupadd docker; usermod -aG docker deploy || true'
  --upload "$TEMP_DIR/dockhand-compose.yml:/opt/dockhand/compose.yaml"
  --upload "$TEMP_DIR/firstboot.env:/opt/dockhand/firstboot.env"
  --upload "$TEMP_DIR/dockhand_admin_password:/opt/dockhand_secrets/admin_password"
  --chmod 0600:/opt/dockhand_secrets/admin_password
  --upload "$TEMP_DIR/notification_url:/opt/dockhand_secrets/notification_url"
  --chmod 0600:/opt/dockhand_secrets/notification_url
  --upload "$TEMP_DIR/initial-startup.sh:/usr/local/bin/initial-startup.sh"
  --upload "$TEMP_DIR/initial-startup.service:/etc/systemd/system/initial-startup.service"
  --chmod 0755:/usr/local/bin/initial-startup.sh
)

if [ "$INSTALL_DOCKGE" == "yes" ]; then
  cmd+=(
    --run-command 'mkdir -p /opt/stacks/dockge'
    --upload "$TEMP_DIR/dockge-compose.yml:/opt/stacks/dockge/compose.yaml"
  )
fi

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
rm -f "$TEMP_DIR/rootpw" "$TEMP_DIR/dockhand_admin_password" "$TEMP_DIR/notification_url"

msg_ok "Customized image with Docker and Dockhand successfully"

msg_info "Expanding root partition to use full disk space"
qemu-img create -f qcow2 expanded.qcow2 ${DISK_SIZE} >/dev/null 2>&1
virt-resize --expand /dev/sda1 ${FILE} expanded.qcow2 >/dev/null 2>&1
mv expanded.qcow2 ${FILE} >/dev/null 2>&1
msg_ok "Expanded image to full size"

msg_info "Creating the Docker VM"
VM_TAGS="docker,dockhand,debian13"
if [ "$INSTALL_DOCKGE" == "yes" ]; then
  VM_TAGS="${VM_TAGS},dockge"
fi
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags "$VM_TAGS" -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${THIN}size=${DISK_SIZE} \
  -boot order=scsi0 \
  -serial0 socket >/dev/null

qm set $VMID --agent enabled=1 >/dev/null

DOCKGE_LINK=""
if [ "$INSTALL_DOCKGE" == "yes" ]; then
  DOCKGE_LINK="<p>Dockge (secondary): <strong><a href=\"http://${HN}:5001\" target=\"_blank\">http://${HN}:5001</a></strong></p>"
fi
DESCRIPTION=$(cat <<EOF
<div align='center'>
  <h2>Docker VM with Dockhand</h2>
  <p>This VM comes pre-configured with Docker and Dockhand.</p>
  <hr>
  <p>Find the VM's IP in the 'Summary' tab once it's running.</p>
  <p>Access Dockhand at: <strong><a href="http://${HN}:3000" target="_blank">http://${HN}:3000</a></strong> (user <code>admin</code>)</p>
  ${DOCKGE_LINK}
</div>
EOF
)
qm set "$VMID" -description "$DESCRIPTION" >/dev/null

msg_ok "Created Docker VM with Dockhand ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Docker VM"
  qm start $VMID
  msg_ok "Started Docker VM"
fi
post_update_to_api "done" "none"
msg_ok "Completed Successfully!\n"
