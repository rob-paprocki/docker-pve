# docker-pve

[![Licence: MIT](https://img.shields.io/badge/licence-MIT-0969da)](LICENSE)
[![Latest version, read from CHANGELOG.md](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Frob-paprocki%2Fdocker-pve%2Fmain%2FCHANGELOG.md&search=%23%23%20%5C%5B%28%5Cd%2B%5C.%5Cd%2B%5C.%5Cd%2B%29%5C%5D&replace=%241&label=latest%20version&color=0969da)](CHANGELOG.md)
[![lint workflow status (shellcheck and image checks)](https://github.com/rob-paprocki/docker-pve/actions/workflows/lint.yml/badge.svg)](https://github.com/rob-paprocki/docker-pve/actions/workflows/lint.yml)
[![Proxmox VE 8 or 9](https://img.shields.io/badge/Proxmox%20VE-8%20%7C%209-b35900?logo=proxmox&logoColor=white)](https://pve.proxmox.com/)

docker-pve is a script you run on a Proxmox VE host to create a Debian 13 VM with Docker and [Dockhand](https://dockhand.pro), a web UI for managing Docker, and to configure and password-protect Dockhand before your network can reach it.

It's for people who run Proxmox VE at home or in a small lab and want a VM for Docker Compose stacks without building one by hand each time. By hand, that means creating the VM, installing Docker from Docker's repository, adding a web UI to manage containers, and creating that UI's admin account before anyone else on the network does.

The script asks for the VM's basics in a whiptail wizard and writes everything else into the disk image before the VM first boots. On that first boot, the VM sets Dockhand up. [Dockge](https://github.com/louislam/dockge) is available as an optional second compose UI.

If you only need Docker, community-scripts' own [Docker VM script](https://github.com/community-scripts/ProxmoxVE/blob/main/vm/docker-vm.sh) builds a plain Docker VM on Debian or Ubuntu, with optional cloud-init. This one is narrower (Debian 13 only, no cloud-init) and adds Dockhand.

It pairs with [qbittorrent-vpn-docker](https://github.com/rob-paprocki/qbittorrent-vpn-docker), a qBittorrent stack behind a Gluetun VPN container. That stack is designed to live under `/opt/stacks/` on the VM this script creates.

**Contents:** [Quick start](#quick-start) · [How it works](#how-it-works) · [Configuration](#configuration) · [What the VM contains](#what-the-vm-contains) · [Security](#trust-model-and-security) · [FAQ](#troubleshooting-and-faq)

## Highlights

- **Dockhand is password-protected before port 3000 opens.** First boot creates Dockhand's `admin` account and turns its login on while Dockhand listens only on `127.0.0.1`, then publishes it on port 3000. If a required step fails, Dockhand stays on `127.0.0.1` and setup runs again on the next boot.
- **Nothing left to install.** Docker, the packages and the first-boot service go into Debian's official cloud image before the VM starts.
- **Containers kept up to date.** Every night at 04:00, host time, Dockhand updates the containers' images, but blocks an update whose new image has more known vulnerabilities than the running one. It can send the results to a notification channel. Debian's own packages are [up to you](#troubleshooting-and-faq).
- **Careful with secrets and remote code.** Passwords never go on a command line, and their first-boot copies are deleted once setup succeeds. The community-scripts helper file is pinned by commit, and the Dockhand and Dockge images by tag.
- **Ready for the paired stack.** A `deploy` user with uid and gid 1000 in the `docker` group, plus `git` and `python3-venv`.

## Quick start

### Requirements

- **Proxmox VE** 8.0 to 8.9 or 9.0 to 9.9, on an amd64 host. The script exits on any other version or architecture.
- **A root shell** on the Proxmox node. The script refuses to run as another user or through `sudo`. Over SSH it asks you to confirm and suggests the Proxmox web shell instead.
- **Storage** that accepts VM disk images. If there are several, the script asks which one to use. It needs room for the VM's disk (25 GiB by default).
- **Free space in the host's temporary folder** (`/tmp`, or `$TMPDIR` if set). It holds the Debian image, about 400 MB to download and bigger once packages are installed, and a resized copy of it.
- **Host network:** outbound HTTPS to `raw.githubusercontent.com` (this script and `api.func`), `cloud.debian.org` (the image and `SHA512SUMS`; it redirects the image download to a mirror), and `download.docker.com` and the Debian package mirrors (packages installed into the image). If the script has to install `libguestfs-tools`, it also needs the host's own apt repositories.
- **VM network:** a DHCP server on the VM's bridge, and access to Docker Hub on first boot to pull the Dockhand image (and Dockge's).
- **Host tools:** `whiptail`, `curl`, `openssl`, `sha512sum`, `qemu-img`, `qm`, `pvesm`, `pvesh` and `pveversion`, all standard on Proxmox VE. If `virt-customize` is missing, the script installs `libguestfs-tools` first.

### Run it

As root on the Proxmox host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/rob-paprocki/docker-pve/main/docker-stack-vm.sh)"
```

Confirm the first prompt, then answer **Yes** to "Use Default Settings?" for a VM with the [defaults](#wizard-options) and a single password prompt, or choose **Advanced** to set everything yourself.

> [!CAUTION]
> This runs a script from the internet as root on your Proxmox host, and that script sources a second file, `api.func`, from the community-scripts/ProxmoxVE repository. Read both before you run them on a host you care about ([trust model](#trust-model-and-security)). To run a fixed version instead of the moving `main` branch, replace `main` in the URL with a commit SHA. Release tags aren't published yet.

### After it finishes

1. Find the VM's IP address on its **Summary** tab in Proxmox (the guest agent reports it). Give first boot a few minutes to pull the Dockhand image and configure it before port 3000 opens.
2. Open `http://<vm-ip>:3000` and log in as `admin` with the Dockhand password you set in the wizard (in Default mode, the root password). Everything under [Dockhand's first-boot setup](#dockhands-first-boot-setup) is already done. If the page doesn't load, see "Dockhand's page doesn't load after first boot" in [the FAQ](#troubleshooting-and-faq).
3. If you installed Dockge, open `http://<vm-ip>:5001` and create its admin account. Use Dockge to read logs and edit files, not to start or update stacks ([the FAQ](#troubleshooting-and-faq) says why).

> [!IMPORTANT]
> Dockge gets none of the first-boot lock-down. First boot publishes it on port 5001 straight away, before Dockhand, and the first person to open it creates its admin account, so do step 3 as soon as you can.

4. Deploy a stack. For the paired qBittorrent stack, follow its [Setup](https://github.com/rob-paprocki/qbittorrent-vpn-docker#setup) as root on the VM. It clones the stack into `/opt/stacks/torrent-stack`, prepares its folders for uid 1000 and starts its setup editor on port 9191. Then adopt the stack in Dockhand as its [docker-pve section](https://github.com/rob-paprocki/qbittorrent-vpn-docker#deploy-on-the-paired-docker-pve-vm-dockhand) describes. Keep the `torrent-stack` folder name: Dockge names stacks after their folder and shows the stack twice when that differs from the compose project name.

## How it works

The script does all its work on the Proxmox host, on a downloaded copy of Debian's disk image. The VM then finishes the job on its first boot.

![Flowchart of what docker-stack-vm.sh does on the Proxmox host, in five steps. First it fetches api.func, asks to proceed, and checks for root, amd64, Proxmox VE 8 or 9, and an SSH session. Then the wizard runs, Default or Advanced, and asks for the storage pool. Next the script downloads the Debian 13 nocloud image and checks it against SHA512SUMS. virt-customize writes the root password, packages, the deploy user, compose files, secrets, initial-startup.service and Docker CE into the image. Last, virt-resize sets the image to your disk size, qm create makes the VM, the disk is imported, and the VM starts if you chose that.](docs/images/how-it-works-host.svg)

On the host, the script:

1. Fetches `api.func`, asks you to confirm, and checks for root, amd64 and Proxmox VE 8 or 9. Over SSH it asks you to confirm again.
2. Runs the wizard, then asks which storage pool to use if there's a choice.
3. Downloads Debian's official 13 (trixie) `nocloud` cloud image, the variant without cloud-init, and checks it against Debian's `SHA512SUMS`.
4. Uses `virt-customize` to write the root password, packages, `deploy` user, compose files, secrets and `initial-startup.service` into the image, and to install Docker CE and the Compose plugin from Docker's own apt repository.
5. Resizes the image to your disk size, creates the VM, imports the disk and, if you chose to, starts the VM.

![Flowchart of the first boot in the VM, run by initial-startup.service. It starts Dockge on port 5001 if you chose it, then starts Dockhand on 127.0.0.1 port 3000 and waits for its API. Then comes a question. Does Dockhand refuse an anonymous API request? No means it isn't set up yet, so the unit configures it through the API (Docker environment, /opt/stacks, 04:00 updates, notifications, adopting existing stacks), then creates the admin account and turns authentication on. Yes means an earlier boot already did this. Either way, the same question comes again. Does Dockhand refuse an anonymous API request now? If yes, the unit republishes Dockhand on port 3000, deletes the secrets and disables itself. If no, or if a required call failed during setup, it exits with an error, Dockhand stays on 127.0.0.1, and the unit runs again on the next boot.](docs/images/how-it-works-vm.svg)

On first boot, `initial-startup.service`:

1. Starts Dockge if you chose it, then Dockhand on `127.0.0.1` only. Docker pulls each image as it starts.
2. Configures Dockhand through its API and creates the `admin` account, turning authentication on last. It skips this when Dockhand already refuses anonymous requests, because an earlier boot got that far.
3. Publishes Dockhand on port 3000, deletes the secrets and disables itself, but only once Dockhand refuses an anonymous request. If that check or a required call fails, it exits with an error, leaves Dockhand on `127.0.0.1`, and runs again on the next boot.

[First-boot lock-down](#first-boot-lock-down) explains why it works this way.

## Configuration

### Wizard options

After a first "Proceed?" confirmation, the wizard asks "Use Default Settings?".

- **Default** asks only for the root password and uses the values in the table.
- **Advanced** asks for every setting, in the table's order, with those values filled in as defaults, except that the Dockhand password gets its own prompt. Then it asks "Ready to create the VM?", and **Do-Over** there starts the questions again.

| Setting | Default |
|---|---|
| VM ID | Next free ID |
| Machine type | i440fx |
| Disk size | 25 GiB |
| Hostname | `docker` |
| CPU cores | 2 |
| RAM | 4096 MiB |
| Bridge | `vmbr0` |
| MAC address | Random, `02:…` |
| IPv6 | On |
| Notification URL | None |
| Root password | Asked |
| Dockhand password | The root password |
| Install Dockge | No |
| SSH key for `deploy` | None |
| Root SSH login | Off |
| Start VM when done | Yes |

What the prompts accept:

- **VM ID:** an ID already in use is refused and asked again.
- **Machine type:** i440fx or q35. Both boot with UEFI.
- **Disk size:** in GiB, as `40G` or a plain number such as `40`. Any other format stops the script.
- **Hostname:** converted to lower case with spaces removed.
- **MAC address:** a locally administered random one is filled in; blank also means that one.
- **IPv6:** No writes a sysctl file that turns IPv6 off in the guest.
- **Notification URL:** optional. An Apprise-style URL for Dockhand's update results ([formats](#troubleshooting-and-faq)).
- **Root password:** required. In Default mode it must be at least 8 characters, because it's also the Dockhand password.
- **Dockhand `admin` password:** asked separately in Advanced mode; at least 8 characters, Dockhand's own minimum.
- **SSH public key for `deploy`:** optional. It must start with an OpenSSH key type such as `ssh-ed25519`; anything else is dropped with a message.
- **Root SSH login:** Yes sets `PermitRootLogin yes` and, if you gave a key, adds it for root too.

In both modes the script then asks which storage pool to use, if more than one accepts disk images.

Neither mode asks for a static IP, so the VM always starts on DHCP. [The FAQ](#troubleshooting-and-faq) explains why and what to do instead.

These settings are the same in both modes:

- **Firmware:** UEFI (OVMF) with a 4 MiB EFI vars disk.
- **Disk controller:** VirtIO SCSI. On storage other than directory, NFS or Btrfs, the disk also gets `discard=on,ssd=1`.
- **Network:** a VirtIO NIC on the chosen bridge, DHCP, no VLAN tag or MTU. Set those on the VM's network device in Proxmox if you need them.
- **Guest agent:** installed in the guest and enabled on the VM.
- **Start at host boot:** on.
- **Serial console:** a `serial0` socket.
- **Tags:** `docker`, `dockhand`, `debian13`, and `dockge` when installed.
- **Timezone:** Dockhand, Dockge and the update schedule use the Proxmox host's timezone. The guest system's own timezone is left as the image ships it. The script uses `Etc/UTC` instead if it can't read the host's timezone, or if the name has a digit or no `/` (such as `Etc/GMT+5` or `GMT`; plain `UTC` is accepted).
- **Notes:** the VM's Notes panel links to `http://<hostname>:3000` (and `:5001` with Dockge).

### Environment variables

The script reads these from its environment. Put them before `bash` in the one-liner:

```bash
DIAGNOSTICS=no DOCKHAND_IMAGE=registry.example.lan/fnsys/dockhand \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/rob-paprocki/docker-pve/main/docker-stack-vm.sh)"
```

- **`DIAGNOSTICS`**, default unset, which `api.func` treats as `no`. Read by the sourced `api.func`, not by this script. "How do I turn off diagnostics?" in [the FAQ](#troubleshooting-and-faq) explains when anything is uploaded.
- **`API_FUNC_REF`**, default `500a860faf7295e6dad20670d05e6400d18f66b0`. The [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) commit whose `misc/api.func` is fetched and sourced. The script exits if the fetch fails or comes back empty.
- **`DOCKHAND_IMAGE`**, default `fnsys/dockhand`. The Dockhand image written into `/opt/dockhand/compose.yaml`, without the tag. Point it at a copy in your own registry if the VM can't reach Docker Hub.
- **`DOCKHAND_TAG`**, default `v1.0.57`. The Dockhand image tag. First boot configures Dockhand through its HTTP API, so a tag that changes that API makes first boot fail, and Dockhand then stays on `127.0.0.1`.
- **`DOCKGE_TAG`**, default `1.5.0`. The `louislam/dockge` image tag, used only when you install Dockge.

## What the VM contains

- **Dockhand** (`fnsys/dockhand:v1.0.57`), the Docker manager and image updater. Port 3000 (HTTP), folder `/opt/dockhand`.
- **Dockge** (`louislam/dockge:1.5.0`), optional, a second compose UI. Port 5001 (HTTP), folder `/opt/stacks/dockge`. Advanced mode only.

The VM also gets:

- Docker CE (`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-compose-plugin`) from Docker's Debian repository.
- `qemu-guest-agent`, with the agent enabled on the VM, so the Proxmox UI can read the VM's IP and shut it down cleanly.
- A `deploy` user (uid and gid 1000, in the `docker` group, no password) so stacks that run as `PUID=1000`/`PGID=1000`, such as [qbittorrent-vpn-docker](https://github.com/rob-paprocki/qbittorrent-vpn-docker), can own their data folders under `/opt/stacks/` directly. Log in as `deploy` with the SSH key from the wizard, or with `su - deploy` from root.
- `openssh-server`, `git` and `python3-venv`. The paired stack needs the last two: `git` to clone it, and `python3-venv` so its host-side setup editor (`scripts/setup.sh`) can build its Python venv. The Debian 13 `nocloud` image ships `python3` but neither of these.
- `initial-startup.service`, which runs on first boot, starts Dockge (if you chose it) and Dockhand, configures Dockhand, and disables itself once it succeeds.
- An empty `/etc/machine-id`, so the VM generates its own on first boot.

Where things are:

- `/opt/stacks/`: your stacks. Dockhand scans it and creates new stacks in it, so Dockhand, Dockge and the `docker compose` CLI all work on the same `compose.yaml` files.
- `/opt/dockhand/compose.yaml`: Dockhand's compose file.
- `/opt/dockhand/data/`: Dockhand's data.
- `/opt/dockhand/firstboot.env`: the VM's hostname and the host's timezone, for the first-boot script.
- `/opt/stacks/dockge/`: Dockge's compose file and data, when installed.
- `/opt/dockhand_secrets/`: the Dockhand password and notification URL, until first boot succeeds (folder 0700, files 0600).
- `/usr/local/bin/initial-startup.sh`: the first-boot script that `initial-startup.service` runs.

### Dockhand's first-boot setup

On first boot, `initial-startup.service` sets Dockhand up with:

- the VM's local Docker socket as its environment, named after the VM's hostname;
- `/opt/stacks` as the folder it scans for stacks, and as the folder for stacks you create in Dockhand;
- a nightly update at 04:00 in the Proxmox host's timezone, which checks every container for a newer image and updates it. If the new image has more known vulnerabilities than the one it replaces, the update is blocked and reported instead;
- the stacks already in `/opt/stacks` adopted, which at first boot means Dockge's own stack if you installed it;
- a notification channel called "Update results" for succeeded, failed and blocked updates, if you gave a notification URL;
- an `admin` account, with local authentication on.

Containers that share another container's network (the paired stack's qBittorrent shares Gluetun's) are reconnected when the nightly update replaces that container.

Dockhand doesn't update itself on that schedule. It shows a new release in its sidebar and updates itself when you click it. Afterwards, set the new tag in `/opt/dockhand/compose.yaml`, so a later `docker compose up -d` there doesn't roll it back.

## Trust model and security

### What you're trusting

Several remote inputs go into the VM. Before you run this on infrastructure you care about, look at where each one comes from and how it's checked:

- **This script**, from `raw.githubusercontent.com/rob-paprocki/docker-pve`: HTTPS only. Pin the URL to a commit if you don't want the moving `main`.
- **`api.func`**, from `raw.githubusercontent.com/community-scripts/ProxmoxVE` at `API_FUNC_REF`: pinned to a commit, so a change on that repository's `main` can't reach you silently. The script exits if the fetch fails.
- **The Debian 13 `nocloud` image**, from `cloud.debian.org/images/cloud/trixie/latest/`: checked against the published `SHA512SUMS`, which covers integrity only. Debian's cloud team doesn't sign per-distribution images consistently, so GPG verification is deferred and authenticity rests on HTTPS to `cloud.debian.org`.
- **Docker CE packages**, from `download.docker.com`: Docker's apt signing key, itself fetched over HTTPS during the build.
- **Debian packages**, from the Debian mirrors configured in the image: Debian's archive signatures.
- **The Dockhand and Dockge images**, from Docker Hub on first boot: pinned by tag, not by digest.

`api.func` provides the two telemetry functions this script calls, `post_to_api_vm` and `post_update_to_api`. Because it's sourced, its code runs as root in the script's shell, which is why it's pinned. At the pinned commit, those functions post to `telemetry.community-scripts.org` only when `DIAGNOSTICS` isn't `no` and a session ID, `RANDOM_UUID`, is set. This script never sets `RANDOM_UUID`, so nothing is uploaded unless your shell already exports one.

### First-boot lock-down

Dockhand starts with authentication off and lets whoever reaches it first create the admin account. So `initial-startup.service` publishes Dockhand on `127.0.0.1` only, configures it and creates the `admin` account through its API, and turns authentication on. It republishes Dockhand on port 3000 only after an anonymous API request is refused.

The admin password and notification URL wait in `/opt/dockhand_secrets` and are deleted once that succeeds. If a required step fails, Dockhand stays on `127.0.0.1`, the secrets stay in place, and the service runs again on the next boot. Two steps only log a warning when they fail: adding the notification channel, and adopting the stacks found in `/opt/stacks`. `journalctl -u initial-startup` on the VM shows what happened.

### Residual risks

> [!WARNING]
> Dockhand and Dockge serve plain HTTP, so their passwords cross the network in the clear. Firewall ports 3000 (and 5001 with Dockge) off the WAN side, and put a TLS reverse proxy in front of them if the VM is reachable from networks you don't trust.

The other risks you accept:

- Dockhand, and Dockge when installed, have unrestricted access to `/var/run/docker.sock` on the guest, so a compromise of either is root on the guest. Dockhand also runs as root inside its container, which is its default.
- The `deploy` user is in the `docker` group, which is equivalent to root on the guest.
- The nightly update pulls and applies new images automatically. Blocking updates that add known vulnerabilities doesn't catch a malicious image with no known CVEs.
- Dockge has no first-boot lock-down; see [After it finishes](#after-it-finishes).

[SECURITY.md](.github/SECURITY.md) lists the same risks and says how to report a new one.

### Dockhand's licence

Dockhand is source-available under the [Business Source License 1.1](https://github.com/Finsys/dockhand/blob/main/LICENSE.txt), not open source. Each version converts to Apache 2.0 four years after its release, and [Dockhand's pricing page](https://dockhand.pro/#pricing) sells a separate commercial-use licence. This repository doesn't include Dockhand; the VM pulls its image from Docker Hub on first boot.

## Troubleshooting and FAQ

<details>
<summary>Dockhand's page doesn't load after first boot</summary>

First boot pulls the Dockhand image, waits up to three minutes for its API, and configures it before port 3000 opens to the network, so give it a few minutes. If it still doesn't load, log in to the VM as root (the **Console** in Proxmox works in every mode) and run:

```bash
journalctl -u initial-startup -b
docker ps
```

If `docker ps` doesn't list Dockhand at all, the image pull failed, so check that the VM can reach Docker Hub.

If it shows Dockhand on `127.0.0.1:3000->3000/tcp`, first boot hasn't finished, and the log names the call that failed. A `DOCKHAND_TAG` override whose API differs from what the script expects is one cause. Fix the cause, then run `systemctl start initial-startup` or reboot. The first-boot script reuses whatever an earlier run created, so running it again is safe.

</details>

<details>
<summary>How do I give the VM a static IP?</summary>

The wizard can't set one. The `nocloud` image this script downloads has no cloud-init, and Proxmox's `--ipconfig0` only takes effect through cloud-init, so a static-IP prompt would silently discard the value.

Instead, reserve an address for the VM's MAC address on your DHCP server (the MAC is on the VM's **Hardware** tab), or change the network configuration inside the guest after first boot. Moving to the `genericcloud` image with cloud-init would bring the prompt back; see [Known limitations](#known-limitations).

</details>

<details>
<summary>Why shouldn't I use Dockge's Start, Update or Deploy buttons?</summary>

Dockge runs its own bundled Docker Compose (v2.34.0 in Dockge 1.5.0), not the VM's `docker-compose-plugin`. The two compute different config hashes, so Dockge's Start, Update and Deploy buttons recreate every container in the stack. Use Dockge for reading logs and editing files, and deploy from Dockhand or with `docker compose` on the VM.

</details>

<details>
<summary>What notification URL formats does Dockhand accept?</summary>

Dockhand takes Apprise-style URLs, in the formats [Apprise lists for each service](https://github.com/caronc/apprise#supported-notifications). The wizard's prompt names `ntfys://`, `discord://`, `tgram://`, `gotify://`, `slack://` and `pover://`. Some examples:

- ntfy over HTTPS: `ntfys://ntfy.example.com/updates`
- Discord: `discord://webhook_id/webhook_token`
- Telegram: `tgram://bot_token/chat_id`
- Gotify: `gotify://host/token`
- Pushover: `pover://user_key@api_token`

A URL Dockhand rejects at first boot only logs a warning. In Default mode there's no prompt at all. Either way, add or fix the channel in Dockhand under **Settings → Notifications**.

</details>

<details>
<summary>How do I turn off diagnostics?</summary>

As shipped, this script uploads nothing. The pinned `api.func` posts only when `DIAGNOSTICS` isn't `no` (unset counts as `no`) and a session ID, `RANDOM_UUID`, is set, and this script never sets `RANDOM_UUID`. An upload could only happen if your shell already exports `RANDOM_UUID` and `DIAGNOSTICS` is set to something other than `no`.

To rule that out, or if you point `API_FUNC_REF` at a newer commit (check what that version sends first), prefix the one-liner with `DIAGNOSTICS=no`:

```bash
DIAGNOSTICS=no bash -c "$(curl -fsSL https://raw.githubusercontent.com/rob-paprocki/docker-pve/main/docker-stack-vm.sh)"
```

If `/usr/local/community-scripts/diagnostics` exists on the host, its `DIAGNOSTICS=` line replaces the environment value, so set it to `no` there too.

</details>

<details>
<summary>How do I get a shell on the VM?</summary>

Log in as root with the root password on the VM's **Console** in Proxmox. Over SSH, OpenSSH's default (`PermitRootLogin prohibit-password`) refuses root password logins, so:

- In Default mode there's no SSH key, so use the console.
- In Advanced mode, if you pasted a key, log in as `deploy` with it. If you allowed root SSH login, root can log in with its password, and with the key if you gave one.

</details>

<details>
<summary>How do I keep Debian on the VM up to date?</summary>

The nightly update covers container images only, not the VM's own Debian packages. Update those as you would on any Debian server, as root on the VM:

```bash
apt update && apt upgrade
```

The Debian image ships the `unattended-upgrades` package. Run `dpkg-reconfigure unattended-upgrades` to check whether it installs security updates automatically, or to turn that on.

</details>

<details>
<summary>How do I update Dockhand or Dockge?</summary>

Dockhand: click the new release in Dockhand's sidebar, then set the same tag in `/opt/dockhand/compose.yaml`. Dockge: edit the tag in `/opt/stacks/dockge/compose.yaml` and run `docker compose up -d` in that folder. [UPSTREAMS.md](UPSTREAMS.md) lists what to check before a Dockge bump.

</details>

<details>
<summary>The script stopped with an error. What's left behind?</summary>

If the error came after the VM was created, the script stops and destroys that VM. Pressing Ctrl+C doesn't, so look for a half-built VM if you interrupt a run. The temporary folder with the image and passwords is removed on every exit. Errors before that (a failed `api.func` fetch, a `SHA512SUMS` mismatch, no usable storage) leave nothing to clean up. Fix the cause and run the one-liner again.

</details>

<details>
<summary>I used an earlier version with Portainer and Watchtower</summary>

Since 4.0.0 the script installs Dockhand instead of both, with Dockge as an option. Dockhand handles image updates as well as container, image, volume and network management. Re-running the one-liner creates a new VM and doesn't touch existing ones. Notification URLs are now Apprise-style, not the Shoutrrr URLs Watchtower took. [CHANGELOG.md](CHANGELOG.md#400---2026-11-08) has the details.

</details>

## Known limitations

- No static IP prompt. It needs the `genericcloud` image and cloud-init.
- No GPG check of the Debian image, until Debian's cloud team signs per-distribution images. The monthly [external-upstream-watch](.github/workflows/external-upstream-watch.yml) workflow opens an issue when a signature file appears. It opens another when `api.func` on community-scripts' `main` has commits from the last 35 days other than the pinned one; it doesn't compare against everything since the pin.
- amd64 only. The script exits on other architectures, such as Proxmox on ARM (PiMox).
- Each run downloads the current `trixie/latest` image and the current Docker CE packages, so two runs weeks apart can produce slightly different VMs. Only `api.func` and the two container images are pinned; [UPSTREAMS.md](UPSTREAMS.md) lists each pin and how to bump it.
- Testing so far: CI runs `shellcheck` on every pull request. For 4.0.0, the first-boot script was run against `fnsys/dockhand:v1.0.57` on a plain Docker host (fresh installs with and without Dockge and notifications, a re-run, recovery from an interrupted first boot, a rejected password). No pull request records a full run on Proxmox VE, so the supported versions come from the script's version check, not from a test matrix.

## Getting help

- Questions, bugs and feature requests: [open an issue](https://github.com/rob-paprocki/docker-pve/issues). Include your Proxmox VE version (`pveversion`), whether you used Default or Advanced mode, the last lines of the script's output, and for first-boot problems the output of `journalctl -u initial-startup -b` from the VM.
- Problems with the qBittorrent stack itself: its [own issue tracker](https://github.com/rob-paprocki/qbittorrent-vpn-docker/issues).
- Security vulnerabilities: don't open a public issue. Follow [SECURITY.md](.github/SECURITY.md), which says how to report one privately.

This is a hobby project with one maintainer, [Rob Paprocki](https://github.com/rob-paprocki), so replies can take a few days.

## Contributing

Pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) covers testing a branch on Proxmox, the lint checks, the changelog and the pull request template. The full rules for people and agents alike are in [CLAUDE.md](CLAUDE.md).

## Changelog and versioning

[CHANGELOG.md](CHANGELOG.md) records every change a user could notice, in [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) format. Versions follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). Releases are to be tagged `vMAJOR.MINOR.PATCH`, each with a GitHub Release; none is published yet.

The version protects what you rely on when you run the script: the one-liner and the script's name, the wizard's modes, prompts and defaults, the environment variables above, the VM's services, ports, `deploy` user and paths, the first-boot behaviour, and what the paired stack depends on. A MAJOR version means re-running the one-liner gives a VM that no longer works the way this README says. [CLAUDE.md](CLAUDE.md#versioning-semantic-versioning-200) has the full rules.

Only the current `main` branch gets fixes; there are no backported releases ([SECURITY.md](.github/SECURITY.md)).

## Licence

MIT; see [LICENSE](LICENSE). The whiptail UI pattern, the `get_valid_nextid` helper and the `api.func` sourcing are adapted from the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) project, copyright © 2021-2025 community-scripts ORG; that notice is kept in the header of `docker-stack-vm.sh`. All additions in this script are copyright © 2025 Rob Paprocki.

The MIT licence covers this repository only. Dockhand and Dockge are separate projects under their own licences ([Dockhand's](#dockhands-licence) is not open source).

## Credits

- Maintained by [Rob Paprocki](https://github.com/rob-paprocki).
- [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE), for the helper-script pattern this script follows and the `api.func` it sources.
- [Dockhand](https://github.com/Finsys/dockhand) by Finsys, and [Dockge](https://github.com/louislam/dockge) by Louis Lam.
- The [Debian Cloud Team](https://cloud.debian.org/images/cloud/), for the cloud images.
- [libguestfs](https://libguestfs.org/), for `virt-customize` and `virt-resize`.
- [Mermaid](https://mermaid.js.org/), for drawing the diagrams in `docs/images/`.
- [NulightJens/humanizer-stack](https://github.com/NulightJens/humanizer-stack) (MIT), for the writing checks vendored in `.claude/skills/`.
