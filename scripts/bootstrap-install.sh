#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

NIX_USER=""
NIX_HOST=""
NIX_IP=""
NIX_GATEWAY=""
NIX_DNS=""
NIX_DISK=""
SSH_KEY_URL=""
SSH_KEY_FILE=""
SSH_KEY_STDIN="false"
NIX_IFACE=""
NIX_PREFIX="24"
TIMEZONE="Asia/Tokyo"
LOCALE="en_US.UTF-8"
CONFIRM="false"
BOOT_MODE="auto"
MOUNT_POINT="/mnt"
STATE_VERSION="25.05"

usage() {
  cat <<EOF
Usage:
  sudo bash ${SCRIPT_NAME} \\
    --user USER \\
    --host HOSTNAME \\
    --ip IP_ADDRESS \\
    --gateway GATEWAY \\
    --dns DNS_SERVER \\
    --disk DISK \\
    --ssh-key-url SSH_KEY_URL \\
    --yes-i-really-mean-it

Options:
  --user USER                 User account to create. Example: yasuo
  --host HOSTNAME             NixOS hostname. Example: nixos-utm-dev
  --ip IP_ADDRESS             Static IPv4 address. Example: 192.168.10.50
  --gateway GATEWAY           Default gateway. Example: 192.168.10.1
  --dns DNS_SERVER            DNS server. Example: 1.1.1.1
  --disk DISK                 Target install disk. Example: /dev/sda, /dev/vda, /dev/nvme0n1

  --ssh-key-url URL           URL to fetch public SSH keys
  --ssh-key-file FILE         Local public key file on the NixOS Live environment
  --ssh-key-stdin             Read public SSH keys from standard input

  --iface IFACE               Network interface name. Auto-detected if omitted
  --prefix PREFIX             IPv4 prefix length. Default: 24
  --timezone TIMEZONE         Time zone. Default: Asia/Tokyo
  --locale LOCALE             Default locale. Default: en_US.UTF-8
  --state-version VERSION     NixOS stateVersion. Default: 25.05
  --boot-mode MODE            auto, efi, or bios. Default: auto
  --yes-i-really-mean-it      Required. Confirms destructive disk operations
  --help                      Show this help

WARNING:
  This script partitions and formats the target disk.
  All data on the specified disk will be destroyed.

Default local user password:
  changeme

After installation:
  Reboot the machine and connect via SSH from the host OS.
EOF
}

log() {
  echo "[INFO] $*" >&2
}

warn() {
  echo "[WARN] $*" >&2
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "This script must be run as root. Try: sudo bash ${SCRIPT_NAME} ..."
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        NIX_USER="${2:-}"
        shift 2
        ;;
      --host)
        NIX_HOST="${2:-}"
        shift 2
        ;;
      --ip)
        NIX_IP="${2:-}"
        shift 2
        ;;
      --gateway)
        NIX_GATEWAY="${2:-}"
        shift 2
        ;;
      --dns)
        NIX_DNS="${2:-}"
        shift 2
        ;;
      --disk)
        NIX_DISK="${2:-}"
        shift 2
        ;;
      --ssh-key-url)
        SSH_KEY_URL="${2:-}"
        shift 2
        ;;
      --ssh-key-file)
        SSH_KEY_FILE="${2:-}"
        shift 2
        ;;
      --ssh-key-stdin)
        SSH_KEY_STDIN="true"
        shift
        ;;
      --iface)
        NIX_IFACE="${2:-}"
        shift 2
        ;;
      --prefix)
        NIX_PREFIX="${2:-}"
        shift 2
        ;;
      --timezone)
        TIMEZONE="${2:-}"
        shift 2
        ;;
      --locale)
        LOCALE="${2:-}"
        shift 2
        ;;
      --state-version)
        STATE_VERSION="${2:-}"
        shift 2
        ;;
      --boot-mode)
        BOOT_MODE="${2:-}"
        shift 2
        ;;
      --yes-i-really-mean-it)
        CONFIRM="true"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

