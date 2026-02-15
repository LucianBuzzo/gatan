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
UI_BORDER_H='-'
UI_BORDER_V='|'
UI_BORDER_TOP_LEFT='+'
UI_BORDER_TOP_RIGHT='+'
UI_BORDER_BOTTOM_LEFT='+'
UI_BORDER_BOTTOM_RIGHT='+'
UI_BORDER_MID_LEFT='+'
UI_BORDER_MID_RIGHT='+'

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

ui_is_positive_int() {
  case "$1" in
    '' | *[!0-9]* | 0) return 1 ;;
    *) return 0 ;;
  esac
}

ui_get_terminal_size_into() {
  local __rows_var="$1"
  local __cols_var="$2"
  local stty_size
  local _ui_rows
  local _ui_cols

  stty_size="$(stty size 2>/dev/null || true)"
  if [ -n "$stty_size" ]; then
    _ui_rows="${stty_size%% *}"
    _ui_cols="${stty_size##* }"
  fi

  if ! ui_is_positive_int "${_ui_rows:-}"; then
    _ui_rows="$(tput lines 2>/dev/null || printf '24')"
  fi
  if ! ui_is_positive_int "${_ui_cols:-}"; then
    _ui_cols="$(tput cols 2>/dev/null || printf '80')"
  fi

  printf -v "$__rows_var" '%s' "$_ui_rows"
  printf -v "$__cols_var" '%s' "$_ui_cols"
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

ui_configure_borders() {
  local charmap
  local encoding_hint

  charmap="$(locale charmap 2>/dev/null || true)"
  encoding_hint="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"

  case "$charmap:$encoding_hint" in
    UTF-8:* | *:*.UTF-8* | *:*utf8* | *:*utf-8*)
      UI_BORDER_H='─'
      UI_BORDER_V='│'
      UI_BORDER_TOP_LEFT='┌'
      UI_BORDER_TOP_RIGHT='┐'
      UI_BORDER_BOTTOM_LEFT='└'
      UI_BORDER_BOTTOM_RIGHT='┘'
      UI_BORDER_MID_LEFT='├'
      UI_BORDER_MID_RIGHT='┤'
      ;;
    *)
      UI_BORDER_H='-'
      UI_BORDER_V='|'
      UI_BORDER_TOP_LEFT='+'
      UI_BORDER_TOP_RIGHT='+'
      UI_BORDER_BOTTOM_LEFT='+'
      UI_BORDER_BOTTOM_RIGHT='+'
      UI_BORDER_MID_LEFT='+'
      UI_BORDER_MID_RIGHT='+'
      ;;
  esac
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
  ui_configure_borders
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

ui_border_line_into() {
  local __var="$1"
  local inner_width="$2"
  local style="${3:-mid}"
  local left
  local right
  local dashes

  case "$style" in
    top)
      left="$UI_BORDER_TOP_LEFT"
      right="$UI_BORDER_TOP_RIGHT"
      ;;
    bottom)
      left="$UI_BORDER_BOTTOM_LEFT"
      right="$UI_BORDER_BOTTOM_RIGHT"
      ;;
    *)
      left="$UI_BORDER_MID_LEFT"
      right="$UI_BORDER_MID_RIGHT"
      ;;
  esac

  if [ "$inner_width" -le 0 ]; then
    printf -v "$__var" '%s%s' "$left" "$right"
    return 0
  fi

  printf -v dashes '%*s' "$inner_width" ''
  dashes="${dashes// /$UI_BORDER_H}"
  printf -v "$__var" '%s%s%s' "$left" "$dashes" "$right"
}

ui_frame_line_into() {
  local __var="$1"
  local content="$2"
  local inner_width="$3"
  local padded

  ui_pad_to_width_into padded "$content" "$inner_width"
  printf -v "$__var" '%s%s%s' "$UI_BORDER_V" "$padded" "$UI_BORDER_V"
}

