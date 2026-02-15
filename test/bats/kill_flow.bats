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

@test "app_set_status marks redraw and status can expire" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/bin/gatan"

    APP_NEEDS_REDRAW=0
    app_set_status "Temporary" 1
    printf "redraw=%s status=%s\n" "$APP_NEEDS_REDRAW" "$APP_STATUS_MESSAGE"

    APP_STATUS_EXPIRES_AT=$(( $(date +%s) - 1 ))
    if app_expire_status_if_needed; then
      printf "expired=%s status=%s\n" "yes" "$APP_STATUS_MESSAGE"
    else
      printf "expired=%s status=%s\n" "no" "$APP_STATUS_MESSAGE"
    fi
  '

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "redraw=1 status=Temporary" ]
  [ "${lines[1]}" = "expired=yes status=Ready." ]
}

@test "app_validate_sudo shows explainer and uses custom sudo prompt when needed" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/bin/gatan"

    prompted=0
    ui_prompt_sudo_explainer() {
      [ "$1" = "$GATAN_SUDO_PROMPT" ]
      prompted=1
      return 0
    }
    ui_restore_terminal() {
      :
    }
    ui_init_terminal() {
      :
    }
    sudo() {
      if [ "${1:-}" = "-n" ] && [ "${2:-}" = "true" ]; then
        return 1
      fi
      if [ "${1:-}" = "-v" ] && [ "${2:-}" = "-p" ]; then
        printf "sudo_prompt=%s\n" "${3:-}"
        return 0
      fi
      return 1
    }

    app_validate_sudo
    printf "rc=%s prompted=%s\n" "$?" "$prompted"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"sudo_prompt=[gatan] Administrator password: "* ]]
  [[ "$output" == *"rc=0 prompted=1"* ]]
}
