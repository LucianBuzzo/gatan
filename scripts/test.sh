#!/usr/bin/env bash

set -euo pipefail

if ! command -v bats >/dev/null 2>&1; then
  echo "bats is required to run tests" >&2
  exit 1
fi

project_root="$(cd "$(dirname "$0")/.." && pwd)"

bats "$project_root/test/bats"
