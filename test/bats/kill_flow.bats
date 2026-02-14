#!/usr/bin/env bats

load '../helpers/test_helper.bash'

setup() {
  setup_test_paths
}

@test "app_kill_pid sends SIGTERM when process exits" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/bin/gatan"

    ui_prompt_yes_no() { return 0; }
    actions_send_signal() {
      [ "$1" = "TERM" ] && [ "$2" = "222" ]
    }
    actions_wait_for_exit() { return 0; }

    app_kill_pid "222" "node"
    printf "%s\n" "$APP_STATUS_MESSAGE"
  '

  [ "$status" -eq 0 ]
  [ "$output" = "Sent SIGTERM to PID 222." ]
}

@test "app_kill_pid escalates to SIGKILL" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/bin/gatan"

    ui_prompt_yes_no() { return 0; }
    SIGNALS=""
    actions_send_signal() {
      SIGNALS="${SIGNALS}${1},"
      return 0
    }
    WAIT_COUNT=0
    actions_wait_for_exit() {
      WAIT_COUNT=$((WAIT_COUNT + 1))
      if [ "$WAIT_COUNT" -eq 1 ]; then
        return 1
      fi
      return 0
    }

    app_kill_pid "333" "ruby"
    printf "%s\n" "$SIGNALS"
    printf "%s\n" "$APP_STATUS_MESSAGE"
  '

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "TERM,KILL," ]
  [ "${lines[1]}" = "Sent SIGKILL to PID 333." ]
}

@test "app_kill_pid cancels when user declines" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/bin/gatan"

    ui_prompt_yes_no() { return 1; }
    actions_send_signal() {
      echo "unexpected"
      return 1
    }

    app_kill_pid "444" "python"
    printf "%s\n" "$APP_STATUS_MESSAGE"
  '

  [ "$status" -eq 0 ]
  [ "$output" = "Cancelled termination for PID 444." ]
}