ui_build_main_frame() {
  local selected_index="$1"
  local scroll_index="$2"
  local status_message="$3"
  local term_rows
  local term_cols
  local table_rows
  local total_rows
  local frame_overhead="${GATAN_MAIN_FRAME_OVERHEAD:-8}"
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
  local inner_width
  local border_top
  local border_mid
  local border_bottom
  local framed_line
  local base_fixed
  local variable_w

  ui_get_terminal_size_into term_rows term_cols
  if [ "$term_cols" -lt 4 ]; then
    term_cols=4
  fi
  inner_width=$((term_cols - 2))

  table_rows=$((term_rows - frame_overhead))
  if [ "$table_rows" -lt 0 ]; then
    table_rows=0
  fi

  base_fixed=$((marker_w + port_w + pid_w + user_w + 5))
  variable_w=$((inner_width - base_fixed))
  if [ "$variable_w" -le 0 ]; then
    command_w=0
    bind_w=0
  else
    # Favor command width in roomy terminals; cap bind so it doesn't overgrow.
    command_w=$((variable_w * 3 / 4))
    bind_w=$((variable_w - command_w))
    if [ "$variable_w" -ge 18 ]; then
      if [ "$bind_w" -lt 10 ]; then
        bind_w=10
        command_w=$((variable_w - bind_w))
      fi
      if [ "$bind_w" -gt 32 ]; then
        bind_w=32
        command_w=$((variable_w - bind_w))
      fi
      if [ "$command_w" -lt 10 ]; then
        command_w=10
        bind_w=$((variable_w - command_w))
      fi
    fi
  fi

  total_rows="${#APP_ROWS[@]}"

  UI_NEXT_LINES=()
  UI_NEXT_WIDTH="$term_cols"
  UI_NEXT_HEIGHT="$term_rows"

  style_bold="$(ui_term_code bold)"
  style_reset="$(ui_term_code sgr0)"
  style_rev="$(ui_term_code rev)"

  ui_border_line_into border_top "$inner_width" top
  ui_border_line_into border_mid "$inner_width" mid
  ui_border_line_into border_bottom "$inner_width" bottom
  ui_push_frame_line "$border_top"

  header_line="$GATAN_APP_NAME ${APP_VERSION:-$(gatan_version)} | TCP listeners: $total_rows"
  ui_truncate_into header_line "$header_line" "$inner_width"
  ui_frame_line_into framed_line "$header_line" "$inner_width"
  ui_push_frame_line "${style_bold}${framed_line}${style_reset}"

  ui_truncate_into keys_line "Keys: Up/Down move  Enter inspect  k kill  r refresh  q quit" "$inner_width"
  ui_frame_line_into framed_line "$keys_line" "$inner_width"
  ui_push_frame_line "$framed_line"

  ui_push_frame_line "$border_mid"

  ui_pad_into padded_marker "" "$marker_w"
  ui_pad_into padded_port "PORT" "$port_w"
  ui_pad_into padded_pid "PID" "$pid_w"
  ui_pad_into padded_user "USER" "$user_w"
  ui_pad_into padded_command "COMMAND" "$command_w"
  ui_pad_into padded_bind "BIND" "$bind_w"
  line="$padded_marker $padded_port $padded_pid $padded_user $padded_command $padded_bind"
  ui_truncate_into line "$line" "$inner_width"
  ui_frame_line_into framed_line "$line" "$inner_width"
  ui_push_frame_line "${style_bold}${framed_line}${style_reset}"

  if [ "$total_rows" -eq 0 ]; then
    if [ "$table_rows" -gt 0 ]; then
      ui_truncate_into line "No listening TCP processes found." "$inner_width"
      ui_frame_line_into framed_line "$line" "$inner_width"
      ui_push_frame_line "$framed_line"
      for ((i = 1; i < table_rows; i++)); do
        ui_frame_line_into framed_line "" "$inner_width"
        ui_push_frame_line "$framed_line"
      done
    fi
  else
    for ((i = 0; i < table_rows; i++)); do
      row_index=$((scroll_index + i))
      if [ "$row_index" -ge "$total_rows" ]; then
        ui_frame_line_into framed_line "" "$inner_width"
        ui_push_frame_line "$framed_line"
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
      ui_truncate_into line "$line" "$inner_width"
      ui_frame_line_into framed_line "$line" "$inner_width"

      if [ "$row_index" -eq "$selected_index" ]; then
        framed_line="${style_rev}${framed_line}${style_reset}"
      fi

      ui_push_frame_line "$framed_line"
    done
  fi

  ui_push_frame_line "$border_mid"
  ui_truncate_into line "$status_message" "$inner_width"
  ui_frame_line_into framed_line "$line" "$inner_width"
  ui_push_frame_line "$framed_line"
  ui_push_frame_line "$border_bottom"

  if [ "${#UI_NEXT_LINES[@]}" -gt "$term_rows" ]; then
    UI_NEXT_LINES=("${UI_NEXT_LINES[@]:0:$term_rows}")
  fi

  for ((i = ${#UI_NEXT_LINES[@]}; i < term_rows; i++)); do
    ui_frame_line_into framed_line "" "$inner_width"
    ui_push_frame_line "$framed_line"
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
  local frame_overhead=7
  local i=0
  local line
  local header_line
  local style_bold
  local style_reset
  local keys_line
  local truncated_command
  local inner_width
  local border_top
  local border_mid
  local border_bottom
  local framed_line

  ui_get_terminal_size_into term_rows term_cols
  if [ "$term_cols" -lt 4 ]; then
    term_cols=4
  fi
  inner_width=$((term_cols - 2))

  body_rows=$((term_rows - frame_overhead))
  if [ "$body_rows" -lt 0 ]; then
    body_rows=0
  fi

  UI_NEXT_LINES=()
  UI_NEXT_WIDTH="$term_cols"
  UI_NEXT_HEIGHT="$term_rows"

  style_bold="$(ui_term_code bold)"
  style_reset="$(ui_term_code sgr0)"

  ui_border_line_into border_top "$inner_width" top
  ui_border_line_into border_mid "$inner_width" mid
  ui_border_line_into border_bottom "$inner_width" bottom
  ui_push_frame_line "$border_top"

  ui_truncate_into truncated_command "$command" 40
  header_line="Inspect PID $pid ($truncated_command)"
  ui_truncate_into header_line "$header_line" "$inner_width"
  ui_frame_line_into framed_line "$header_line" "$inner_width"
  ui_push_frame_line "${style_bold}${framed_line}${style_reset}"

  ui_truncate_into keys_line "Keys: b back  k kill  r refresh  q quit" "$inner_width"
  ui_frame_line_into framed_line "$keys_line" "$inner_width"
  ui_push_frame_line "$framed_line"

  ui_push_frame_line "$border_mid"

  if [ -z "$content" ]; then
    content='No process details available.'
  fi

  while IFS= read -r line; do
    if [ "$i" -ge "$body_rows" ]; then
      break
    fi

    ui_truncate_into line "$line" "$inner_width"
    ui_frame_line_into framed_line "$line" "$inner_width"
    ui_push_frame_line "$framed_line"
    i=$((i + 1))
  done <<EOF_CONTENT
$content
EOF_CONTENT

  for (( ; i < body_rows; i++)); do
    ui_frame_line_into framed_line "" "$inner_width"
    ui_push_frame_line "$framed_line"
  done

  ui_push_frame_line "$border_mid"
  ui_truncate_into line "$status_message" "$inner_width"
  ui_frame_line_into framed_line "$line" "$inner_width"
  ui_push_frame_line "$framed_line"
  ui_push_frame_line "$border_bottom"

  if [ "${#UI_NEXT_LINES[@]}" -gt "$term_rows" ]; then
    UI_NEXT_LINES=("${UI_NEXT_LINES[@]:0:$term_rows}")
  fi

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
  local result=1

  ui_get_terminal_size_into term_rows term_cols

  while true; do
    ui_term_emit cup "$((term_rows - 1))" 0
    ui_term_emit el
    printf '%s' "$(ui_truncate "$prompt" "$term_cols")"

    key="$(ui_read_key 0.1 || true)"
    if [ -z "$key" ]; then
      continue
    fi

    case "$key" in
      Y)
        result=0
        break
        ;;
      N | ENTER | Q | ESC)
        result=1
        break
        ;;
    esac
  done

  ui_term_emit cup "$((term_rows - 1))" 0
  ui_term_emit el
  # Prompt text is drawn outside the frame cache, so force a full redraw.
  ui_force_full_redraw

  return "$result"
}
