# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions 1.0.0 to 4.0.0 were assigned retroactively on 2026-11-09 from the merge history. 1.0.0 is the script at `8d4dbad`, the last commit on `main` before the first PR, and each later version's tag points at the merge commit of the PR it covers.

The script builds a new VM each time it runs and leaves existing VMs alone, so a new version only changes the VMs you build with it. Entries marked **BREAKING:** change something you may rely on and say what to do; [CLAUDE.md](CLAUDE.md) defines what counts as breaking. Versions 3.0.1 to 3.0.8 change only documentation and the repository's CI, not the script.

## [Unreleased]

### Added

- `CHANGELOG.md`, with a version back-filled for every merged PR.
- `CLAUDE.md`, the project rules for versioning, the changelog, the README and user-facing text.
- The humanizer and structural-humanizer skills under `.claude/skills/`, vendored from [NulightJens/humanizer-stack](https://github.com/NulightJens/humanizer-stack) at commit `13f5c02` under its MIT licence, for editing user-facing text.

### Changed

- README reorganised. The script behaves the same.

## [4.0.0] - 2026-11-08

### Added

- Dockhand (`fnsys/dockhand:v1.0.57`) is the VM's Docker manager and image updater. It lives in `/opt/dockhand`, manages the stacks in `/opt/stacks`, and serves plain HTTP on port 3000 (Portainer used HTTPS), so put a TLS reverse proxy in front of it if the VM is reachable from untrusted networks. Log in at `http://<vm-ip>:3000` as `admin` with the password you gave the wizard (in Default mode, the root password). Dockhand is source-available under the Business Source License 1.1, not open source. ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))
- First boot sets Dockhand up before the network can reach it: it registers the local Docker socket, scans `/opt/stacks`, schedules a nightly update at 04:00 host time, adds the notification channel if you gave a URL, adopts the stacks already in `/opt/stacks`, creates `admin` and turns on login. Until then Dockhand listens only on `127.0.0.1`; port 3000 opens to the network once a test request without a login is refused. ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))
- `DOCKHAND_IMAGE` and `DOCKHAND_TAG` override the Dockhand image (defaults `fnsys/dockhand` and `v1.0.57`). ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))
- Advanced mode asks for a Dockhand `admin` password of at least 8 characters in place of the Portainer password, and whether to install Dockge (default no). ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))
- The VM gets `git`, to clone the paired [qbittorrent-vpn-docker](https://github.com/rob-paprocki/qbittorrent-vpn-docker) stack, and `python3-venv`, which that stack's `scripts/setup.sh` needs to build its Python venv. ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))
- Sponsor links on the GitHub repository page (`.github/FUNDING.yml`). ([e5dfb3a](https://github.com/rob-paprocki/docker-pve/commit/e5dfb3a), [2f4b772](https://github.com/rob-paprocki/docker-pve/commit/2f4b772))

### Changed

- **BREAKING:** Dockge is no longer installed by default, and Default mode no longer creates `/opt/stacks/dockge`. To keep Dockge on port 5001, pick **Advanced** when the wizard asks "Use Default Settings?", then answer yes to the Dockge question. Its compose file is then `/opt/stacks/dockge/compose.yaml` (was `docker-compose.yml`). ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))
- **BREAKING:** The nightly 04:00 update now covers every container on the VM except Dockhand itself, including stacks you deploy yourself; Watchtower only touched containers labelled `scope=dockge`. An update is blocked and reported when the new image has more known vulnerabilities than the current one. Containers that share another container's network, such as qBittorrent behind Gluetun in the paired stack, are reconnected when that container is updated. To stop unattended updates, change or turn off the schedule in Dockhand's update settings for the VM's Docker environment, which is named after the VM's hostname. The schedule covers every container on the VM. ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))
- **BREAKING:** The notification URL prompt takes an Apprise-style URL for Dockhand, such as `ntfys://ntfy.example.com/updates` or `tgram://bot_token/chat_id`, instead of a Shoutrrr URL for Watchtower. Rewrite any URL you reuse in Apprise form. ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))
- **BREAKING:** Default mode now needs a root password of at least 8 characters, because it is also the Dockhand `admin` password. ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))
- `initial-startup.service` disables itself only after first-boot setup succeeds. If setup fails, Dockhand stays on `127.0.0.1`, out of reach from the network, and the service runs again on the next boot; `journalctl -u initial-startup` on the VM shows what went wrong. If only the notification channel or the stack adoption fails, setup logs a warning and carries on. ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))
- The Proxmox VM tags are `docker,dockhand,debian13`, plus `dockge` when Dockge is installed (were `docker,dockge,portainer,debian13`), and the VM's Proxmox notes link to Dockhand on port 3000. ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))
- The README now says to clone the paired stack into `/opt/stacks/torrent-stack` and adopt it in Dockhand under **Stacks → Adopt**. ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))

### Removed

