#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
prefix="${PREFIX:-/usr/local}"

mkdir -p "$prefix/bin"
mkdir -p "$prefix/lib/gatan"

cp -f "$project_root/bin/gatan" "$prefix/bin/gatan"
cp -f "$project_root/lib/gatan/"*.sh "$prefix/lib/gatan/"
cp -f "$project_root/VERSION" "$prefix/VERSION"
chmod +x "$prefix/bin/gatan"
