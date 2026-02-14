#!/usr/bin/env bats

load '../helpers/test_helper.bash'

setup() {
  setup_test_paths
}

@test "ui_read_key parses arrow down" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"
    printf "\033[B" | ui_read_key 0.1
  '

  [ "$status" -eq 0 ]
  [ "$output" = "DOWN" ]
}

@test "ui_read_key parses enter" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"
    printf "\n" | ui_read_key 0.1
  '

  [ "$status" -eq 0 ]
  [ "$output" = "ENTER" ]
}
