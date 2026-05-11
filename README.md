# nixos-vm-setup-public

Public bootstrap scripts and reusable templates for setting up reproducible NixOS development VMs.

> 日本語版はこちら: [README.ja.md](./README.ja.md)

## Overview

This repository provides public bootstrap scripts for installing and preparing NixOS-based virtual machines.

The main script, `bootstrap-install.sh`, is intended to be executed from the NixOS Live ISO environment. It performs a minimal first-stage installation of NixOS so that the VM can be accessed via SSH after reboot.

This repository is designed to contain only public and reusable setup logic.

Sensitive information such as private repository URLs, access tokens, age keys, private SSH keys, machine-specific secrets, and personal configuration should be managed outside of this repository.

## Main Script

### `bootstrap-install.sh`

`bootstrap-install.sh` is a first-stage NixOS installer script.

It performs the following tasks:

- Validates required installation parameters
- Detects EFI or BIOS boot mode
- Detects or accepts the network interface name
- Partitions the specified target disk
- Formats the root partition
- Formats and mounts the EFI partition when using EFI boot
- Generates the initial NixOS hardware configuration
- Writes a minimal `configuration.nix`
- Creates a normal user
- Enables SSH public key authentication
- Disables SSH password login
- Installs NixOS using `nixos-install`

After installation and reboot, the VM should be reachable from the host machine via SSH.

## Intended Usage

This script is intended for virtual machine environments such as:

- UTM
- Proxmox
- Local development VMs
- Disposable NixOS test environments
- Reproducible development environments

It may also work in other environments, but the primary target is NixOS VM setup.

## Installation Flow

The intended setup flow is:

```text
NixOS Live ISO
  ↓
Run bootstrap-install.sh
  ↓
Partition and format target disk
  ↓
Generate minimal NixOS configuration
  ↓
Run nixos-install
  ↓
Reboot
  ↓
Connect via SSH
  ↓
Continue with private configuration, flakes, or other provisioning steps
```

This repository handles only the public first-stage installation flow.

Private configuration and secrets should be handled in a separate private repository or by another secure provisioning process.

## Warning

> [!WARNING]
> This script performs destructive disk operations.

`bootstrap-install.sh` partitions and formats the specified target disk.

All existing data on the target disk will be destroyed.

Always verify the target disk before running the script.

Example target disks:

```text
/dev/sda
/dev/vda
/dev/nvme0n1
```

Use `lsblk` to confirm the correct disk before installation.

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL,MODEL
```

## Requirements

The script is intended to be run from the NixOS Live ISO environment.

Required commands include:

- `bash`
- `curl`
- `ip`
- `lsblk`
- `sgdisk`
- `wipefs`
- `partprobe`
- `udevadm`
- `mkfs.ext4`
- `mkfs.fat`
- `mount`
- `umount`
- `nixos-generate-config`
- `nixos-install`

These are expected to be available in the NixOS installer environment.

## Basic Usage

### Example: SSH public key from GitHub

```bash
curl -fsSL https://raw.githubusercontent.com/yasuo-dev/nixos-vm-setup-public/main/scripts/bootstrap-install.sh -o bootstrap-install.sh
chmod +x ./bootstrap-install.sh
sudo bash ./bootstrap-install.sh \
  --user user-dev \
  --host nixos-utm-dev \
  --ip 192.168.64.50 \
  --gateway 192.168.64.1 \
  --dns 1.1.1.1 \
  --disk /dev/vda \
  --ssh-key-url "https://github.com/YOUR_GITHUB_USERNAME.keys" \
  --yes-i-really-mean-it
```

### Example: SSH public key from stdin

```bash
cat ~/.ssh/id_ed25519.pub | ssh nixos@192.168.64.xxx 'sudo bash ./bootstrap-install.sh \
  --user user-dev \
  --host nixos-utm-dev \
  --ip 192.168.64.50 \
  --gateway 192.168.64.1 \
  --dns 1.1.1.1 \
  --disk /dev/vda \
  --ssh-key-stdin \
  --yes-i-really-mean-it'
```

### Example: SSH public key from a local file

```bash
sudo bash ./bootstrap-install.sh \
  --user user-dev \
  --host nixos-utm-dev \
  --ip 192.168.64.50 \
  --gateway 192.168.64.1 \
  --dns 1.1.1.1 \
  --disk /dev/vda \
  --ssh-key-file ./id_ed25519.pub \
  --yes-i-really-mean-it
```

## Options

```text
--user USER                 User account to create
--host HOSTNAME             NixOS hostname
--ip IP_ADDRESS             Static IPv4 address
--gateway GATEWAY           Default gateway
--dns DNS_SERVER            DNS server
--disk DISK                 Target install disk

--ssh-key-url URL           URL to fetch public SSH keys
--ssh-key-file FILE         Local public key file on the NixOS Live environment
--ssh-key-stdin             Read public SSH keys from standard input

--iface IFACE               Network interface name
--prefix PREFIX             IPv4 prefix length. Default: 24
--timezone TIMEZONE         Time zone. Default: Asia/Tokyo
--locale LOCALE             Default locale. Default: en_US.UTF-8
--state-version VERSION     NixOS stateVersion. Default: 25.05
--boot-mode MODE            auto, efi, or bios. Default: auto

--yes-i-really-mean-it      Required confirmation for destructive disk operations
--help                      Show help
```

## Default Configuration

The generated NixOS configuration includes:

- Static IPv4 networking
- OpenSSH enabled
- SSH public key authentication enabled
- SSH password login disabled
- Root SSH login disabled
- Firewall enabled
- TCP port 22 allowed
- A normal user with `wheel` group access
- Temporary local console password: `changeme`
- Basic packages:
  - `git`
  - `curl`
  - `wget`
  - `vim`
  - `nano`
  - `openssh`
  - `htop`
  - archive utilities

Nix experimental features are enabled:

```nix
nix-command
flakes
```

## After Installation

Reboot the VM:

```bash
reboot
```

Then connect from the host OS:

```bash
ssh user-dev@192.168.64.50
```

Example SSH config:

```sshconfig
Host nixos-utm-dev
  HostName 192.168.64.50
  User user-dev
  IdentityFile ~/.ssh/id_ed25519_nixos
  IdentitiesOnly yes
```

After the first login, change the temporary local password:

```bash
passwd
```

## Security Notes

This repository should not contain secrets.

Do not commit:

- Private SSH keys
- GitHub personal access tokens
- age identity keys
- `.env` files
- Private repository URLs
- Production configuration

Recommended separation:

```text
public repository
  bootstrap scripts
  reusable templates

private repository
  actual machine configuration
  private flake
  deployment-specific settings
```

## Repository Scope

This repository is for public bootstrap setup only.

It is not intended to be a complete private NixOS configuration repository.

A typical multi-stage approach is:

```text
Stage 0:
  Boot NixOS Live ISO

Stage 1:
  Run bootstrap-install.sh from this public repository

Stage 2:
  Apply full NixOS configuration using flakes, agenix, sops-nix, or other tools
```

## License

This project is licensed under the MIT License.
