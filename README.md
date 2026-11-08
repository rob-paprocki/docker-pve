# docker-pve

A Proxmox VE helper that provisions a Debian 13 cloud-image VM pre-loaded with Docker and [Dockhand](https://dockhand.pro), which manages the containers and keeps their images updated. [Dockge](https://github.com/louislam/dockge) is available as an optional secondary compose UI. An interactive whiptail wizard asks for the VM's basics; everything else is baked into the image before first boot, and Dockhand is configured and locked down on first boot before it is reachable from the network.

Pairs with [qbittorrent-vpn-docker](https://github.com/rob-paprocki/qbittorrent-vpn-docker), a Gluetun-fronted qBittorrent stack designed to live under `/opt/stacks/` on the VM this script creates.

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

| Service             | Image                       | Port        | Role                                         |
|---------------------|-----------------------------|-------------|----------------------------------------------|
| Dockhand            | `fnsys/dockhand:v1.0.57`    | 3000 (HTTP) | Docker manager and image updater             |
| Dockge (optional)   | `louislam/dockge:1.5.0`     | 5001 (HTTP) | Secondary compose UI; Advanced settings only |

Dockhand lives in `/opt/dockhand` and manages the stacks in `/opt/stacks`. On first boot it is set up with:

* the VM's local Docker socket as its environment;
* `/opt/stacks` as the folder it scans for stacks, and the stacks folder for stacks you create in Dockhand, so Dockhand, Dockge and the CLI all work on the same `compose.yaml` files in place;
* a nightly update at 04:00 (host timezone): every container is checked for a newer image and updated, unless the new image has more known vulnerabilities than the one it replaces, in which case the update is blocked and reported. Containers that share another container's network (the paired stack's qBittorrent shares Gluetun's) are reconnected when their parent is updated;
* an optional notification channel for update results (succeeded, failed, blocked);
* an `admin` account, with authentication on.

Dockhand does not update itself on that schedule. It shows a new release in its sidebar and updates itself when you click it; afterwards, set the new tag in `/opt/dockhand/compose.yaml` so a later `docker compose up -d` there doesn't roll it back.

There is no Watchtower and no Portainer. Dockhand covers both: image updates, plus container, image, volume and network management.

The VM also gets:

* `qemu-guest-agent` installed and `--agent 1` set, so the PVE UI can read the IP and gracefully stop the VM.
* A `deploy` non-root user (uid 1000, in the `docker` group) so stacks that run as `PUID=1000`/`PGID=1000` (such as [qbittorrent-vpn-docker](https://github.com/rob-paprocki/qbittorrent-vpn-docker)) can own `/opt/stacks/*/<data>` directly.
* A first-boot `initial-startup.service` that starts Dockhand (and Dockge, if chosen), configures Dockhand, and disables itself once it succeeds.
* `git` and `python3-venv`, so the paired stack can be cloned and its host-side setup editor (`scripts/setup.sh`) can build its Python venv. The Debian 13 `nocloud` image ships `python3` but neither of these.

## Options the wizard asks about

**Default** mode prompts for a root password (8+ characters); everything else uses defaults (25 GB disk, 2 cores, 4 GiB RAM, DHCP, i440fx, EFI, VirtIO SCSI, SSH off for root, no Dockge, no notifications). The Dockhand `admin` password reuses the root password in default mode to avoid a second prompt. **Advanced** mode also asks for:

* VMID, machine type (i440fx or q35, both EFI with a 4 MiB vars store), disk size, hostname
* CPU cores, RAM, bridge, MAC address
* IPv6 on/off (sysctl inside the guest)
* Notification URL for Dockhand's update results, in Dockhand's Apprise-style format, e.g. `ntfys://ntfy.example.com/updates`, `discord://webhook_id/webhook_token`, `tgram://bot_token/chat_id`, `gotify://host/token`, `pover://user_key@api_token`. These differ from the Shoutrrr URLs earlier versions passed to Watchtower.
* Root password
* Dockhand `admin` password (minimum 8 characters, Dockhand's own limit)
* Whether to also install Dockge (defaults to **no**)
* Optional SSH public key for the `deploy` user (and root, if root SSH is enabled)
* Allow root SSH login (defaults to **no**)
* Start VM when done

Static IP is not prompted. The `nocloud` Debian image this script downloads has no cloud-init, and Proxmox's `--ipconfig0` only takes effect through cloud-init, so a static-IP prompt here would silently discard the value. Set an IP reservation on your DHCP server, or edit the VM's network inside the guest post-boot. A cloud-init migration is in the Round-3 backlog.

## Trust model

Three remote inputs are involved. Read each before running this on infrastructure you care about:

1. **This script**, delivered via `curl | bash` or a direct checkout. Pin the ref if you don't want the floating `main`.
2. **`community-scripts/ProxmoxVE/misc/api.func`**, sourced at the top of this script. It provides `post_to_api_vm`, `post_update_to_api`, etc., which POST anonymous counters (OS, action, outcome) to a community telemetry endpoint. Pinned to a specific commit so a change on `main` cannot land silently; the script aborts if the fetch fails. Set `DIAGNOSTICS=no` to disable all uploads at runtime.
3. **Debian 13 `nocloud` qcow2**, verified against the published `SHA512SUMS`. Integrity only, not authenticity: Debian's cloud team does not sign per-distribution images consistently, so GPG verification is deferred. HTTPS to `cloud.debian.org` covers the authenticity leg.

### First-boot lock-down

Dockhand starts with authentication off and lets whoever reaches it first create the admin account. `initial-startup.service` therefore publishes Dockhand on `127.0.0.1` only, configures it and creates the `admin` account through its API, enables authentication, and republishes it on port 3000 only after an anonymous API request is refused. The admin password and notification URL wait in `/opt/dockhand_secrets` (0700, files 0600) and are deleted once that succeeds.

If any step fails, Dockhand stays on `127.0.0.1`, the secrets stay in place, and the service runs again on the next boot. Check `journalctl -u initial-startup` on the VM.

### Container-level residuals

Dockhand, and Dockge when installed, have unrestricted access to `/var/run/docker.sock` on the guest, so a compromise of either is root on the guest. Dockhand also runs as root inside its container (its default).

The nightly update pulls new images automatically. Blocking updates that add known vulnerabilities does not catch a malicious image with no known CVEs.

Dockhand is source-available under the Business Source License 1.1, not open source. Each version converts to Apache 2.0 four years after release, and its pricing page sells a separate commercial-use license.

Dockhand and Dockge serve plain HTTP, so the Dockhand password crosses the network in the clear. Firewall ports **3000** (and **5001** with Dockge) off the WAN side, and put a TLS reverse proxy in front of them if the VM is reachable from untrusted networks.

## Next steps

Once the VM is up:

1. Visit `http://<vm-ip>:3000` and log in as `admin` with the password you set in the wizard (the root password in default mode). Everything listed under **What you get** is already configured. If the page doesn't load a few minutes after first boot, run `journalctl -u initial-startup` on the VM.
2. If you installed Dockge, visit `http://<vm-ip>:5001` and create the Dockge admin. Use it for reading logs and editing files: its Start, Update and Deploy buttons run Dockge's bundled Docker Compose (v2.34.0), whose config hashes differ from the VM's, so they recreate every container in the stack.
3. Deploy a stack. For the paired VPN'd qBittorrent setup:
   ```bash
   cd /opt/stacks
   git clone https://github.com/rob-paprocki/qbittorrent-vpn-docker.git torrent-stack
   cd torrent-stack
   # follow that repo's README: ./scripts/setup.sh serves the env-editor on :9191
   ```
   Then pick it up in Dockhand under **Stacks → Adopt**. Dockhand names the stack `torrent-stack` from its compose file. Clone into a `torrent-stack` folder anyway: Dockge names stacks after their folder and shows the stack twice when the two names differ.

## Round-3 backlog

Items the audit flagged but deferred past Round 2:

* GPG verification of the Debian cloud image (blocked on the Debian Cloud Team signing per-distribution images consistently)
* genericcloud + cloud-init to restore a working static-IP prompt
* arm64 support
* SECURITY.md, CODEOWNERS, PR templates

## License

MIT (see `LICENSE`). The whiptail UI pattern, `get_valid_nextid` helper, and `api.func` sourcing are adapted from the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) project, copyright © 2021-2025 community-scripts ORG. All additions in this script are copyright © 2025 Rob Paprocki.
