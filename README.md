# Gatan

Gatan is a macOS Bash utility for inspecting services bound to TCP ports.

When you run `gatan`, it prompts for sudo once, opens a full-screen terminal UI, and lets you:

- Browse listening TCP processes
- Inspect process details
- Terminate a selected process (SIGTERM, then optional SIGKILL)

## Requirements

- macOS 12+
- `sudo`
- `lsof`
- `awk`
- `ps`
- `kill`
- `tput`
- `stty`

## Installation (bpkg)

```bash
bpkg install lucianbuzzo/gatan
```

## Usage

```bash
gatan
gatan --help
gatan --version
```

## Keybindings

- `Up` / `Down`: move selection
- `Enter`: inspect selected process
- `k`: kill selected process
- `r`: refresh list/details
- `b`: back from inspect view
- `q`: quit

## Kill Semantics

1. Confirm `SIGTERM` with `y/N` prompt.
2. If still running, optional `SIGKILL` confirmation.

## Development

### Conventional Commits

Commits are enforced in CI using Conventional Commits.

Examples:

- `feat: add inspect view`
- `fix: handle empty listener table`
- `chore: update ci workflow`

See `CONTRIBUTING.md` for details.

To enforce this locally:

```bash
git config core.hooksPath .githooks
```

### Releases

Versioning and releases are managed by `release-please`.

- Merges to `main` update/open a release PR.
- Merging the release PR updates `VERSION`/`CHANGELOG.md`, creates a tag, and publishes a GitHub release.
