#!/usr/bin/env bash

UI_ACTIVE=0
UI_STTY_ORIG=""

ui_read_timeout() {
  local timeout="${1:-1}"

  # macOS system bash 3.2 only accepts integer read timeouts.
  if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ] && [[ "$timeout" == *.* ]]; then
    printf '1\n'
    return 0
  fi

  printf '%s\n' "$timeout"
}

ui_init_terminal() {
  if [ "$UI_ACTIVE" -eq 1 ]; then
    return 0
  fi

  UI_STTY_ORIG="$(stty -g 2>/dev/null || true)"
  tput smcup >/dev/null 2>&1 || true
  tput civis >/dev/null 2>&1 || true
  UI_ACTIVE=1
}

ui_restore_terminal() {
  if [ "$UI_ACTIVE" -eq 0 ]; then
    return 0
  fi

  if [ -n "$UI_STTY_ORIG" ]; then
    stty "$UI_STTY_ORIG" >/dev/null 2>&1 || true
  fi

  tput cnorm >/dev/null 2>&1 || true
  tput rmcup >/dev/null 2>&1 || true
  UI_ACTIVE=0
}

ui_read_key() {
  local timeout="${1:-0.2}"
  local read_timeout
  local seq_timeout
  local key
  local seq

  read_timeout="$(ui_read_timeout "$timeout")"
  seq_timeout="$(ui_read_timeout "0.001")"

  IFS= read -rsn1 -t "$read_timeout" key || return 1

  if [ "$key" = $'\x1b' ]; then
    IFS= read -rsn1 -t "$seq_timeout" seq || {
      printf 'ESC\n'
      return 0
    }

    if [ "$seq" = "[" ]; then
      IFS= read -rsn1 -t "$seq_timeout" seq || {
        printf 'ESC\n'
        return 0
      }

      case "$seq" in
        A) printf 'UP\n' ;;
        B) printf 'DOWN\n' ;;
        C) printf 'RIGHT\n' ;;
        D) printf 'LEFT\n' ;;
        *) printf 'ESC\n' ;;
      esac
      return 0
    fi

    printf 'ESC\n'
    return 0
  fi

  case "$key" in
    "" | $'\n' | $'\r') printf 'ENTER\n' ;;
    q | Q) printf 'Q\n' ;;
    r | R) printf 'R\n' ;;
    k | K) printf 'K\n' ;;
    b | B) printf 'B\n' ;;
    y | Y) printf 'Y\n' ;;
    n | N) printf 'N\n' ;;
    j | J) printf 'DOWN\n' ;;
    *) printf '%s\n' "$key" ;;
  esac
}

ui_truncate() {
  local text="$1"
  local width="$2"

  if [ "$width" -le 0 ]; then
    printf ''
    return 0
  fi

  if [ "${#text}" -le "$width" ]; then
    printf '%s' "$text"
    return 0
  fi

  if [ "$width" -eq 1 ]; then
    printf '%s' "${text:0:1}"
    return 0
  fi

  printf '%s~' "${text:0:$((width - 1))}"
}

ui_pad() {
  local text="$1"
  local width="$2"
  local truncated

  truncated="$(ui_truncate "$text" "$width")"
  printf "%-${width}s" "$truncated"
}

