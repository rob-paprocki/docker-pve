# Security policy

## Reporting

Open a private GitHub Security Advisory on this repository, or email `rob.paprocki.14@gmail.com` with `[security:docker-pve]` in the subject line. Expect a first reply inside five business days; this is a hobby repo with one maintainer.

Do not open a public issue for a vulnerability until a fix is released.

## Supported versions

Only the current `main` branch is supported. Each change rolls forward; there are no backported releases.

## Known residual risks

These are documented, not fixed yet.

[CVE-2026-78122](https://app.opencve.io/cve/CVE-2026-78122) on `ghcr.io/tecnativa/docker-socket-proxy:0.5.0`. A client with `CONTAINERS=1` can GET `/containers/{id}/archive|export|logs|top`. The proxy here sits on an internal (egressless) Docker network reachable only by the monitor-only Watchtower, so the exposure is bounded by that one container's blast radius. Upstream fix tracked at [Tecnativa/docker-socket-proxy#183](https://github.com/Tecnativa/docker-socket-proxy/pull/183); the monthly `external-upstream-watch` workflow in this repo opens an issue when PR #183 merges.

Debian cloud image authenticity. The provisioning script verifies the Debian 13 cloud image against the published `SHA512SUMS` but does not verify a GPG signature, because Debian's cloud team does not sign per-distribution images consistently. HTTPS to `cloud.debian.org` is the only authenticity leg. The same monthly workflow watches for a signature file to appear.

Docker socket exposure. Dockge, the updating Watchtower, Portainer, and the Portainer agent each have unrestricted access to `/var/run/docker.sock` on the guest. A compromise of any of them is root on the guest. The monitor-only Watchtower is proxied; the others are not.

## Scope

Reports in scope: the provisioning script, the compose files it writes, the systemd unit, and the trust model described in the README.

Out of scope: the containers themselves (file bugs upstream), Proxmox VE, Debian, Docker, the kernel, your network, your DHCP server.
