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

actions_inspect() {
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
