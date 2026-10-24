# Upstream dependencies

Every pinned version in this repo, where it comes from, and what to watch for.

Two moving parts handle the automation:

- [`.github/dependabot.yml`](.github/dependabot.yml) auto-bumps the one thing Dependabot can parse here: GitHub Actions versions in `.github/workflows/*.yml`. Non-major bumps are grouped on one Monday PR.
- [`.github/workflows/label-major-bumps.yml`](.github/workflows/label-major-bumps.yml) adds the `breaking-candidate` label to any Dependabot PR crossing a major-version boundary. That label fires [`.github/workflows/claude-breaking-review.yml`](.github/workflows/claude-breaking-review.yml), which has Claude read the upstream changelog, grep this repo for the specific symbols flagged, and comment with a `REAL / NOT / UNCLEAR` verdict.

Dependabot does not read bash scripts, so the five Docker image tags encoded as `${VAR:-default}` inside `docker-stack-vm.sh` are **hand-bumped**. The monthly [`.github/workflows/external-upstream-watch.yml`](.github/workflows/external-upstream-watch.yml) files GitHub issues when the three externally-blocked items are ready (CVE-2026-78122 fix lands, Debian starts signing cloud images, `community-scripts/api.func` drifts). For the other image tags, this file is the companion recipe: each section below has the source link, the breaking signals, and the hand-bump steps.

## Container images (hand-bumped)

The following tags live inside `docker-stack-vm.sh` as `${VAR:-default}` bash defaults. Dependabot cannot parse these; a bump is a one-line edit per variable followed by a shellcheck pass.

### `louislam/dockge`

- **Pinned at:** `DOCKGE_TAG` default (currently `1.5.0`)
- **Source:** [`louislam/dockge`](https://hub.docker.com/r/louislam/dockge) on Docker Hub, [GitHub releases](https://github.com/louislam/dockge/releases)
- **Breaking signals:** major-version bumps; data-model changes documented in the release notes under "Migration" or "Breaking". Dockge's stack-folder layout is stable, but the UI auth model has moved before.
- **Bump by hand:** change the `DOCKGE_TAG` default, re-render `dockge-compose.yml` locally with the heredoc, redeploy via Dockge.

### `portainer/portainer-ce` and `portainer/agent`

- **Pinned at:** `PORTAINER_CE_TAG` and `PORTAINER_AGENT_TAG` (both `2.45.3`)
- **Source:** [Portainer releases](https://github.com/portainer/portainer/releases). CE and agent are tagged in lockstep by Portainer.
- **Breaking signals:** database schema migrations between majors (2.x → 3.x will be one). Breaking CLI flag changes are rare. The `--admin-password-file` flag format (plaintext, read at first start) has been stable; if it ever changes, the admin pre-seed will silently fail.
- **Bump by hand:** change both default tag values together. Agent and CE must match or Portainer's environment page will complain.

### `ghcr.io/nicholas-fedor/watchtower`

- **Pinned at:** `WATCHTOWER_TAG` default (currently `v1.23.2`)
- **Source:** [`nicholas-fedor/watchtower`](https://github.com/nicholas-fedor/watchtower), the active community fork of the archived `containrrr/watchtower`.
- **Breaking signals:** env var renames or label-prefix changes. The current prefix is `com.centurylinklabs.watchtower.*` and matches the containrrr era; a prefix rename would break every scope label in this repo at once. Monitor-only mode is `WATCHTOWER_MONITOR_ONLY=true`.
- **Bump by hand:** change `WATCHTOWER_TAG`. Both Watchtower instances share the variable.

### `ghcr.io/tecnativa/docker-socket-proxy`

- **Pinned at:** `SOCKET_PROXY_TAG` default (currently `0.5.0`)
- **Source:** [`Tecnativa/docker-socket-proxy`](https://github.com/Tecnativa/docker-socket-proxy)
- **Breaking signals:** [CVE-2026-78122](https://app.opencve.io/cve/CVE-2026-78122) fix is in-flight at [PR #183](https://github.com/Tecnativa/docker-socket-proxy/pull/183); the first release carrying it will probably rework the `CONTAINERS` env semantics. Env variable additions beyond `CONTAINERS/IMAGES/POST` are not breaking for this repo (we don't use the others).
- **Bump by hand:** change `SOCKET_PROXY_TAG`. If the fix release renames env variables, update the docker-socket-proxy service block in the dockge-compose heredoc.

## Non-container upstreams

### Debian 13 `nocloud` cloud image

- **Pinned at:** not pinned; downloaded from `cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-$(arch).qcow2` on every run
- **Verified against:** published `SHA512SUMS` at the same path. GPG signature verification is not done; the Debian cloud team does not sign per-distribution images consistently. The monthly `external-upstream-watch` workflow checks for a signature file to appear.
- **Breaking signals:** a next-release name change (`trixie` → whatever the next stable codename is) would need the URL template updated. SHA512 verification fails hard on any mismatch, so a corrupt or substituted image won't silently install.
- **Bump by hand:** nothing to do unless Debian changes the release codename, in which case update `URL` in `docker-stack-vm.sh`.

### `community-scripts/ProxmoxVE` `api.func`

- **Pinned at:** `API_FUNC_REF` default commit SHA (currently `500a860faf7295e6dad20670d05e6400d18f66b0`)
- **Source:** [`community-scripts/ProxmoxVE`](https://github.com/community-scripts/ProxmoxVE), file `misc/api.func`
- **Verified against:** the two functions this script uses (`post_to_api_vm`, `post_update_to_api`) by grep before pinning.
- **Breaking signals:** a rename or removal of either function; under `set -e` the script would exit immediately on first call. The monthly `external-upstream-watch` workflow lists new commits touching `misc/api.func` since the pin and opens an issue when it finds any.
- **Bump by hand:** fetch the raw file at the candidate SHA, confirm both functions still exist, update `API_FUNC_REF`.

### GitHub Actions

- **Pinned at:** inside `.github/workflows/*.yml` (`actions/checkout@v4`, `ludeeus/action-shellcheck@2.0.0`, `anthropics/claude-code-action@v1`)
- **Source:** each action's own GitHub repo.
- **Breaking signals:** `v1` → `v2` major on `claude-code-action` is the one most likely to actually require changes (prompt / input renames).
- **Auto-tracked:** yes, by Dependabot (`github-actions` ecosystem). Non-major bumps group on a Monday PR; majors land solo and get labelled `breaking-candidate` by `label-major-bumps.yml`.

## How to add a new pinned dep

1. Add the `VAR="${VAR:-default}"` line to `docker-stack-vm.sh`.
2. Add a section here with a source link, breaking signals, and a bump-by-hand paragraph.
3. If the dep is externally-blocked on an upstream issue (like Tecnativa PR #183), add a check step to `.github/workflows/external-upstream-watch.yml` so a bump candidate shows up as a GitHub issue when the upstream is ready.

If a dep ever gains a form Dependabot can parse (a Dockerfile, a package manifest, a compose file), add an `updates:` block for that ecosystem to `.github/dependabot.yml` instead of hand-bumping.