validate_args() {
  [[ -n "${NIX_USER}" ]] || die "--user is required"
  [[ -n "${NIX_HOST}" ]] || die "--host is required"
  [[ -n "${NIX_IP}" ]] || die "--ip is required"
  [[ -n "${NIX_GATEWAY}" ]] || die "--gateway is required"
  [[ -n "${NIX_DNS}" ]] || die "--dns is required"
  [[ -n "${NIX_DISK}" ]] || die "--disk is required"

  [[ "${CONFIRM}" == "true" ]] || die "--yes-i-really-mean-it is required"

  [[ -b "${NIX_DISK}" ]] || die "Target disk is not a block device: ${NIX_DISK}"

  local key_source_count=0

  [[ -n "${SSH_KEY_URL}" ]] && key_source_count=$((key_source_count + 1))
  [[ -n "${SSH_KEY_FILE}" ]] && key_source_count=$((key_source_count + 1))
  [[ "${SSH_KEY_STDIN}" == "true" ]] && key_source_count=$((key_source_count + 1))

  if (( key_source_count == 0 )); then
    die "One of --ssh-key-url, --ssh-key-file, or --ssh-key-stdin is required"
  fi

  if (( key_source_count > 1 )); then
    die "Use only one of --ssh-key-url, --ssh-key-file, or --ssh-key-stdin"
  fi

  if [[ ! "${NIX_USER}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    die "Invalid username: ${NIX_USER}"
  fi

  if [[ ! "${NIX_HOST}" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
    die "Invalid hostname: ${NIX_HOST}"
  fi

  if [[ ! "${NIX_PREFIX}" =~ ^[0-9]+$ ]]; then
    die "Invalid prefix length: ${NIX_PREFIX}"
  fi

  if (( NIX_PREFIX < 1 || NIX_PREFIX > 32 )); then
    die "Prefix length must be between 1 and 32"
  fi

  case "${BOOT_MODE}" in
    auto|efi|bios) ;;
    *) die "--boot-mode must be auto, efi, or bios" ;;
  esac
}

detect_boot_mode() {
  if [[ "${BOOT_MODE}" != "auto" ]]; then
    log "Using specified boot mode: ${BOOT_MODE}"
    return
  fi

  if [[ -d /sys/firmware/efi/efivars ]]; then
    BOOT_MODE="efi"
  else
    BOOT_MODE="bios"
  fi

  log "Auto-detected boot mode: ${BOOT_MODE}"
}

detect_interface() {
  if [[ -n "${NIX_IFACE}" ]]; then
    log "Using specified network interface: ${NIX_IFACE}"
    return
  fi

  local detected=""
  detected="$(ip route show default 2>/dev/null | awk '{print $5; exit}' || true)"

  if [[ -z "${detected}" ]]; then
    detected="$(ls /sys/class/net | grep -v '^lo$' | head -n 1 || true)"
  fi

  [[ -n "${detected}" ]] || die "Could not auto-detect network interface. Use --iface."

  NIX_IFACE="${detected}"
  log "Auto-detected network interface: ${NIX_IFACE}"
}

get_ssh_key_source_label() {
  if [[ "${SSH_KEY_STDIN}" == "true" ]]; then
    echo "stdin"
  elif [[ -n "${SSH_KEY_URL}" ]]; then
    echo "${SSH_KEY_URL}"
  else
    echo "${SSH_KEY_FILE}"
  fi
}

show_plan() {
  echo
  echo "============================================================"
  echo "NixOS Bootstrap Install Plan"
  echo "============================================================"
  echo "Target disk:       ${NIX_DISK}"
  echo "Boot mode:         ${BOOT_MODE}"
  echo "Mount point:       ${MOUNT_POINT}"
  echo
  echo "Hostname:          ${NIX_HOST}"
  echo "User:              ${NIX_USER}"
  echo "Default password:  changeme"
  echo
  echo "Network iface:     ${NIX_IFACE}"
  echo "Static IP:         ${NIX_IP}/${NIX_PREFIX}"
  echo "Gateway:           ${NIX_GATEWAY}"
  echo "DNS:               ${NIX_DNS}"
  echo
  echo "Timezone:          ${TIMEZONE}"
  echo "Locale:            ${LOCALE}"
  echo "stateVersion:      ${STATE_VERSION}"
  echo
  echo "SSH key source:    $(get_ssh_key_source_label)"
  echo
  echo "WARNING:"
  echo "  All data on ${NIX_DISK} will be destroyed."
  echo "============================================================"
  echo
}

confirm_disk() {
  show_plan

  log "Current block devices:"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL,MODEL

  echo

  if [[ "${SSH_KEY_STDIN}" == "true" ]]; then
    warn "--ssh-key-stdin is used, so interactive disk confirmation is skipped."
    warn "Proceeding because --yes-i-really-mean-it was specified."
    return
  fi

  read -r -p "Type the exact target disk path to continue (${NIX_DISK}): " typed

  if [[ "${typed}" != "${NIX_DISK}" ]]; then
    die "Confirmation mismatch. Aborted."
  fi
}

unmount_existing_mounts() {
  log "Unmounting existing mounts under ${MOUNT_POINT}, if any"

  if mountpoint -q "${MOUNT_POINT}/boot"; then
    umount -R "${MOUNT_POINT}/boot" || true
  fi

  if mountpoint -q "${MOUNT_POINT}"; then
    umount -R "${MOUNT_POINT}" || true
  fi
}

partition_suffix() {
  local disk="$1"
  if [[ "${disk}" =~ [0-9]$ ]]; then
    echo "p"
  else
    echo ""
  fi
}

partition_disk() {
  local suffix
  suffix="$(partition_suffix "${NIX_DISK}")"

  if [[ "${BOOT_MODE}" == "efi" ]]; then
    EFI_PART="${NIX_DISK}${suffix}1"
    ROOT_PART="${NIX_DISK}${suffix}2"
  else
    BIOS_PART="${NIX_DISK}${suffix}1"
    ROOT_PART="${NIX_DISK}${suffix}2"
  fi

  log "Wiping disk signatures: ${NIX_DISK}"
  wipefs -af "${NIX_DISK}" || true
  sgdisk --zap-all "${NIX_DISK}" || true

  log "Creating GPT partition table"

  if [[ "${BOOT_MODE}" == "efi" ]]; then
    log "Creating EFI partition: ${EFI_PART}"
    sgdisk -n 1:0:+512M -t 1:EF00 -c 1:EFI "${NIX_DISK}"

    log "Creating root partition: ${ROOT_PART}"
    sgdisk -n 2:0:0 -t 2:8300 -c 2:NIXOS_ROOT "${NIX_DISK}"
  else
    log "Creating BIOS boot partition: ${BIOS_PART}"
    sgdisk -n 1:0:+1M -t 1:EF02 -c 1:BIOS_BOOT "${NIX_DISK}"

    log "Creating root partition: ${ROOT_PART}"
    sgdisk -n 2:0:0 -t 2:8300 -c 2:NIXOS_ROOT "${NIX_DISK}"
  fi

  partprobe "${NIX_DISK}" || true
  udevadm settle || true
  sleep 1

  log "Partition result:"
  lsblk "${NIX_DISK}"
}

format_partitions() {
  log "Formatting root partition: ${ROOT_PART}"
  mkfs.ext4 -F -L nixos "${ROOT_PART}"

  if [[ "${BOOT_MODE}" == "efi" ]]; then
    log "Formatting EFI partition: ${EFI_PART}"
    mkfs.fat -F 32 -n BOOT "${EFI_PART}"
  fi
}

mount_partitions() {
  log "Mounting root partition to ${MOUNT_POINT}"
  mkdir -p "${MOUNT_POINT}"
  mount "${ROOT_PART}" "${MOUNT_POINT}"

  if [[ "${BOOT_MODE}" == "efi" ]]; then
    log "Mounting EFI partition to ${MOUNT_POINT}/boot"
    mkdir -p "${MOUNT_POINT}/boot"
    mount "${EFI_PART}" "${MOUNT_POINT}/boot"
  fi
}

fetch_public_keys() {
  local tmp
  tmp="$(mktemp)"

  if [[ -n "${SSH_KEY_URL}" ]]; then
    log "Fetching public SSH keys from: ${SSH_KEY_URL}"
    curl -fsSL "${SSH_KEY_URL}" -o "${tmp}"

  elif [[ -n "${SSH_KEY_FILE}" ]]; then
    log "Reading public SSH keys from file: ${SSH_KEY_FILE}"
    [[ -f "${SSH_KEY_FILE}" ]] || die "SSH key file not found: ${SSH_KEY_FILE}"
    cp "${SSH_KEY_FILE}" "${tmp}"

  elif [[ "${SSH_KEY_STDIN}" == "true" ]]; then
    log "Reading public SSH keys from stdin"
    cat > "${tmp}"

  else
    rm -f "${tmp}"
    die "No SSH key source specified"
  fi

  if [[ ! -s "${tmp}" ]]; then
    rm -f "${tmp}"
    die "No SSH public keys found"
  fi

  local cleaned
  cleaned="$(mktemp)"

  grep -E '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+)[[:space:]]+' "${tmp}" > "${cleaned}" || true
  rm -f "${tmp}"

  if [[ ! -s "${cleaned}" ]]; then
    rm -f "${cleaned}"
    die "No valid SSH public keys found"
  fi

  echo "${cleaned}"
}

nix_escape_string() {
  sed 's/\\/\\\\/g; s/"/\\"/g'
}

generate_keys_nix_list() {
  local key_file="$1"

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    local escaped
    escaped="$(printf '%s' "${line}" | nix_escape_string)"
    printf '      "%s"\n' "${escaped}"
  done < "${key_file}"
}

generate_configuration() {
  local key_file="$1"

  log "Generating hardware configuration"
  nixos-generate-config --root "${MOUNT_POINT}"

  local keys_list
  keys_list="$(generate_keys_nix_list "${key_file}")"

  log "Writing ${MOUNT_POINT}/etc/nixos/configuration.nix"

  cat > "${MOUNT_POINT}/etc/nixos/configuration.nix" <<EOF
{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  networking.hostName = "${NIX_HOST}";

  networking.useDHCP = false;
  networking.interfaces.${NIX_IFACE}.useDHCP = false;
  networking.interfaces.${NIX_IFACE}.ipv4.addresses = [
    {
      address = "${NIX_IP}";
      prefixLength = ${NIX_PREFIX};
    }
  ];
  networking.defaultGateway = "${NIX_GATEWAY}";
  networking.nameservers = [
    "${NIX_DNS}"
  ];

  time.timeZone = "${TIMEZONE}";

  i18n.defaultLocale = "${LOCALE}";

  users.mutableUsers = true;

  users.users.${NIX_USER} = {
    isNormalUser = true;
    description = "${NIX_USER}";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];

    # Temporary default password for local console login.
    # Change it after first login:
    #   passwd
    initialPassword = "changeme";

    openssh.authorizedKeys.keys = [
${keys_list}
    ];
  };

  security.sudo.wheelNeedsPassword = true;

  services.openssh = {
    enable = true;
    settings = {
      PubkeyAuthentication = true;
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
    ];
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    vim
    nano
    gnutar
    gzip
    xz
    unzip
    openssh
    htop
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

EOF

  if [[ "${BOOT_MODE}" == "efi" ]]; then
    cat >> "${MOUNT_POINT}/etc/nixos/configuration.nix" <<EOF
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

EOF
  else
    cat >> "${MOUNT_POINT}/etc/nixos/configuration.nix" <<EOF
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "${NIX_DISK}";

EOF
  fi

  cat >> "${MOUNT_POINT}/etc/nixos/configuration.nix" <<EOF
  system.stateVersion = "${STATE_VERSION}";
}
EOF
}

install_nixos() {
  log "Installing NixOS"
  nixos-install --no-root-passwd --root "${MOUNT_POINT}"
}

show_summary() {
  cat <<EOF

============================================================
NixOS bootstrap installation completed.
============================================================

Target disk:
  ${NIX_DISK}

Boot mode:
  ${BOOT_MODE}

User:
  ${NIX_USER}

Temporary local password:
  changeme

Hostname:
  ${NIX_HOST}

Network:
  Interface: ${NIX_IFACE}
  Address:   ${NIX_IP}/${NIX_PREFIX}
  Gateway:   ${NIX_GATEWAY}
  DNS:       ${NIX_DNS}

SSH:
  Password login: disabled
  Public key login: enabled

Next step:
  reboot

After reboot, try SSH from the host OS:

  ssh ${NIX_USER}@${NIX_IP}

Recommended ~/.ssh/config:

  Host ${NIX_HOST}
    HostName ${NIX_IP}
    User ${NIX_USER}
    IdentityFile ~/.ssh/id_ed25519_nixos
    IdentitiesOnly yes

Important:
  After first login, change the temporary local password:

    passwd

============================================================

EOF
}

main() {
  require_root

  need_cmd curl
  need_cmd grep
  need_cmd awk
  need_cmd sed
  need_cmd ip
  need_cmd lsblk
  need_cmd wipefs
  need_cmd sgdisk
  need_cmd partprobe
  need_cmd udevadm
  need_cmd mkfs.ext4
  need_cmd mkfs.fat
  need_cmd mount
  need_cmd umount
  need_cmd nixos-generate-config
  need_cmd nixos-install

  parse_args "$@"
  validate_args
  detect_boot_mode
  detect_interface
  confirm_disk

  local key_file
  key_file="$(fetch_public_keys)"

  unmount_existing_mounts
  partition_disk
  format_partitions
  mount_partitions
  generate_configuration "${key_file}"
  rm -f "${key_file}"

  install_nixos
  show_summary
}

main "$@"
