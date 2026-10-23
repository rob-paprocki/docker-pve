# docker-pve

A Proxmox VE helper that provisions a Debian 13 cloud-image VM pre-loaded with Docker, **Dockge**, **Portainer** (CE + remote agent on 9001), and **Watchtower**. An interactive whiptail wizard asks for the VM's basics; everything else is baked into the image before first boot.

Pairs with [qbittorrent-vpn-docker](https://github.com/rob-paprocki/qbittorrent-vpn-docker) — a Gluetun-fronted qBittorrent stack designed to live under `/opt/stacks/` on the VM this script creates and be adopted directly by Dockge.

## Prerequisites

* Proxmox VE 8.x or 9.x on an amd64 host (enforced by the script)
* Root shell on the PVE node (not an unprivileged SSH session — the script will warn)
* Outbound HTTPS to:
  * `cloud.debian.org` (Debian 13 qcow2)
  * `download.docker.com` (Docker apt repo and GPG key)
  * `raw.githubusercontent.com/community-scripts/ProxmoxVE` (the shared `api.func` helpers — see **Trust model** below)
* Host tools: `whiptail`, `curl`, `openssl`, `qm`, `pvesm`, `pveversion` (all standard on PVE). `virt-customize` is auto-installed via `libguestfs-tools` on first run.

## One-liner (as root on the PVE host)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/rob-paprocki/docker-pve/main/docker-stack-vm.sh)"
```

Opt out of community-scripts anonymous diagnostics by prefixing `DIAGNOSTICS=no`.

## What you get

| Service    | Image                                 | Port                | Default scope label                 |
|------------|---------------------------------------|---------------------|-------------------------------------|
| Dockge     | `louislam/dockge:1.5.0`               | 5001 (HTTP)         | `watchtower.scope=dockge`           |
| Watchtower | `containrrr/watchtower:1.7.1`         | —                   | `watchtower.scope=dockge`           |
| Portainer  | `portainer/portainer-ce:2.45.3`       | 8000 / 9443 (HTTPS) | (unscoped — bump manually)          |
| Agent      | `portainer/agent:2.45.3`              | 9001                | (unscoped)                          |

Watchtower runs on a cron (daily at 04:00) and only touches containers it manages — the scope filter is set to `dockge`, and only the Dockge + Watchtower containers carry that label. Stacks a user later deploys through Dockge are not auto-updated unless they add the label themselves. **Portainer and its agent are intentionally not auto-updated** — Portainer version bumps are a deliberate action, not a 04:00 surprise.

The VM also gets:
* `qemu-guest-agent` installed and `--agent 1` set, so the PVE UI can read the IP and gracefully stop the VM
* A `deploy` non-root user (uid 1000, in the `docker` group) so stacks that run as `PUID=1000`/`PGID=1000` (e.g. [qbittorrent-vpn-docker](https://github.com/rob-paprocki/qbittorrent-vpn-docker)) can own `/opt/stacks/*/<data>` directly
* `/opt/stacks/` pre-populated with `dockge/` and `portainer/`, and a one-shot `initial-startup.service` that runs `docker compose up -d` for both before deleting itself

## Options the wizard asks about

**Default** mode just prompts for a root password; everything else uses defaults (25 GB disk, 2 cores, 4 GiB RAM, DHCP, i440fx, EFI, VirtIO SCSI, SSH off for root). **Advanced** mode also asks for:

* VMID, machine type (i440fx or q35, both EFI with a 4 MiB vars store), disk size, hostname
* CPU cores, RAM, bridge, MAC address
* IPv6 on/off (sysctl inside the guest)
* Watchtower notification URL (any shoutrrr URL — `discord://…`, `slack://…`, `telegram://…`, `gotify://…`)
* Root password
* Allow root SSH login? (defaults to **no**)
* Start VM when done?

Static IP is **not** prompted. The `nocloud` Debian image this script downloads has no cloud-init, and Proxmox's `--ipconfig0` only takes effect through cloud-init — so a static-IP prompt here would silently discard the value. Set an IP reservation on your DHCP server, or edit the VM's network inside the guest post-boot.

## Trust model

Three remote inputs are involved. Read each before running this on infrastructure you care about:

1. **This script**, delivered to you via `curl | bash` or a direct checkout. Pin the ref if you don't want the floating `main`.
2. **`community-scripts/ProxmoxVE/main/misc/api.func`**, sourced at the top of this script. It provides `post_to_api_vm`, `post_update_to_api`, etc., which POST anonymous counters (OS, action, outcome) to a community telemetry endpoint. The script now aborts if the fetch fails. Set `DIAGNOSTICS=no` to disable all uploads at runtime.
3. **Debian 13 `nocloud` qcow2**, downloaded without SHA512 or signature verification (planned for a future revision). Trust depends on HTTPS to `cloud.debian.org` and the Debian CDN.

The provisioned VM gives three containers (Dockge, Portainer, Watchtower) unrestricted access to `/var/run/docker.sock` on the guest — compromise of any of them is root on the guest. Firewall ports **5001 / 8000 / 9443 / 9001** off the WAN side; put a reverse proxy with auth in front of them if the VM is reachable from untrusted networks.

## Next steps

Once the VM is up:
1. Visit `http://<vm-ip>:5001`, create the Dockge admin.
2. Visit `https://<vm-ip>:9443`, create the Portainer admin **within 5 minutes of first boot** (Portainer self-locks that admin-provisioning window).
3. Deploy a stack. If you want the paired VPN'd qBittorrent setup:
   ```bash
   cd /opt/stacks
   git clone https://github.com/rob-paprocki/qbittorrent-vpn-docker.git
   # follow that repo's README to fill in .env, then up it from Dockge or the CLI
   ```

## Deferred (follow-up work the audit flagged)

* SHA512 / GPG verification of the Debian cloud image
* Pin `api.func` by git ref instead of tracking `main`
* Portainer admin password pre-seed (close the 5-minute race window)
* Optional SSH public-key injection
* Shellcheck CI
* Prompt for a static IP via genericcloud + cloud-init drive
* arm64 support

## License

MIT (see `LICENSE`). The whiptail UI pattern, `get_valid_nextid` helper, and `api.func` sourcing are adapted from the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) project — copyright © 2021-2025 community-scripts ORG. All additions in this script are copyright © 2025 Rob Paprocki.
