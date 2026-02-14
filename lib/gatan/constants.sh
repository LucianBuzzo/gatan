#!/usr/bin/env bash

# shellcheck disable=SC2034
# Shared constants used across gatan modules.
readonly GATAN_APP_NAME="gatan"
readonly GATAN_DEFAULT_VERSION="0.1.0"
readonly GATAN_STATUS_TTL_SECONDS=3
readonly GATAN_SUDO_KEEPALIVE_INTERVAL=50
readonly GATAN_MAIN_FRAME_OVERHEAD=8
readonly GATAN_TERM_WAIT_ATTEMPTS=8
readonly GATAN_TERM_WAIT_INTERVAL=0.1
readonly GATAN_OPEN_FILES_LIMIT=20

# Resolve the repository root relative to this file.
gatan_project_root() {
  local source_path
  local dir

  source_path="${BASH_SOURCE[0]}"
  dir="${source_path%/*}"
  if [ "$dir" = "$source_path" ]; then
    dir="."
  fi

  dir="$(cd "$dir/../.." && pwd)"
  printf '%s\n' "$dir"
}

gatan_version() {
  local version_file

  version_file="$(gatan_project_root)/VERSION"
  if [ -f "$version_file" ]; then
    tr -d '[:space:]' <"$version_file"
    return 0
  fi

  printf '%s\n' "$GATAN_DEFAULT_VERSION"
}
