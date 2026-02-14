#!/usr/bin/env bats

load '../helpers/test_helper.bash'

setup() {
  setup_test_paths
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
