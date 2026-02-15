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

@test "app_load_inspect returns quickly with loading live metrics" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/bin/gatan"

    APP_INSPECT_PID="123"
    actions_inspect_static() {
      printf "PID      123\n"
    }
    actions_get_live_metrics_snapshot() {
      sleep 0.2
      printf "PID 123\nCPU 1.0\n"
    }

    app_load_inspect "123"
    rc="$?"
    has_loading=0
    has_job=0
    [[ "$APP_INSPECT_CONTENT" == *"(loading...)"* ]] && has_loading=1
    has_live_label=0
    [[ "$APP_INSPECT_CONTENT" == *"Live metrics (PID"* ]] && has_live_label=1
    if [ -n "$APP_INSPECT_TOP_JOB_PID" ]; then
      has_job=1
    fi
    printf "rc=%s loading=%s job=%s live_label=%s\n" "$rc" "$has_loading" "$has_job" "$has_live_label"
    app_stop_inspect_top_refresh
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=0 loading=1 job=1 live_label=0"* ]]
}

@test "app_poll_inspect_top_refresh updates inspect content with snapshot" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/bin/gatan"

    APP_VIEW="inspect"
    APP_INSPECT_PID="123"
    actions_inspect_static() {
      printf "PID      123\n"
    }
    actions_get_live_metrics_snapshot() {
      printf "PID 123\nCPU 1.0\n"
    }

    app_load_inspect "123"
    for _ in 1 2 3 4 5; do
      app_poll_inspect_top_refresh || true
      if [ -z "$APP_INSPECT_TOP_JOB_PID" ]; then
        break
      fi
      sleep 0.05
    done

    has_snapshot=0
    [[ "$APP_INSPECT_CONTENT" == *"CPU"*1.0* ]] && has_snapshot=1
    job_done=0
    if [ -z "$APP_INSPECT_TOP_JOB_PID" ]; then
      job_done=1
    fi
    printf "job_done=%s snapshot=%s\n" "$job_done" "$has_snapshot"
    app_stop_inspect_top_refresh
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"job_done=1 snapshot=1"* ]]
}

@test "app_request_main_refresh starts async job and sets notify flag" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/bin/gatan"

    core_collect_sorted_listeners() {
      printf "node\t123\talice\t22u\t*:3000\t3000\t*\tTCP\n"
    }

    app_request_main_refresh 1
    has_job=0
    if [ -n "$APP_MAIN_REFRESH_JOB_PID" ]; then
      has_job=1
    fi
    printf "has_job=%s notify=%s\n" "$has_job" "$APP_MAIN_REFRESH_NOTIFY_ON_COMPLETE"
    app_stop_main_refresh
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"has_job=1 notify=1"* ]]
}

@test "app_poll_main_refresh applies rows and emits completion status" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/bin/gatan"

    core_collect_sorted_listeners() {
      printf "node\t123\talice\t22u\t*:3000\t3000\t*\tTCP\n"
    }

    APP_ROWS=($'\''old\t1\troot\t1u\t*:1\t1\t*\tTCP'\'')
    app_request_main_refresh 1

    for _ in 1 2 3 4 5; do
      app_poll_main_refresh "$(app_now_millis)" || true
      if [ -z "$APP_MAIN_REFRESH_JOB_PID" ]; then
        break
      fi
      sleep 0.05
    done

    printf "rows=%s status=%s\n" "${#APP_ROWS[@]}" "$APP_STATUS_MESSAGE"
    app_stop_main_refresh
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"rows=1 status=Refreshed listener list."* ]]
}
