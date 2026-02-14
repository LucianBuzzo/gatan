#!/usr/bin/env bats

load '../helpers/test_helper.bash'

setup() {
  setup_test_paths
}

teardown() {
  teardown_mock_bin
}

@test "--help prints usage" {
  run bash "$PROJECT_ROOT/bin/gatan" --help

  [ "$status" -eq 0 ]
  assert_contains "$output" "Usage: gatan"
}

@test "--version matches VERSION file" {
  local expected

  expected="$(tr -d '[:space:]' <"$PROJECT_ROOT/VERSION")"
  run bash "$PROJECT_ROOT/bin/gatan" --version

  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "unknown option fails" {
  run bash "$PROJECT_ROOT/bin/gatan" --unknown

  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown option"
}

@test "fails when required commands are unavailable" {
  run env PATH="/tmp/definitely-not-a-path" /bin/bash "$PROJECT_ROOT/bin/gatan"

  [ "$status" -ne 0 ]
  assert_contains "$output" "Missing required commands"
}

@test "startup succeeds in test mode with sudo auth" {
  setup_mock_bin

  write_mock sudo <<'EOF_SUDO'
#!/usr/bin/env bash
if [ "${1:-}" = "-v" ]; then
  exit 0
fi
if [ "${1:-}" = "-n" ] && [ "${2:-}" = "true" ]; then
  exit 0
fi
exec "$@"
EOF_SUDO

  write_mock lsof <<'EOF_LSOF'
#!/usr/bin/env bash
echo "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"
EOF_LSOF

  run env PATH="$MOCK_BIN:$PATH" GATAN_TEST_DISABLE_UI=1 bash "$PROJECT_ROOT/bin/gatan"

  [ "$status" -eq 0 ]
}

@test "startup fails when sudo auth fails" {
  setup_mock_bin

  write_mock sudo <<'EOF_SUDO'
#!/usr/bin/env bash
if [ "${1:-}" = "-v" ]; then
  exit 1
fi
if [ "${1:-}" = "-n" ] && [ "${2:-}" = "true" ]; then
  exit 1
fi
exec "$@"
EOF_SUDO

  write_mock lsof <<'EOF_LSOF'
#!/usr/bin/env bash
echo "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"
EOF_LSOF

  run env PATH="$MOCK_BIN:$PATH" GATAN_TEST_DISABLE_UI=1 bash "$PROJECT_ROOT/bin/gatan"

  [ "$status" -ne 0 ]
  assert_contains "$output" "Failed to authenticate with sudo"
}
