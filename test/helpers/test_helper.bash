#!/usr/bin/env bash

setup_test_paths() {
  # shellcheck disable=SC2034
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

setup_mock_bin() {
  MOCK_BIN="$(mktemp -d "${BATS_TEST_TMPDIR}/gatan-mock.XXXXXX")"
  export MOCK_BIN
}

teardown_mock_bin() {
  if [ -n "${MOCK_BIN:-}" ] && [ -d "$MOCK_BIN" ]; then
    rm -rf "$MOCK_BIN"
  fi
}

write_mock() {
  local name="$1"

  cat >"$MOCK_BIN/$name"
  chmod +x "$MOCK_BIN/$name"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"

  case "$haystack" in
    *"$needle"*) return 0 ;;
    *)
      echo "expected output to contain: $needle" >&2
      return 1
      ;;
  esac
}