ui_render_main() {
  local selected_index="$1"
  local scroll_index="$2"
  local status_message="$3"
  local term_rows
  local term_cols
  local table_rows
  local total_rows
  local header_rows=4
  local footer_rows=2
  local port_w=6
  local pid_w=8
  local user_w=12
  local command_w=24
  local bind_w
  local i
  local row_index

  term_rows="$(tput lines 2>/dev/null || printf '24')"
  term_cols="$(tput cols 2>/dev/null || printf '80')"
  table_rows=$((term_rows - header_rows - footer_rows))
  if [ "$table_rows" -lt 1 ]; then
    table_rows=1
  fi

  bind_w=$((term_cols - port_w - pid_w - user_w - command_w - 8))
  if [ "$bind_w" -lt 8 ]; then
    bind_w=8
    command_w=$((term_cols - port_w - pid_w - user_w - bind_w - 8))
    if [ "$command_w" -lt 10 ]; then
      command_w=10
    fi
  fi

  total_rows="${#APP_ROWS[@]}"

  printf '\033[H\033[2J'
  tput bold >/dev/null 2>&1 || true
  printf '%s %s | TCP listeners: %s\n' "$GATAN_APP_NAME" "$(gatan_version)" "$total_rows"
  tput sgr0 >/dev/null 2>&1 || true
  printf 'Keys: Up/Down move  Enter inspect  k kill  r refresh  q quit\n'
  printf '\n'

  tput bold >/dev/null 2>&1 || true
  printf '%s %s %s %s %s\n' \
    "$(ui_pad 'PORT' "$port_w")" \
    "$(ui_pad 'PID' "$pid_w")" \
    "$(ui_pad 'USER' "$user_w")" \
    "$(ui_pad 'COMMAND' "$command_w")" \
    "$(ui_pad 'BIND' "$bind_w")"
  tput sgr0 >/dev/null 2>&1 || true

  if [ "$total_rows" -eq 0 ]; then
    printf '%s\n' "No listening TCP processes found."
    for ((i = 1; i < table_rows; i++)); do
      printf '\n'
    done
  else
    for ((i = 0; i < table_rows; i++)); do
      local row
      local command
      local pid
      local user
      local port
      local bind
      local line

      row_index=$((scroll_index + i))
      if [ "$row_index" -ge "$total_rows" ]; then
        printf '\n'
        continue
      fi

      row="${APP_ROWS[$row_index]}"
      IFS=$'\t' read -r command pid user _ _ port bind _ <<EOF_ROW
$row
EOF_ROW

      if [ -z "$port" ]; then
        port='-'
      fi

      line="$(ui_pad "$port" "$port_w") $(ui_pad "$pid" "$pid_w") $(ui_pad "$user" "$user_w") $(ui_pad "$command" "$command_w") $(ui_pad "$bind" "$bind_w")"
      line="$(ui_truncate "$line" "$term_cols")"

      if [ "$row_index" -eq "$selected_index" ]; then
        tput rev >/dev/null 2>&1 || true
        printf '%s\n' "$line"
        tput sgr0 >/dev/null 2>&1 || true
      else
        printf '%s\n' "$line"
      fi
    done
  fi

  printf '\n'
  printf '%s' "$(ui_truncate "$status_message" "$term_cols")"
}

ui_render_inspect() {
  local pid="$1"
  local command="$2"
  local status_message="$3"
  local content="${APP_INSPECT_CONTENT:-}"
  local term_rows
  local term_cols
  local body_rows
  local i=0

  term_rows="$(tput lines 2>/dev/null || printf '24')"
  term_cols="$(tput cols 2>/dev/null || printf '80')"
  body_rows=$((term_rows - 5))
  if [ "$body_rows" -lt 1 ]; then
    body_rows=1
  fi

  printf '\033[H\033[2J'
  tput bold >/dev/null 2>&1 || true
  printf 'Inspect PID %s (%s)\n' "$pid" "$(ui_truncate "$command" 40)"
  tput sgr0 >/dev/null 2>&1 || true
  printf 'Keys: b back  k kill  r refresh  q quit\n'
  printf '\n'

  if [ -z "$content" ]; then
    content='No process details available.'
  fi

  while IFS= read -r line; do
    if [ "$i" -ge "$body_rows" ]; then
      break
    fi

    printf '%s\n' "$(ui_truncate "$line" "$term_cols")"
    i=$((i + 1))
  done <<EOF_CONTENT
$content
EOF_CONTENT

  for (( ; i < body_rows; i++)); do
    printf '\n'
  done

  printf '%s' "$(ui_truncate "$status_message" "$term_cols")"
}

ui_prompt_yes_no() {
  local prompt="$1"
  local term_rows
  local term_cols
  local key

  term_rows="$(tput lines 2>/dev/null || printf '24')"
  term_cols="$(tput cols 2>/dev/null || printf '80')"

  while true; do
    tput cup "$((term_rows - 1))" 0 >/dev/null 2>&1 || true
    tput el >/dev/null 2>&1 || true
    printf '%s' "$(ui_truncate "$prompt" "$term_cols")"

    key="$(ui_read_key 0.1 || true)"
    if [ -z "$key" ]; then
      continue
    fi

    case "$key" in
      Y) return 0 ;;
      N | ENTER | Q | ESC) return 1 ;;
    esac
  done
}
