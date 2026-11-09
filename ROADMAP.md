# Roadmap

What's planned for docker-pve. Each item links to its GitHub issue, which holds the design and the discussion. Nothing here is promised by a date.

## Planned

- **More Dockhand notifications** ([#16](https://github.com/rob-paprocki/docker-pve/issues/16)). Today the notification channel reports only update results. This adds a container going unhealthy (for the paired stack, that's the VPN), a container killed for running out of memory, Docker's disk use passing a limit, and new releases of the pinned Dockhand and Dockge images. Default mode would also ask for the webhook, and both of Discord's webhook URL formats would be accepted.

The paired [qbittorrent-vpn-docker](https://github.com/rob-paprocki/qbittorrent-vpn-docker/blob/main/ROADMAP.md) stack has its own notification plans: download finished, VPN status and alerts for native installs.

## Waiting on something outside this project

These are the README's [known limitations](README.md#known-limitations) that could be lifted later:

- **A static IP prompt.** This needs a move to Debian's `genericcloud` image with cloud-init.
- **A GPG check of the Debian image.** This waits for Debian's cloud team to sign per-distribution images; a monthly workflow watches for it.
- **arm64 hosts.**

## How to suggest something

Open an issue. If it's a change you'd like to make yourself, [CONTRIBUTING.md](CONTRIBUTING.md) says how.
