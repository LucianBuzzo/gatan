#!/usr/bin/env bats

load '../helpers/test_helper.bash'

setup() {
  setup_test_paths
}

teardown() {
  teardown_mock_bin
}

@test "core_collect_sorted_listeners normalizes and sorts rows" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/constants.sh"
    source "$PROJECT_ROOT/lib/gatan/core.sh"

    core_raw_lsof() {
      cat "$PROJECT_ROOT/test/helpers/fixtures/lsof-listen.txt"
    }

    core_collect_sorted_listeners
  '

  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = $'nginx\t90\troot\t6u\t127.0.0.1:80\t80\t127.0.0.1\tTCP' ]
  [ "${lines[1]}" = $'node\t321\talice\t22u\t*:3000\t3000\t*\tTCP' ]
  [ "${lines[2]}" = $'python\t322\talice\t8u\t[::1]:8080\t8080\t[::1]\tTCP' ]
}

@test "core_raw_lsof requests full command names from lsof" {
  setup_mock_bin

  write_mock sudo <<'EOF_SUDO'
#!/usr/bin/env bash
exec "$@"
EOF_SUDO

  write_mock lsof <<'EOF_LSOF'
#!/usr/bin/env bash
for arg in "$@"; do
  printf '<%s>\n' "$arg"
done >"$GATAN_ARGS_LOG"
echo "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"
EOF_LSOF

  run env PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN:$PATH" bash -c '
    source "$PROJECT_ROOT/lib/gatan/core.sh"
    GATAN_ARGS_LOG="$(mktemp)"
    export GATAN_ARGS_LOG
    core_raw_lsof >/dev/null
    cat "$GATAN_ARGS_LOG"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"<+c>"* ]]
  [[ "$output" == *"<0>"* ]]
  [[ "$output" == *"<-iTCP>"* ]]
  [[ "$output" == *"<-sTCP:LISTEN>"* ]]
}
