#!/usr/bin/env bash

actions_get_process_summary() {
  local pid="$1"

  ps -o pid= -o ppid= -o user= -o command= -p "$pid" 2>/dev/null | awk '
    NR == 1 {
      pid = $1
      ppid = $2
      user = $3

      $1 = ""
      $2 = ""
      $3 = ""
      sub(/^[[:space:]]+/, "", $0)

      printf "%s\t%s\t%s\t%s\n", pid, ppid, user, $0
      exit
    }
  '
}

actions_get_cwd() {
  local pid="$1"
  local cwd

  cwd="$(sudo lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | awk '
    /^n/ {
      sub(/^n/, "", $0)
      print $0
      exit
    }
  ')"

  if [ -n "$cwd" ]; then
    printf '%s\n' "$cwd"
    return 0
  fi

  printf '%s\n' "-"
}

actions_get_open_files() {
  local pid="$1"

  sudo lsof -p "$pid" 2>/dev/null | head -n "$((GATAN_OPEN_FILES_LIMIT + 1))"
}

actions_get_cpu_percent() {
  local pid="$1"

  ps -o %cpu= -p "$pid" 2>/dev/null | awk '
    NR == 1 {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      print $0
      exit
    }
  '
}

actions_get_top_snapshot() {
  local pid="$1"
  local snapshot
  local row
  local value_pid
  local value_user
  local value_command
  local value_cpu
  local value_mem
  local value_time
  local value_threads
  local value_state
  local cpu_from_ps

  if ! command -v top >/dev/null 2>&1; then
    printf '%s\n' "(top unavailable)"
    return 0
  fi

  # macOS: capture a single top sample for the target PID.
  snapshot="$(top -l 1 -pid "$pid" -stats pid,command,cpu,mem,time,threads,state 2>/dev/null || true)"
  if [ -z "$snapshot" ]; then
    # Fallback for environments where macOS flags are not supported.
    snapshot="$(top -b -n 1 -p "$pid" 2>/dev/null || true)"
  fi
  if [ -z "$snapshot" ]; then
    printf '%s\n' "(top snapshot unavailable)"
    return 0
  fi

  row="$(printf '%s\n' "$snapshot" | awk -v pid="$pid" '$1 == pid { print; exit }')"
  if [ -z "$row" ]; then
    printf '%s\n' "(top snapshot unavailable)"
    return 0
  fi

  # shellcheck disable=SC2086
  set -- $row
  if [ "$#" -ge 12 ]; then
    value_pid="$1"
    value_user="$2"
    value_state="$8"
    value_cpu="$9"
    value_mem="${10}"
    value_time="${11}"
    value_command="${12}"

    cpu_from_ps="$(actions_get_cpu_percent "$pid")"
    if [[ "$cpu_from_ps" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      value_cpu="$cpu_from_ps"
    fi

    printf '%-10s  %s\n' "PID" "$value_pid"
    printf '%-10s  %s\n' "USER" "$value_user"
    printf '%-10s  %s\n' "COMMAND" "$value_command"
    printf '%-10s  %s\n' "CPU" "$value_cpu"
    printf '%-10s  %s\n' "MEM" "$value_mem"
    printf '%-10s  %s\n' "TIME" "$value_time"
    printf '%-10s  %s\n' "STATE" "$value_state"
    return 0
  fi

  if [ "$#" -ge 7 ]; then
    value_pid="$1"
    value_command="$2"
    value_cpu="$3"
    value_mem="$4"
    value_time="$5"
    value_threads="$6"
    value_state="$7"

    cpu_from_ps="$(actions_get_cpu_percent "$pid")"
    if [[ "$cpu_from_ps" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      value_cpu="$cpu_from_ps"
    fi

    printf '%-10s  %s\n' "PID" "$value_pid"
    printf '%-10s  %s\n' "COMMAND" "$value_command"
    printf '%-10s  %s\n' "CPU" "$value_cpu"
    printf '%-10s  %s\n' "MEM" "$value_mem"
    printf '%-10s  %s\n' "TIME" "$value_time"
    printf '%-10s  %s\n' "THREADS" "$value_threads"
    printf '%-10s  %s\n' "STATE" "$value_state"
    return 0
  fi

  printf '%s\n' "(top snapshot unavailable)"
}

actions_inspect_static() {
  local pid="$1"
  local summary
  local info_pid
  local info_ppid
  local info_user
  local info_command
  local cwd
  local open_files

  summary="$(actions_get_process_summary "$pid")"
  if [ -z "$summary" ]; then
    return 1
  fi

  IFS=$'\t' read -r info_pid info_ppid info_user info_command <<EOF_SUMMARY
$summary
EOF_SUMMARY

  cwd="$(actions_get_cwd "$pid")"
  open_files="$(actions_get_open_files "$pid")"

  printf '%-8s %s\n' "PID" "$info_pid"
  printf '%-8s %s\n' "PPID" "$info_ppid"
  printf '%-8s %s\n' "USER" "$info_user"
  printf '%-8s %s\n' "COMMAND" "$info_command"
  printf '%-8s %s\n' "CWD" "$cwd"
  printf '\nOpen files (first %s):\n' "$GATAN_OPEN_FILES_LIMIT"

  if [ -n "$open_files" ]; then
    printf '%s\n' "$open_files"
  else
    printf '%s\n' "(no open files data)"
  fi
}

actions_inspect() {
  local pid="$1"
  local top_snapshot

  actions_inspect_static "$pid" || return 1
  top_snapshot="$(actions_get_top_snapshot "$pid")"

  printf '\nTop snapshot (PID %s):\n' "$pid"
  printf '%s\n' "$top_snapshot"
}

actions_send_signal() {
  local signal_name="$1"
  local pid="$2"

  sudo kill "-$signal_name" "$pid" 2>/dev/null
}

actions_pid_exists() {
  local pid="$1"

  sudo kill -0 "$pid" >/dev/null 2>&1
}

actions_wait_for_exit() {
  local pid="$1"
  local attempts="${2:-$GATAN_TERM_WAIT_ATTEMPTS}"
  local interval="${3:-$GATAN_TERM_WAIT_INTERVAL}"
  local i

  for ((i = 0; i < attempts; i++)); do
    if ! actions_pid_exists "$pid"; then
      return 0
    fi
    sleep "$interval"
  done

  return 1
}
