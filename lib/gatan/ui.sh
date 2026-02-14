#!/usr/bin/env bash

UI_ACTIVE=0
UI_STTY_ORIG=""
UI_INCREMENTAL_SUPPORTED=0
UI_FORCE_FULL_REDRAW=1
UI_FRAME_LINES=()
UI_FRAME_WIDTH=0
UI_FRAME_HEIGHT=0
UI_NEXT_LINES=()
UI_NEXT_WIDTH=0
UI_NEXT_HEIGHT=0

ui_term_emit() {
  local cap="$1"
  shift
  tput "$cap" "$@" 2>/dev/null || true
}

ui_term_code() {
  local cap="$1"
  shift
  tput "$cap" "$@" 2>/dev/null || true
}

ui_reset_frame_cache() {
  UI_FRAME_LINES=()
  UI_FRAME_WIDTH=0
  UI_FRAME_HEIGHT=0
}

ui_force_full_redraw() {
  UI_FORCE_FULL_REDRAW=1
}

ui_detect_incremental_support() {
  if tput cup 0 0 >/dev/null 2>&1 && tput el >/dev/null 2>&1; then
    UI_INCREMENTAL_SUPPORTED=1
  else
    UI_INCREMENTAL_SUPPORTED=0
  fi
}

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
  # Keep input in character mode and disable echo so held keys don't print
  # raw escape bytes like "^[[A" while navigating.
  stty -echo -icanon min 1 time 0 >/dev/null 2>&1 || true
  ui_term_emit smcup
  ui_term_emit civis
  ui_detect_incremental_support
  ui_force_full_redraw
  ui_reset_frame_cache
  UI_ACTIVE=1
}

