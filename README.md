# docker-pve

A Proxmox VE helper that provisions a Debian 13 cloud-image VM pre-loaded with Docker, Dockge, Portainer (CE plus the remote agent on 9001), and Watchtower. An interactive whiptail wizard asks for the VM's basics; everything else is baked into the image before first boot.

Pairs with [qbittorrent-vpn-docker](https://github.com/rob-paprocki/qbittorrent-vpn-docker), a Gluetun-fronted qBittorrent stack designed to live under `/opt/stacks/` on the VM this script creates and be adopted directly by Dockge.

## Prerequisites

* Proxmox VE 8.x or 9.x on an amd64 host (enforced by the script)
* Root shell on the PVE node, not an unprivileged SSH session (the script will warn)
* Outbound HTTPS to:
  * `cloud.debian.org` (Debian 13 qcow2 and SHA512SUMS)
  * `download.docker.com` (Docker apt repo and GPG key)
  * `raw.githubusercontent.com/community-scripts/ProxmoxVE` (the shared `api.func` helpers, pinned by commit; see **Trust model**)
* Host tools: `whiptail`, `curl`, `openssl`, `sha512sum`, `qm`, `pvesm`, `pveversion` (all standard on PVE). `virt-customize` is auto-installed via `libguestfs-tools` on first run.

## One-liner (as root on the PVE host)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/rob-paprocki/docker-pve/main/docker-stack-vm.sh)"
```

Opt out of community-scripts anonymous diagnostics by prefixing `DIAGNOSTICS=no`.

## What you get

| Service               | Image                                              | Port                | Watchtower scope          |
|-----------------------|----------------------------------------------------|---------------------|---------------------------|
| Dockge                | `louislam/dockge:1.5.0`                            | 5001 (HTTP)         | `dockge`                  |
| Watchtower (updater)  | `ghcr.io/nicholas-fedor/watchtower:v1.23.2`        | (none)              | `dockge`                  |
| Watchtower (monitor)  | `ghcr.io/nicholas-fedor/watchtower:v1.23.2`        | (none)              | `portainer` (notify-only) |
| docker-socket-proxy   | `ghcr.io/tecnativa/docker-socket-proxy:0.5.0`      | (none)              | (unscoped, pin manually)  |
| Portainer             | `portainer/portainer-ce:2.45.3`                    | 8000 / 9443 (HTTPS) | `portainer`               |
| Portainer agent       | `portainer/agent:2.45.3`                           | 9001                | `portainer`               |

Two Watchtower instances run on separate schedules. The `scope=dockge` instance auto-updates Dockge and itself nightly at 04:00. Stacks a user later deploys through Dockge are not touched unless they add `com.centurylinklabs.watchtower.scope=dockge` to their own services. The `scope=portainer` instance runs at 05:30 in monitor-only mode: it reports upgrades for Portainer and its agent through the configured notification channel and never applies them, so Portainer version bumps stay a deliberate action. The monitor-only instance talks to the Docker API through `docker-socket-proxy` with `POST=0`, so even a full compromise there cannot create, stop, or remove containers.

The VM also gets:

* `qemu-guest-agent` installed and `--agent 1` set, so the PVE UI can read the IP and gracefully stop the VM.
* A `deploy` non-root user (uid 1000, in the `docker` group) so stacks that run as `PUID=1000`/`PGID=1000` (such as [qbittorrent-vpn-docker](https://github.com/rob-paprocki/qbittorrent-vpn-docker)) can own `/opt/stacks/*/<data>` directly.
* `/opt/stacks/` pre-populated with `dockge/` and `portainer/`, plus a one-shot `initial-startup.service` that runs `docker compose up -d` for both before deleting itself.

## Options the wizard asks about

**Default** mode prompts for a root password; everything else uses defaults (25 GB disk, 2 cores, 4 GiB RAM, DHCP, i440fx, EFI, VirtIO SCSI, SSH off for root). The Portainer admin password reuses the root password in default mode to avoid a second prompt. **Advanced** mode also asks for:

* VMID, machine type (i440fx or q35, both EFI with a 4 MiB vars store), disk size, hostname
* CPU cores, RAM, bridge, MAC address
* IPv6 on/off (sysctl inside the guest)
* Watchtower notification URL (any shoutrrr URL, e.g. `ntfy://`, `discord://`, `slack://`, `telegram://`, `gotify://`)
* Root password
* Portainer admin password (minimum 12 characters; pre-seeded via `--admin-password-file` so there is no first-boot race window)
* Optional SSH public key for the `deploy` user (and root, if root SSH is enabled)
* Allow root SSH login (defaults to **no**)
* Start VM when done

Static IP is not prompted. The `nocloud` Debian image this script downloads has no cloud-init, and Proxmox's `--ipconfig0` only takes effect through cloud-init, so a static-IP prompt here would silently discard the value. Set an IP reservation on your DHCP server, or edit the VM's network inside the guest post-boot. A cloud-init migration is in the Round-3 backlog.

## Trust model

Three remote inputs are involved. Read each before running this on infrastructure you care about:

1. **This script**, delivered via `curl | bash` or a direct checkout. Pin the ref if you don't want the floating `main`.
2. **`community-scripts/ProxmoxVE/misc/api.func`**, sourced at the top of this script. It provides `post_to_api_vm`, `post_update_to_api`, etc., which POST anonymous counters (OS, action, outcome) to a community telemetry endpoint. Pinned to a specific commit so a change on `main` cannot land silently; the script aborts if the fetch fails. Set `DIAGNOSTICS=no` to disable all uploads at runtime.
3. **Debian 13 `nocloud` qcow2**, verified against the published `SHA512SUMS`. Integrity only, not authenticity: Debian's cloud team does not sign per-distribution images consistently, so GPG verification is deferred. HTTPS to `cloud.debian.org` covers the authenticity leg.

### Container-level residuals

The provisioned VM gives Dockge, the updating Watchtower, Portainer, and the Portainer agent unrestricted access to `/var/run/docker.sock` on the guest, so a compromise of any one is root on the guest. The monitor-only Watchtower is proxied through `docker-socket-proxy` with `POST=0`, which cuts off container create/start/stop even on compromise. The proxy itself carries [CVE-2026-78122](https://app.opencve.io/cve/CVE-2026-78122): GET on `/containers/{id}/archive|export|logs|top` leaks when `CONTAINERS=1`. Fix tracked at [Tecnativa/docker-socket-proxy#183](https://github.com/Tecnativa/docker-socket-proxy/pull/183). The proxy sits on an internal (egressless) bridge, so only `watchtower-portainer` can reach it.

Firewall ports **5001 / 8000 / 9443 / 9001** off the WAN side; put a reverse proxy with auth in front of them if the VM is reachable from untrusted networks.

## Next steps

Once the VM is up:

1. Visit `http://<vm-ip>:5001` and create the Dockge admin.
2. Visit `https://<vm-ip>:9443` and log in to Portainer as `admin` with the password you set in the wizard. The admin account is pre-seeded, so there is no first-boot window to race.
3. Deploy a stack. For the paired VPN'd qBittorrent setup:
   ```bash
   cd /opt/stacks
   git clone https://github.com/rob-paprocki/qbittorrent-vpn-docker.git
   # follow that repo's README to fill in .env, then up it from Dockge or the CLI
   ```

## Round-3 backlog

Items the audit flagged but deferred past Round 2:

* GPG verification of the Debian cloud image (blocked on the Debian Cloud Team signing per-distribution images consistently)
* `docker-socket-proxy` upstream fix for [CVE-2026-78122](https://app.opencve.io/cve/CVE-2026-78122) (Tecnativa PR #183)
* genericcloud + cloud-init to restore a working static-IP prompt
* arm64 support
* SECURITY.md, CODEOWNERS, PR templates

## License

MIT (see `LICENSE`). The whiptail UI pattern, `get_valid_nextid` helper, and `api.func` sourcing are adapted from the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) project, copyright © 2021-2025 community-scripts ORG. All additions in this script are copyright © 2025 Rob Paprocki.
