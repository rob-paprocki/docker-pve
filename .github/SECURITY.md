# Security policy

## Reporting

Open a private GitHub Security Advisory on this repository, or email `rob.paprocki.14@gmail.com` with `[security:docker-pve]` in the subject line. Expect a first reply inside five business days; this is a hobby repo with one maintainer.

Do not open a public issue for a vulnerability until a fix is released.

## Supported versions

Only the current `main` branch is supported. Each change rolls forward; there are no backported releases.

## Known residual risks

These are documented, not fixed yet.

Debian cloud image authenticity. The provisioning script verifies the Debian 13 cloud image against the published `SHA512SUMS` but does not verify a GPG signature, because Debian's cloud team does not sign per-distribution images consistently. HTTPS to `cloud.debian.org` is the only authenticity leg. The monthly `external-upstream-watch` workflow watches for a signature file to appear.

Docker socket exposure. Dockhand, and Dockge when installed, have unrestricted access to `/var/run/docker.sock` on the guest. A compromise of either is root on the guest.

Root inside the Dockhand container. Dockhand runs as root inside its container, which is its default.

The `deploy` user. It is in the `docker` group, which is equivalent to root on the guest.

Automatic image updates. Dockhand pulls and applies new images nightly. It blocks an update whose image has more known vulnerabilities than the running one, which does not catch a malicious image with no known CVEs.

Plain HTTP. Dockhand (port 3000) and Dockge (port 5001) serve HTTP only, so logins cross the network in the clear unless a TLS reverse proxy fronts them.

First-boot window. Dockhand lets whoever reaches it first create the admin account while authentication is off. The first-boot script keeps Dockhand on `127.0.0.1` until the admin exists and an anonymous API request is refused, and leaves it there if a required step fails.

Dockge has no first-boot lock-down. When it is installed, first boot publishes it on port 5001 straight away, and the first person to open it creates its admin account.

## Scope

Reports in scope: the provisioning script, the compose files it writes, the systemd unit, and the trust model described in the README.

Out of scope: the containers themselves (file bugs upstream), Proxmox VE, Debian, Docker, the kernel, your network, your DHCP server.
