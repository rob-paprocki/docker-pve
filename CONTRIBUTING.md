# Contributing to docker-pve

Pull requests are welcome. The repository's rules are in [CLAUDE.md](CLAUDE.md) and apply to every contributor, whether a person or an agent. This page is the short version.

To report a security vulnerability, don't open a pull request or a public issue; follow [SECURITY.md](.github/SECURITY.md).

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
  - fails if a tracked Markdown file has a Mermaid block, or shows an image from the repository that doesn't switch with the reader's light or dark theme. CLAUDE.md, under "Images and diagrams", says how to make one that does.

## Changelog, README and other docs

- Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for anything a user could notice, under `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` or `Security`. Breaking changes start with **BREAKING:** and say how to adapt. CI-only and housekeeping changes can skip it.
- When you change behaviour, update the README in the same pull request. To change a diagram, edit its `.mmd` source in `docs/images/` and regenerate the images as CLAUDE.md describes.
- Run user-facing text through the two humanizer passes CLAUDE.md describes, then re-check every fact against the script.
- To bump a pinned image or `api.func`, follow [UPSTREAMS.md](UPSTREAMS.md). Dependabot only bumps GitHub Actions versions; the rest is done by hand.

## Review

[CODEOWNERS](.github/CODEOWNERS) assigns every file to the repository owner, so GitHub requests their review on every pull request. This is a hobby project with one maintainer, so a review can take a few days.