- **BREAKING:** Portainer CE and the Portainer agent. Ports 8000, 9443 and 9001 are no longer used, `/opt/stacks/portainer` and `/opt/portainer_secrets` are no longer created, and `PORTAINER_CE_TAG` and `PORTAINER_AGENT_TAG` are no longer read. Use Dockhand on port 3000. VMs built by earlier versions are not migrated; rebuild one to switch. ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))
- **BREAKING:** Both Watchtower instances and `docker-socket-proxy`; Dockhand does the updates. `WATCHTOWER_IMAGE`, `WATCHTOWER_TAG`, `SOCKET_PROXY_IMAGE` and `SOCKET_PROXY_TAG` are no longer read. ([#12](https://github.com/rob-paprocki/docker-pve/pull/12))

## [3.0.8] - 2026-10-25

### Changed

- CI: `actions/checkout` bumped from 4 to 7 in every workflow that uses it. ([#6](https://github.com/rob-paprocki/docker-pve/pull/6))

## [3.0.7] - 2026-10-25

### Fixed

- CI: the breaking-change review workflow accepts PRs opened by `dependabot[bot]`. ([#10](https://github.com/rob-paprocki/docker-pve/pull/10))

## [3.0.6] - 2026-10-25

### Fixed

- CI: the breaking-change review workflow passes `github_token` to the Claude action, so the Claude GitHub App is no longer needed. ([#9](https://github.com/rob-paprocki/docker-pve/pull/9))

## [3.0.5] - 2026-10-24

### Fixed

- CI: the breaking-change review workflow runs on `pull_request_target`, so it uses `main`'s copy of the workflow and passes the action's validation. ([#8](https://github.com/rob-paprocki/docker-pve/pull/8))

## [3.0.4] - 2026-10-24

### Fixed

- CI: the breaking-change review workflow gets the `id-token: write` permission it needs. ([#7](https://github.com/rob-paprocki/docker-pve/pull/7))

## [3.0.3] - 2026-10-24

### Changed

- CI: Dependabot replaces Renovate and tracks GitHub Actions versions. A new workflow labels Dependabot PRs that cross a major version `breaking-candidate`, which starts the Claude review. The image tags in `docker-stack-vm.sh` are bumped by hand, as `UPSTREAMS.md` describes. ([#5](https://github.com/rob-paprocki/docker-pve/pull/5))

## [3.0.2] - 2026-10-24

### Added

- `.github/SECURITY.md`: how to report a vulnerability privately, and the known residual risks. ([#4](https://github.com/rob-paprocki/docker-pve/pull/4))
- `UPSTREAMS.md`: each pinned dependency, what to watch for in its releases, and how to bump it. ([#4](https://github.com/rob-paprocki/docker-pve/pull/4))
- CI: Renovate config, a Claude review workflow for major dependency bumps, a monthly upstream-watch workflow, CODEOWNERS and a PR template. ([#4](https://github.com/rob-paprocki/docker-pve/pull/4))

## [3.0.1] - 2026-10-23

### Fixed

- README updated to match 3.0.0: the six services and their Watchtower scopes, the pre-seeded Portainer admin, the new Advanced prompts and the trust model. ([#3](https://github.com/rob-paprocki/docker-pve/pull/3))

## [3.0.0] - 2026-10-23

### Added

- Advanced mode asks for an optional SSH public key and adds it to `deploy`, and to root when root SSH login is allowed. ([#2](https://github.com/rob-paprocki/docker-pve/pull/2))
- A second Watchtower, `watchtower-portainer`, checks Portainer and the agent at 05:30 and sends a notification instead of updating them. It reaches Docker through a read-only `docker-socket-proxy` on an internal network. ([#2](https://github.com/rob-paprocki/docker-pve/pull/2))
- `WATCHTOWER_IMAGE`, `SOCKET_PROXY_IMAGE` and `SOCKET_PROXY_TAG` override the Watchtower image and the socket proxy's image and tag. ([#2](https://github.com/rob-paprocki/docker-pve/pull/2))

### Changed

- **BREAKING:** The Portainer admin password is baked into the image at `/opt/portainer_secrets/portainer_admin_password` (mode 0600), and Portainer creates the `admin` account from it on first start. That closes the first-boot window in which anyone on the network could claim the account. The first visit shows a login page instead of the admin-setup page: log in at `https://<vm-ip>:9443` as `admin`. Default mode uses the root password; Advanced mode asks for a separate Portainer password of at least 12 characters. ([#2](https://github.com/rob-paprocki/docker-pve/pull/2))
- **BREAKING:** Watchtower runs `ghcr.io/nicholas-fedor/watchtower:v1.23.2`, the maintained fork, because `containrrr/watchtower` was archived. `WATCHTOWER_TAG` now picks a tag of the fork; if you set it, use a tag the fork publishes. ([#2](https://github.com/rob-paprocki/docker-pve/pull/2))
- The notification URL prompt shows an ntfy example and lists the Shoutrrr schemes it accepts. ([#2](https://github.com/rob-paprocki/docker-pve/pull/2))

### Security

- `api.func` is fetched from community-scripts/ProxmoxVE commit `500a860` instead of `main`. Set `API_FUNC_REF` to use another commit. ([#2](https://github.com/rob-paprocki/docker-pve/pull/2))
- The Debian cloud image is checked against Debian's published `SHA512SUMS`, and the script stops on a mismatch or a missing entry. ([#2](https://github.com/rob-paprocki/docker-pve/pull/2))

## [2.0.0] - 2026-10-23

### Added

- README: requirements, the one-liner, what the VM contains, the wizard options, the trust model and first steps. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))
- A `deploy` user in the VM (uid 1000, in the `docker` group), so stacks that run as `PUID=1000`/`PGID=1000`, such as qbittorrent-vpn-docker, can own their folders under `/opt/stacks`. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))
- `DOCKGE_TAG`, `PORTAINER_CE_TAG`, `PORTAINER_AGENT_TAG` and `WATCHTOWER_TAG` override the image tags. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))
- CI: shellcheck on pull requests and pushes to `main`. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))

### Changed

- Images are pinned: Dockge `1.5.0` (was `1`), Portainer CE and agent `2.45.3` (were `latest` and untagged), Watchtower `1.7.1` (was untagged). ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))
- The containers' timezone, which also sets the time of Watchtower's 04:00 run, comes from the Proxmox host (`timedatectl`, then `/etc/timezone`) instead of an ipapi.co lookup, which sent the host's public IP to a third party. If neither gives a valid timezone, it uses UTC. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))
- The script stops if it cannot download `api.func`. Before, it carried on without the functions it calls. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))

### Removed

- **BREAKING:** Advanced mode no longer asks for a static IPv4 address and gateway. The address was never applied, because the `nocloud` image has no cloud-init, so VMs always used DHCP. Set a DHCP reservation, or configure the address inside the VM after boot. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))

### Fixed

- Watchtower updates Dockge and itself at 04:00. In 1.0.0 neither container carried the `scope=dockge` label its filter looks for, so it skipped everything. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))
- Portainer and the agent come back after a reboot or crash (`restart: unless-stopped`). Before, they relied on the swarm-only `deploy.restart_policy`, which Docker Compose ignores. The two now share a network. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))
- q35 VMs get a 4 MiB EFI vars disk to match the OVMF firmware, as i440fx VMs already did. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))
- Proxmox VE 9.1 and later 9.x releases pass the version check, which used to accept only 9.0. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))
- Root passwords with spaces, quotes or other shell characters no longer break the image build. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))
- Ctrl+C and SIGTERM exit the script (status 130 and 143). ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))

### Security

- The root password reaches `virt-customize` through a 0600 file, not the command line, where other users on the Proxmox host could read it from the process list. ([#1](https://github.com/rob-paprocki/docker-pve/pull/1))

## [1.0.0] - 2025-10-15

### Added

- `docker-stack-vm.sh`, run as root on a Proxmox VE 8.x or 9.0 amd64 host. It downloads the Debian 13 `nocloud` cloud image, installs Docker CE into it with `virt-customize`, and creates a UEFI VM (by default 2 cores, 4096 MiB RAM, a 25 GiB disk, hostname `docker`, bridge `vmbr0`, machine type i440fx). The repository held only this script and the MIT licence.
- The VM runs Dockge (`louislam/dockge:1`, port 5001) with Watchtower (nightly at 04:00, optional notification URL) from `/opt/stacks/dockge`, and Portainer CE (`latest`, ports 8000 and 9443) with the Portainer agent (port 9001) from `/opt/stacks/portainer`. A one-shot `initial-startup.service` starts both stacks on first boot.
- A whiptail wizard. Default mode asks only for a root password. Advanced mode also asks for the VMID, machine type (i440fx or q35), disk size, hostname, CPU cores, RAM, bridge, MAC address, IPv6, a static IPv4 address and gateway, a Watchtower notification URL, root SSH login and whether to start the VM.

[Unreleased]: https://github.com/rob-paprocki/docker-pve/compare/v4.0.0...HEAD
[4.0.0]: https://github.com/rob-paprocki/docker-pve/compare/v3.0.8...v4.0.0
[3.0.8]: https://github.com/rob-paprocki/docker-pve/compare/v3.0.7...v3.0.8
[3.0.7]: https://github.com/rob-paprocki/docker-pve/compare/v3.0.6...v3.0.7
[3.0.6]: https://github.com/rob-paprocki/docker-pve/compare/v3.0.5...v3.0.6
[3.0.5]: https://github.com/rob-paprocki/docker-pve/compare/v3.0.4...v3.0.5
[3.0.4]: https://github.com/rob-paprocki/docker-pve/compare/v3.0.3...v3.0.4
[3.0.3]: https://github.com/rob-paprocki/docker-pve/compare/v3.0.2...v3.0.3
[3.0.2]: https://github.com/rob-paprocki/docker-pve/compare/v3.0.1...v3.0.2
[3.0.1]: https://github.com/rob-paprocki/docker-pve/compare/v3.0.0...v3.0.1
[3.0.0]: https://github.com/rob-paprocki/docker-pve/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/rob-paprocki/docker-pve/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/rob-paprocki/docker-pve/releases/tag/v1.0.0