ui_restore_terminal() {
  if [ "$UI_ACTIVE" -eq 0 ]; then
    return 0
  fi

  if [ -n "$UI_STTY_ORIG" ]; then
    stty "$UI_STTY_ORIG" >/dev/null 2>&1 || true
  fi

  ui_term_emit cnorm
  ui_term_emit rmcup
  ui_reset_frame_cache
  UI_FORCE_FULL_REDRAW=1
  UI_INCREMENTAL_SUPPORTED=0
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

ui_truncate_into() {
  local __var="$1"
  local text="$2"
  local width="$3"
  local __ui_value

  if [ "$width" -le 0 ]; then
    __ui_value=""
  elif [ "${#text}" -le "$width" ]; then
    __ui_value="$text"
  elif [ "$width" -eq 1 ]; then
    __ui_value="${text:0:1}"
  else
    __ui_value="${text:0:$((width - 1))}~"
  fi

  printf -v "$__var" '%s' "$__ui_value"
}

ui_pad_into() {
  local __var="$1"
  local text="$2"
  local width="$3"
  local _ui_truncated
  local _ui_out

  ui_truncate_into _ui_truncated "$text" "$width"
  printf -v _ui_out "%-${width}s" "$_ui_truncated"
  printf -v "$__var" '%s' "$_ui_out"
}

ui_pad_to_width_into() {
  local __var="$1"
  local text="$2"
  local width="$3"
  local len
  local _ui_pad
  local _ui_out

  if [ "$width" -le 0 ]; then
    _ui_out=""
    printf -v "$__var" '%s' "$_ui_out"
    return 0
  fi

  ui_truncate_into _ui_out "$text" "$width"
  len="${#_ui_out}"
  if [ "$len" -lt "$width" ]; then
    printf -v _ui_pad '%*s' "$((width - len))" ''
    _ui_out="${_ui_out}${_ui_pad}"
  fi

  printf -v "$__var" '%s' "$_ui_out"
}

ui_truncate() {
  local out
  ui_truncate_into out "$1" "$2"
  printf '%s' "$out"
}

ui_pad() {
  local out
  ui_pad_into out "$1" "$2"
  printf '%s' "$out"
}

ui_pad_to_width() {
  local out
  ui_pad_to_width_into out "$1" "$2"
  printf '%s' "$out"
}

ui_push_frame_line() {
  local line="$1"
  UI_NEXT_LINES+=("$line")
}

ui_build_main_frame() {
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
  local marker_w=1
  local row
  local command
  local pid
  local user
  local port
  local bind
  local marker
  local line
  local header_line
  local style_bold
  local style_reset
  local style_rev
  local keys_line
  local padded_marker
  local padded_port
  local padded_pid
  local padded_user
  local padded_command
  local padded_bind

  term_rows="$(tput lines 2>/dev/null || printf '24')"
  term_cols="$(tput cols 2>/dev/null || printf '80')"
  table_rows=$((term_rows - header_rows - footer_rows))
  if [ "$table_rows" -lt 1 ]; then
    table_rows=1
  fi

  bind_w=$((term_cols - marker_w - port_w - pid_w - user_w - command_w - 10))
  if [ "$bind_w" -lt 8 ]; then
    bind_w=8
    command_w=$((term_cols - marker_w - port_w - pid_w - user_w - bind_w - 10))
    if [ "$command_w" -lt 10 ]; then
      command_w=10
    fi
  fi

  total_rows="${#APP_ROWS[@]}"

  UI_NEXT_LINES=()
  UI_NEXT_WIDTH="$term_cols"
  UI_NEXT_HEIGHT="$term_rows"

  style_bold="$(ui_term_code bold)"
  style_reset="$(ui_term_code sgr0)"
  style_rev="$(ui_term_code rev)"

  header_line="$GATAN_APP_NAME ${APP_VERSION:-$(gatan_version)} | TCP listeners: $total_rows"
  ui_truncate_into header_line "$header_line" "$term_cols"
  ui_push_frame_line "${style_bold}${header_line}${style_reset}"
  ui_truncate_into keys_line "Keys: Up/Down move  Enter inspect  k kill  r refresh  q quit" "$term_cols"
  ui_push_frame_line "$keys_line"
  ui_push_frame_line ""

  ui_pad_into padded_marker "" "$marker_w"
  ui_pad_into padded_port "PORT" "$port_w"
  ui_pad_into padded_pid "PID" "$pid_w"
  ui_pad_into padded_user "USER" "$user_w"
  ui_pad_into padded_command "COMMAND" "$command_w"
  ui_pad_into padded_bind "BIND" "$bind_w"
  line="$padded_marker $padded_port $padded_pid $padded_user $padded_command $padded_bind"
  ui_truncate_into line "$line" "$term_cols"
  ui_push_frame_line "${style_bold}${line}${style_reset}"

  if [ "$total_rows" -eq 0 ]; then
    ui_truncate_into line "No listening TCP processes found." "$term_cols"
    ui_push_frame_line "$line"
    for ((i = 1; i < table_rows; i++)); do
      ui_push_frame_line ""
    done
  else
    for ((i = 0; i < table_rows; i++)); do
      row_index=$((scroll_index + i))
      if [ "$row_index" -ge "$total_rows" ]; then
        ui_push_frame_line ""
        continue
      fi

      row="${APP_ROWS[$row_index]}"
      IFS=$'\t' read -r command pid user _ _ port bind _ <<EOF_ROW
$row
EOF_ROW

      if [ -z "$port" ]; then
        port='-'
      fi

      marker=' '
      if [ "$row_index" -eq "$selected_index" ]; then
        marker='>'
      fi

      ui_pad_into padded_marker "$marker" "$marker_w"
      ui_pad_into padded_port "$port" "$port_w"
      ui_pad_into padded_pid "$pid" "$pid_w"
      ui_pad_into padded_user "$user" "$user_w"
      ui_pad_into padded_command "$command" "$command_w"
      ui_pad_into padded_bind "$bind" "$bind_w"
      line="$padded_marker $padded_port $padded_pid $padded_user $padded_command $padded_bind"
      ui_truncate_into line "$line" "$term_cols"

      if [ "$row_index" -eq "$selected_index" ]; then
        ui_pad_to_width_into line "$line" "$term_cols"
        line="${style_rev}${line}${style_reset}"
      fi

      ui_push_frame_line "$line"
    done
  fi

  ui_push_frame_line ""
  ui_truncate_into line "$status_message" "$term_cols"
  ui_push_frame_line "$line"

  for ((i = ${#UI_NEXT_LINES[@]}; i < term_rows; i++)); do
    ui_push_frame_line ""
  done
}

ui_build_inspect_frame() {
  local pid="$1"
  local command="$2"
  local status_message="$3"
  local content="${APP_INSPECT_CONTENT:-}"
  local term_rows
  local term_cols
  local body_rows
  local i=0
  local line
  local header_line
  local style_bold
  local style_reset
  local keys_line
  local truncated_command

  term_rows="$(tput lines 2>/dev/null || printf '24')"
  term_cols="$(tput cols 2>/dev/null || printf '80')"
  body_rows=$((term_rows - 4))
  if [ "$body_rows" -lt 1 ]; then
    body_rows=1
  fi

  UI_NEXT_LINES=()
  UI_NEXT_WIDTH="$term_cols"
  UI_NEXT_HEIGHT="$term_rows"

  style_bold="$(ui_term_code bold)"
  style_reset="$(ui_term_code sgr0)"

  ui_truncate_into truncated_command "$command" 40
  header_line="Inspect PID $pid ($truncated_command)"
  ui_truncate_into header_line "$header_line" "$term_cols"
  ui_push_frame_line "${style_bold}${header_line}${style_reset}"
  ui_truncate_into keys_line "Keys: b back  k kill  r refresh  q quit" "$term_cols"
  ui_push_frame_line "$keys_line"
  ui_push_frame_line ""

  if [ -z "$content" ]; then
    content='No process details available.'
  fi

  while IFS= read -r line; do
    if [ "$i" -ge "$body_rows" ]; then
      break
    fi

    ui_truncate_into line "$line" "$term_cols"
    ui_push_frame_line "$line"
    i=$((i + 1))
  done <<EOF_CONTENT
$content
EOF_CONTENT

  for (( ; i < body_rows; i++)); do
    ui_push_frame_line ""
  done

  ui_truncate_into line "$status_message" "$term_cols"
  ui_push_frame_line "$line"

  for ((i = ${#UI_NEXT_LINES[@]}; i < term_rows; i++)); do
    ui_push_frame_line ""
  done
}

ui_paint_frame() {
  local i
  local needs_full=0

  if [ "$UI_FORCE_FULL_REDRAW" -eq 1 ]; then
    needs_full=1
  fi
  if [ "$UI_INCREMENTAL_SUPPORTED" -ne 1 ]; then
    needs_full=1
  fi
  if [ "$UI_FRAME_WIDTH" -ne "$UI_NEXT_WIDTH" ] || [ "$UI_FRAME_HEIGHT" -ne "$UI_NEXT_HEIGHT" ]; then
    needs_full=1
  fi
  if [ "${#UI_FRAME_LINES[@]}" -ne "${#UI_NEXT_LINES[@]}" ]; then
    needs_full=1
  fi

  if [ "$needs_full" -eq 1 ]; then
    printf '\033[H\033[2J'
    for ((i = 0; i < UI_NEXT_HEIGHT; i++)); do
      ui_term_emit cup "$i" 0
      ui_term_emit el
      printf '%s' "${UI_NEXT_LINES[$i]}"
    done
  else
    for ((i = 0; i < UI_NEXT_HEIGHT; i++)); do
      if [ "${UI_FRAME_LINES[$i]}" != "${UI_NEXT_LINES[$i]}" ]; then
        ui_term_emit cup "$i" 0
        ui_term_emit el
        printf '%s' "${UI_NEXT_LINES[$i]}"
      fi
    done
  fi

  UI_FRAME_LINES=("${UI_NEXT_LINES[@]}")
  UI_FRAME_WIDTH="$UI_NEXT_WIDTH"
  UI_FRAME_HEIGHT="$UI_NEXT_HEIGHT"
  UI_FORCE_FULL_REDRAW=0
}

ui_render_main() {
  ui_build_main_frame "$1" "$2" "$3"
  ui_paint_frame
}

ui_render_inspect() {
  ui_build_inspect_frame "$1" "$2" "$3"
  ui_paint_frame
}

ui_prompt_yes_no() {
  local prompt="$1"
  local term_rows
  local term_cols
  local key

  term_rows="$(tput lines 2>/dev/null || printf '24')"
  term_cols="$(tput cols 2>/dev/null || printf '80')"

  while true; do
    ui_term_emit cup "$((term_rows - 1))" 0
    ui_term_emit el
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
