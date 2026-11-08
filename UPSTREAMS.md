# Upstream dependencies

Every pinned version in this repo, where it comes from, and what to watch for.

Two moving parts handle the automation:

- [`.github/dependabot.yml`](.github/dependabot.yml) auto-bumps the one thing Dependabot can parse here: GitHub Actions versions in `.github/workflows/*.yml`. Non-major bumps are grouped on one Monday PR.
- [`.github/workflows/label-major-bumps.yml`](.github/workflows/label-major-bumps.yml) adds the `breaking-candidate` label to any Dependabot PR crossing a major-version boundary. That label fires [`.github/workflows/claude-breaking-review.yml`](.github/workflows/claude-breaking-review.yml), which has Claude read the upstream changelog, grep this repo for the specific symbols flagged, and comment with a `REAL / NOT / UNCLEAR` verdict.

Dependabot does not read bash scripts, so the two Docker image tags encoded as `${VAR:-default}` inside `docker-stack-vm.sh` are **hand-bumped**. The monthly [`.github/workflows/external-upstream-watch.yml`](.github/workflows/external-upstream-watch.yml) files GitHub issues when the two externally-blocked items are ready (Debian starts signing cloud images, `community-scripts/api.func` drifts). For the other image tags, this file is the companion recipe: each section below has the source link, the breaking signals, and the hand-bump steps.

## Container images (hand-bumped)

The following tags live inside `docker-stack-vm.sh` as `${VAR:-default}` bash defaults. Dependabot cannot parse these; a bump is a one-line edit per variable followed by a shellcheck pass.

### `fnsys/dockhand`

- **Pinned at:** `DOCKHAND_TAG` default (currently `v1.0.57`); image name in `DOCKHAND_IMAGE` (also published as `ghcr.io/finsys/dockhand`).
- **Source:** [`fnsys/dockhand`](https://hub.docker.com/r/fnsys/dockhand) on Docker Hub, [`Finsys/dockhand`](https://github.com/Finsys/dockhand) on GitHub. Business Source License 1.1; each version converts to Apache 2.0 four years after release.
- **Breaking signals:** first boot drives Dockhand through its HTTP API, so any change to these breaks it. Breakage fails closed: Dockhand stays on `127.0.0.1` and `journalctl -u initial-startup` shows the failing call.
  - `GET`/`POST /api/environments` (socket environment)
  - `POST /api/settings/general` (`externalStackPaths`, `defaultTimezone`)
  - `POST /api/environments/{id}/update-check` (`cron`, `autoUpdate`, `vulnerabilityCriteria: more_than_current`)
  - `GET`/`POST /api/notifications`, `POST /api/environments/{id}/notifications` (event types `auto_update_success`, `auto_update_failed`, `auto_update_blocked`)
  - `POST /api/stacks/scan` and `/api/stacks/adopt`
  - `GET`/`POST /api/users`: creating the first user without a session while no admin exists, and that user becoming Admin
  - `PUT /api/auth/settings` (`authEnabled`)
  - anonymous API requests returning 401 once authentication is on
  - the `DATA_DIR` and `STACKS_DIR` environment variables, and the 8-character password minimum the wizard mirrors
- **Bump by hand:** change `DOCKHAND_TAG`, then render the heredocs and run `initial-startup.sh` against the new image on a scratch Docker host to confirm first boot still completes. On existing VMs, use Dockhand's own self-update, then set the same tag in `/opt/dockhand/compose.yaml`.

### `louislam/dockge`

- **Pinned at:** `DOCKGE_TAG` default (currently `1.5.0`). Optional: only installed when chosen in Advanced settings.
- **Source:** [`louislam/dockge`](https://hub.docker.com/r/louislam/dockge) on Docker Hub, [GitHub releases](https://github.com/louislam/dockge/releases)
- **Breaking signals:** major-version bumps; data-model changes documented in the release notes under "Migration" or "Breaking". Dockge's stack-folder layout is stable, but the UI auth model has moved before.
- **Bundled Compose:** Dockge runs its own copy of Docker Compose (v2.34.0 in 1.5.0), not the VM's `docker-compose-plugin`. When the two versions compute different `com.docker.compose.config-hash` values, a `docker compose up` from either side recreates every container the other side last created. On a bump, compare `docker exec dockge docker compose version` with `docker compose version` on the VM.
- **Bump by hand:** change the `DOCKGE_TAG` default, re-render `dockge-compose.yml` locally with the heredoc. On existing VMs, edit the tag in `/opt/stacks/dockge/compose.yaml` and `docker compose up -d` there.

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
