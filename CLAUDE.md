# Working on docker-pve

These rules apply to every change in this repository, whoever makes it.

## Versioning: Semantic Versioning 2.0.0

Releases follow [SemVer 2.0.0](https://semver.org/spec/v2.0.0.html). Tags are `vMAJOR.MINOR.PATCH` (for example `v2.1.0`), annotated, and placed on the merge commit in `main`.

The **public interface** that SemVer protects is everything a user relies on when they run the script:

- the one-liner in the README and the script's name and path (`docker-stack-vm.sh`);
- the wizard: its modes (Default and Advanced), prompts, choices and defaults;
- the environment variables it reads: `DIAGNOSTICS`, `API_FUNC_REF`, `DOCKHAND_IMAGE`, `DOCKHAND_TAG`, `DOCKGE_TAG`;
- what the VM it creates contains: the installed services and their ports (Dockhand 3000, Dockge 5001), the `deploy` user (uid 1000, in the `docker` group), the paths `/opt/stacks`, `/opt/dockhand` and `/opt/stacks/dockge`, and the `initial-startup.service` first-boot behaviour;
- anything the paired [qbittorrent-vpn-docker](https://github.com/rob-paprocki/qbittorrent-vpn-docker) stack depends on (the `/opt/stacks` location, uid/gid 1000, `git` and `python3-venv` on the VM).

Pick the bump from the most significant change in the release:

| Bump | When | Examples |
|---|---|---|
| MAJOR | Re-running the documented command gives a VM that no longer works the way the README said it would, or a documented prompt, option, variable, port, path or default is removed or changes meaning | Changing the default manager; removing Watchtower; moving `/opt/stacks` |
| MINOR | New functionality that leaves every existing command and default working | A new wizard option; a new optional service; a new override variable |
| PATCH | Fixes, docs, CI, and dependency pin bumps that don't change documented behaviour | A bug fix; a Dockhand tag bump with no behaviour change; README corrections |

A dependency bump that changes documented behaviour (a port, a path, a default, a login flow) is MINOR or MAJOR, not PATCH. While a change is only on `main` and not released, it sits under `[Unreleased]` in the changelog.

## Changelog: Keep a Changelog 1.1.0

`CHANGELOG.md` follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).

- Every PR that changes anything a user could notice adds a line under `## [Unreleased]` in the same PR. CI-only and repo-housekeeping changes may skip it.
- Group entries under `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` and `Security`, in that order, omitting empty groups.
- Write entries for the person running the script, not for a reviewer: say what changed for them and what, if anything, they need to do. Link the PR as `([#12](https://github.com/rob-paprocki/docker-pve/pull/12))`.
- Breaking changes start with **BREAKING:** and say how to adapt.
- Keep the link references at the bottom (`[Unreleased]: …/compare/vX.Y.Z...HEAD`, `[X.Y.Z]: …/compare/vA.B.C...vX.Y.Z`) up to date.

### Cutting a release

1. Move the `[Unreleased]` entries into a new `## [X.Y.Z] - YYYY-MM-DD` section (ISO date) and update the link references, in a PR of its own or as the last commit of the PR being released.
2. After it merges, tag the merge commit: `git tag -a vX.Y.Z -m "vX.Y.Z" <sha>` and push the tag.
3. Create a GitHub Release for the tag, with that version's changelog section as the notes.

Never re-tag or move a published tag. If a release is wrong, publish a new PATCH.

## README

The README is the project's front page, so it should be more than a wall of text. When you change behaviour, update the README in the same PR. Use these as the reference for what a good README covers:

- [banesullivan/README](https://github.com/banesullivan/README)
- [Utrecht University: README files](https://utrechtuniversity.github.io/workshop-computational-reproducibility/chapters/readme-files.html)
- [CodeRefinery: Writing good README files](https://coderefinery.github.io/documentation/writing-readme-files/)
- [UK Government Analysis Function: Project documentation](https://best-practice-and-impact.github.io/qa-of-code-guidance/project_documentation.html)

Keep these elements, and add them when they're missing:

- badges (licence, latest release, CI) at the top;
- one sentence saying what the project is for, then a short paragraph on who it's for and what problem it solves;
- a highlights list;
- a diagram where it explains the architecture or flow better than prose (see **Images and diagrams** below);
- a quick start someone can copy and paste, with its requirements;
- usage and configuration, using tables for options and defaults;
- troubleshooting or FAQ, using `<details>` blocks for long answers;
- how to get help, how to contribute, the licence, and credits.

Use GitHub alerts (`> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`, `> [!WARNING]`, `> [!CAUTION]`) for things a reader must not miss, and sparingly.

### Images and diagrams

- **No Mermaid**, or any other diagram that GitHub draws in the browser. The GitHub mobile app shows those as raw code. A diagram is a committed image, generated from a source file kept in the repository with a free and open-source tool, and the command that regenerates it is written next to the source.
- **Every image must suit the reader's theme**, light or dark, on github.com and in the GitHub mobile app. That covers diagrams, screenshots, logos and badges. Before merging, look at each one in both themes on a phone-width screen.

## Writing anything a user will read

User-facing text here means the README and other docs, `CHANGELOG.md`, release notes, the GitHub description and topics, PR and issue text, and the prompts and messages the script shows.

1. Write the first draft.
2. Run the **humanizer** skill on it: follow `.claude/skills/humanizer/SKILL.md`, and run `python3 .claude/skills/humanizer/scripts/copy_scan.py <file>` from the repo root.
3. Then run the **structural-humanizer** skill on the result: follow `.claude/skills/structural-humanizer/SKILL.md`, and run `python3 .claude/skills/structural-humanizer/scripts/structural_scan.py <file>`.
4. Re-check every fact the edits touched (versions, ports, paths, commands, defaults) against the code. Polish must never change what the text claims.

The two skills are vendored from [NulightJens/humanizer-stack](https://github.com/NulightJens/humanizer-stack) at commit `13f5c02`, under its MIT licence (`.claude/skills/HUMANIZER-STACK-LICENSE`, attribution in `.claude/skills/HUMANIZER-STACK-ATTRIBUTION.md`). Update them by copying a newer commit over the top and recording the new commit here.

## Repository metadata

The GitHub description (one sentence, under about 120 characters) and topics must match what `main` does. When a change makes either one wrong (a new default manager, a dropped component, a new platform), update them when the PR merges. Description text goes through the same humanizer passes as other user-facing text.
