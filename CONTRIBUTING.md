# Contributing to docker-pve

This repository is a release copy. Development happens elsewhere, and this repository changes only when a new version comes out, one commit per version, so a pull request can't be merged as it is. Open it anyway: I'll bring the change across by hand, credit you in the changelog and close the pull request. The rest of this page still applies to how you prepare it.

The rules on this page apply to every contributor, whether a person or an agent.

To report a security vulnerability, don't open a pull request or a public issue; follow [SECURITY.md](.github/SECURITY.md).

Planned work is in [ROADMAP.md](ROADMAP.md), with an issue for each item.

## Before you open a pull request

- Open the pull request against `main`. The [pull request template](.github/pull_request_template.md) asks for a summary, a test plan and a one-line rollback.
- Test your branch on a Proxmox VE host. The script fetches nothing else from this repository, so the one-liner pointed at your fork and branch runs your version end to end. Set the two variables first:

  ```bash
  YOUR_USER=your-github-name
  YOUR_BRANCH=your-branch-name
  bash -c "$(curl -fsSL "https://raw.githubusercontent.com/$YOUR_USER/docker-pve/$YOUR_BRANCH/docker-stack-vm.sh")"
  ```

  Then check `journalctl -u initial-startup -b` on the new VM, and say what you ran in the test plan.
- Keep the [lint workflow](.github/workflows/lint.yml) passing; the pull request template asks you to confirm it does. It runs on every pull request to `main` and every push to it, and does two things:
  - runs `shellcheck` at warning severity on the shell scripts. To run the same check before you push, use `shellcheck --severity=warning docker-stack-vm.sh docs/images/render.sh`, which picks up the repository's `.shellcheckrc`;
  - fails if a tracked Markdown file has a Mermaid block, or shows an image from the repository that doesn't switch with the reader's light or dark theme. The [Images and diagrams](#images-and-diagrams) section below says how to make one that does.

## Changelog, README and other docs

- Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for anything a user could notice, under `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` or `Security`. Breaking changes start with **Breaking** and say how to adapt. Each release section opens with an `**Upgrading:**` line: either `**Upgrading:** nothing to do.` or the steps to take. CI-only and housekeeping changes can skip it.
- When you change behaviour, update the README in the same pull request. To change a diagram, edit its `.mmd` source in `docs/images/` and regenerate the images as [Images and diagrams](#images-and-diagrams) describes.
- Read user-facing text again after writing it: cut filler and stock phrases, then re-check every fact (versions, ports, paths, commands, defaults) against the script.
- To bump a pinned image, follow [UPSTREAMS.md](UPSTREAMS.md). Dependabot covers GitHub Actions versions and the diagram tools, and those bumps ship with releases; the rest is done by hand.

## What counts as breaking

The version protects what people rely on when they run the script:

- the one-liner in the README and the script's name and path (`docker-stack-vm.sh`);
- the wizard: its modes (Default and Advanced), prompts, choices and defaults;
- the environment variables it reads: `DOCKHAND_IMAGE`, `DOCKHAND_TAG`, `DOCKGE_TAG`;
- what the VM it creates contains: the installed services and their ports (Dockhand 3000, Dockge 5001), the `deploy` user (uid 1000, in the `docker` group), the paths `/opt/stacks`, `/opt/dockhand` and `/opt/stacks/dockge`, and the first-boot behaviour of `initial-startup.service`;
- what the paired [qbittorrent-vpn-docker](https://github.com/rob-paprocki/qbittorrent-vpn-docker) stack depends on: the `/opt/stacks` location, uid and gid 1000, and `git` and `python3-venv` on the VM.

Pick the bump from the most significant change in the release:

| Bump | When | Examples |
|---|---|---|
| Major | Re-running the documented command gives a VM that no longer works the way the README said, or a documented prompt, option, variable, port, path or default is removed or changes meaning | Changing the default manager; removing Watchtower; moving `/opt/stacks` |
| Minor | New functionality that leaves every existing command and default working | A new wizard option; a new optional service; a new override variable |
| Patch | Fixes, docs, CI, and dependency pin bumps that don't change documented behaviour | A bug fix; a Dockhand tag bump with no behaviour change; README corrections |

A dependency bump that changes documented behaviour (a port, a path, a default, a login flow) is minor or major, not patch. While a change is only on `main`, it sits under `[Unreleased]` in the changelog.

## Images and diagrams

- **No Mermaid in docs.** The GitHub mobile app shows Mermaid as raw code. A diagram is a committed image, rendered from a source file kept in the repository.
- **Every image follows the reader's theme.** Show a light and a dark version in a `<picture>`, with the light one as the fallback:

  ```html
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/NAME-dark.svg">
    <img alt="What the image shows" src="docs/images/NAME-light.svg">
  </picture>
  ```

  The same pattern works for screenshots (`NAME-light.png` and `NAME-dark.png`). Don't use the `#gh-dark-mode-only` and `#gh-light-mode-only` URL fragments.
- **Diagram sources** live in `docs/images/` as `NAME.mmd`. Mermaid is only the source language; the diagram is rendered offline. After editing a `.mmd` file or `mermaid-light.json` or `mermaid-dark.json`, run `docs/images/render.sh` (or `docs/images/render.sh NAME` for one diagram) from the repository root. It needs Node.js 22.13 or later, npm and python3, installs the pinned tools into a temporary folder, and writes `NAME-light.svg`, `NAME-dark.svg` and a combined `NAME.svg`. Commit the source and all three files together.
- **Keep diagrams narrow.** GitHub's README column is about 327 px wide on a phone, so aim for a natural width of about 380 px or less and wrap labels at about 16 characters.
- **Alt text** walks through every step and branch of the diagram. Follow the image with a short numbered list of the same flow, because the mobile app may not show it.
- **Badges** stay single images from shields.io or GitHub Actions. Give each one alt text and a message colour with at least 4.5:1 contrast against white text, such as `0969da`.
- **Check both themes** at phone width and on a desktop before merging: no text spilling out of its box, diagram text at least 13 px, and contrast of at least 4.5:1 for text and 3:1 for lines.

## Review

[CODEOWNERS](.github/CODEOWNERS) assigns every file to the repository owner, so GitHub requests their review on every pull request. This is a hobby project with one maintainer, so a review can take a few days.
