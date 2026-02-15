#!/usr/bin/env bats

load '../helpers/test_helper.bash'

setup() {
  setup_test_paths
  setup_mock_bin
}

teardown() {
  teardown_mock_bin
}

@test "actions_inspect returns process details and open files" {
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

  write_mock ps <<'EOF_PS'
#!/usr/bin/env bash
echo "123 1 alice /usr/bin/node /Users/alice/app/server.js"
EOF_PS

  write_mock lsof <<'EOF_LSOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-a" ]; then
  cat <<'OUT'
p123
fcwd
n/Users/alice/app
OUT
  exit 0
fi

if [ "${1:-}" = "-p" ]; then
  cat <<'OUT'
COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
node 123 alice cwd DIR 1,4 512 123 /Users/alice/app
node 123 alice txt REG 1,4 4096 124 /usr/bin/node
OUT
  exit 0
fi
EOF_LSOF

  run env PATH="$MOCK_BIN:$PATH" PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/constants.sh"
    source "$PROJECT_ROOT/lib/gatan/actions.sh"
    actions_inspect 123
  '

  [ "$status" -eq 0 ]
  assert_contains "$output" "PID      123"
  assert_contains "$output" "PPID     1"
  assert_contains "$output" "USER     alice"
  assert_contains "$output" "COMMAND  /usr/bin/node /Users/alice/app/server.js"
  assert_contains "$output" "CWD      /Users/alice/app"
  assert_contains "$output" "Open files (first"
}
