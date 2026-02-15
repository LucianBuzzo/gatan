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
UI_COLOR_ACCENT_FG=$'\033[38;2;42;161;152m'
UI_COLOR_ACCENT_BG=$'\033[48;2;42;161;152m'
UI_COLOR_TEXT_LIGHT=$'\033[38;2;253;246;227m'
UI_COLOR_STATUS_FG=$'\033[38;2;147;161;161m'
UI_COLOR_RESET_FG=$'\033[39m'
UI_COLOR_RESET_BG=$'\033[49m'
UI_COLOR_RESET_ALL=$'\033[0m'

ui_term_emit() {
  local cap="$1"
  shift

  case "$cap" in
    cup)
      # ANSI cursor addressing is 1-based.
      printf '\033[%s;%sH' "$(($1 + 1))" "$(($2 + 1))"
      ;;
    el)
      printf '\033[2K'
      ;;
    smcup)
      printf '\033[?1049h'
      ;;
    rmcup)
      printf '\033[?1049l'
      ;;
    civis)
      printf '\033[?25l'
      ;;
    cnorm)
      printf '\033[?25h'
      ;;
    *)
      tput "$cap" "$@" 2>/dev/null || true
      ;;
  esac
}

ui_term_code() {
  local cap="$1"
  shift

  case "$cap" in
    bold) printf '\033[1m' ;;
    sgr0) printf '\033[0m' ;;
    rev) printf '\033[7m' ;;
    *) tput "$cap" "$@" 2>/dev/null || true ;;
  esac
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
    # Keep behavior functional on bash 3.2 by rounding any fractional wait up
    # to 1 second (bash 3.2 cannot honor sub-second timeouts).
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
  local key=""
  local seq=""

  read_timeout="$(ui_read_timeout "$timeout")"
  seq_timeout="$(ui_read_timeout "0.001")"

  IFS= read -rsn1 -d '' -t "$read_timeout" key || return 1

  if [ "$key" = $'\x1b' ]; then
    IFS= read -rsn1 -d '' -t "$seq_timeout" seq || {
      printf 'ESC\n'
      return 0
    }

    if [ "$seq" = "[" ]; then
      IFS= read -rsn1 -d '' -t "$seq_timeout" seq || {
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
    $'\n' | $'\r') printf 'ENTER\n' ;;
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
  printf -v "$__var" '%s%s%s%s%s%s%s' \
    "$UI_COLOR_ACCENT_FG" "$UI_BORDER_V" "$UI_COLOR_RESET_FG" \
    "$padded" \
    "$UI_COLOR_ACCENT_FG" "$UI_BORDER_V" "$UI_COLOR_RESET_FG"
}

ui_content_line_into() {
  local __var="$1"
  local content="$2"
  local width="$3"
  local padded

  ui_pad_to_width_into padded "$content" "$width"
  printf -v "$__var" '%s' "$padded"
}

ui_style_status_line_into() {
  local __var="$1"
  local content="$2"
  local width="$3"
  local padded

  ui_pad_to_width_into padded "$content" "$width"
  printf -v "$__var" '%s%s%s' "$UI_COLOR_STATUS_FG" "$padded" "$UI_COLOR_RESET_FG"
}

ui_style_border_line_into() {
  local __var="$1"
  local line="$2"
  printf -v "$__var" '%s%s%s' "$UI_COLOR_ACCENT_FG" "$line" "$UI_COLOR_RESET_FG"
}

ui_rule_line_into() {
  local __var="$1"
  local width="$2"
  local rule

  if [ "$width" -le 0 ]; then
    printf -v "$__var" '%s' ""
    return 0
  fi

  printf -v rule '%*s' "$width" ''
  rule="${rule// /$UI_BORDER_H}"
  printf -v "$__var" '%s' "$rule"
}

ui_label_border_line_into() {
  local __var="$1"
  local line="$2"
  local label="$3"
  local inset="${4:-3}"
  local line_len
  local label_text
  local max_label
  local suffix_start
  local prefix
  local suffix

  line_len="${#line}"
  if [ "$line_len" -le 0 ]; then
    printf -v "$__var" '%s' "$line"
    return 0
  fi

  if [ "$inset" -lt 1 ]; then
    inset=1
  fi
  if [ "$inset" -ge "$line_len" ]; then
    inset=$((line_len - 1))
  fi

  label_text=" ${label} "
  max_label=$((line_len - inset - 1))
  if [ "$max_label" -lt 0 ]; then
    max_label=0
  fi
  ui_truncate_into label_text "$label_text" "$max_label"

  prefix="${line:0:$inset}"
  suffix_start=$((inset + ${#label_text}))
  if [ "$suffix_start" -lt "$line_len" ]; then
    suffix="${line:$suffix_start}"
  else
    suffix=""
  fi

  printf -v "$__var" '%s%s%s' "$prefix" "$label_text" "$suffix"
}

ui_bottom_link_line_into() {
  local __var="$1"
  local width="$2"
  local line
  local fill

  if [ "$UI_BORDER_H" = '─' ]; then
    fill='▄'
    printf -v line '%*s' "$width" ''
    line="${line// /$fill}"

    # Keep terminal background untouched so only the lower half appears cyan.
    printf -v "$__var" '%s%s%s' "$UI_COLOR_ACCENT_FG" "$line" "$UI_COLOR_RESET_ALL"
    return 0
  fi

  ui_border_line_into line "$((width - 2))" bottom
  ui_style_border_line_into "$__var" "$line"
}

ui_style_keybind_line_into() {
  local __var="$1"
  local content="$2"
  local width="$3"
  local middle
  local middle_width
  local left_infill
  local right_infill
  local styled_line

  if [ "$width" -le 0 ]; then
    printf -v "$__var" '%s' ""
    return 0
  fi

  if [ "$width" -lt 4 ]; then
    ui_truncate_into middle "$content" "$width"
    ui_pad_to_width_into middle "$middle" "$width"
    printf -v "$__var" '%s' "$middle"
    return 0
  fi

  middle_width=$((width - 4))
  ui_truncate_into middle "$content" "$middle_width"
  ui_pad_to_width_into middle "$middle" "$middle_width"

  left_infill=' '
  right_infill=' '
  if [ "$UI_BORDER_H" = '─' ]; then
    left_infill='█'
    right_infill='█'
  fi

  styled_line="${UI_COLOR_RESET_BG}${UI_COLOR_ACCENT_FG}${left_infill}${UI_COLOR_ACCENT_BG}${UI_COLOR_TEXT_LIGHT} ${middle} ${UI_COLOR_RESET_BG}${UI_COLOR_ACCENT_FG}${right_infill}${UI_COLOR_RESET_ALL}${UI_COLOR_RESET_FG}"
  printf -v "$__var" '%s' "$styled_line"
}

ui_style_keybind_padding_line_into() {
  local __var="$1"
  local width="$2"
  local fill
  local line

  if [ "$width" -le 0 ]; then
    printf -v "$__var" '%s' ""
    return 0
  fi

  if [ "$UI_BORDER_H" = '─' ]; then
    fill='▀'
    printf -v line '%*s' "$width" ''
    line="${line// /$fill}"
    printf -v "$__var" '%s%s%s' "$UI_COLOR_ACCENT_FG" "$line" "$UI_COLOR_RESET_ALL"
    return 0
  fi

  printf -v line '%*s' "$width" ''
  printf -v "$__var" '%s%s%s' "$UI_COLOR_ACCENT_BG" "$line" "$UI_COLOR_RESET_ALL"
}

ui_compose_keybind_content_into() {
  local __var="$1"
  local left_text="$2"
  local right_text="$3"
  local width="$4"
  local out
  local right_part
  local left_part
  local left_width
  local remaining
  local pad

  if [ "$width" -le 0 ]; then
    printf -v "$__var" '%s' ""
    return 0
  fi

  ui_truncate_into right_part "$right_text" "$width"
  if [ "${#right_part}" -ge "$width" ]; then
    printf -v "$__var" '%s' "$right_part"
    return 0
  fi

  remaining=$((width - ${#right_part}))
  if [ -n "$left_text" ] && [ "$remaining" -gt 1 ]; then
    left_width=$((remaining - 1))
    ui_pad_to_width_into left_part "$left_text" "$left_width"
    out="${left_part} ${right_part}"
  else
    printf -v pad '%*s' "$remaining" ''
    out="${pad}${right_part}"
  fi

  ui_pad_to_width_into out "$out" "$width"
  printf -v "$__var" '%s' "$out"
}

ui_build_main_frame() {
  local selected_index="$1"
  local scroll_index="$2"
  local status_message="$3"
  local term_rows
  local term_cols
  local table_rows
  local total_rows
  local frame_overhead_base="${GATAN_MAIN_FRAME_OVERHEAD:-6}"
  local frame_overhead
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
  local keybind_content
  local key_pad_line
  local padded_marker
  local padded_port
  local padded_pid
  local padded_user
  local padded_command
  local padded_bind
  local content_width
  local border_bottom
  local framed_line
  local base_fixed
  local variable_w
  local top_label
  local show_keybind_padding=0

  ui_get_terminal_size_into term_rows term_cols
  if [ "$term_cols" -lt 4 ]; then
    term_cols=4
  fi
  content_width="$term_cols"
  frame_overhead="$frame_overhead_base"
  if [ "$term_rows" -ge $((frame_overhead_base + 1)) ]; then
    frame_overhead=$((frame_overhead_base + 1))
    show_keybind_padding=1
  fi

  table_rows=$((term_rows - frame_overhead))
  if [ "$table_rows" -lt 0 ]; then
    table_rows=0
  fi

  base_fixed=$((marker_w + port_w + pid_w + user_w + 5))
  variable_w=$((content_width - base_fixed))
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
  top_label="$GATAN_APP_NAME ${APP_VERSION:-$(gatan_version)}"

  header_line="  TCP listeners: $total_rows"
  ui_truncate_into header_line "$header_line" "$content_width"
  ui_content_line_into framed_line "$header_line" "$content_width"
  ui_push_frame_line "${style_bold}${framed_line}${style_reset}"
  ui_content_line_into framed_line "" "$content_width"
  ui_push_frame_line "$framed_line"

  ui_pad_into padded_marker "" "$marker_w"
  ui_pad_into padded_port "PORT" "$port_w"
  ui_pad_into padded_pid "PID" "$pid_w"
  ui_pad_into padded_user "USER" "$user_w"
  ui_pad_into padded_command "COMMAND" "$command_w"
  ui_pad_into padded_bind "BIND" "$bind_w"
  line="$padded_marker $padded_port $padded_pid $padded_user $padded_command $padded_bind"
  ui_truncate_into line "$line" "$content_width"
  ui_content_line_into framed_line "$line" "$content_width"
  ui_push_frame_line "${style_bold}${framed_line}${style_reset}"

  if [ "$total_rows" -eq 0 ]; then
    if [ "$table_rows" -gt 0 ]; then
      ui_truncate_into line "No listening TCP processes found." "$content_width"
      ui_content_line_into framed_line "$line" "$content_width"
      ui_push_frame_line "$framed_line"
      for ((i = 1; i < table_rows; i++)); do
        ui_content_line_into framed_line "" "$content_width"
        ui_push_frame_line "$framed_line"
      done
    fi
  else
    for ((i = 0; i < table_rows; i++)); do
      row_index=$((scroll_index + i))
      if [ "$row_index" -ge "$total_rows" ]; then
        ui_content_line_into framed_line "" "$content_width"
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
      ui_truncate_into line "$line" "$content_width"
      ui_content_line_into framed_line "$line" "$content_width"

      if [ "$row_index" -eq "$selected_index" ]; then
        framed_line="${style_rev}${framed_line}${style_reset}"
      fi

      ui_push_frame_line "$framed_line"
    done
  fi

  ui_truncate_into line "  $status_message" "$content_width"
  ui_style_status_line_into framed_line "$line" "$content_width"
  ui_push_frame_line "$framed_line"
  ui_bottom_link_line_into border_bottom "$term_cols"
  ui_push_frame_line "$border_bottom"
  ui_compose_keybind_content_into keybind_content "↑/↓ move | Enter inspect | k kill | r refresh | q quit" "$top_label" "$((term_cols - 4))"
  ui_style_keybind_line_into keys_line "$keybind_content" "$term_cols"
  ui_push_frame_line "$keys_line"
  if [ "$show_keybind_padding" -eq 1 ]; then
    ui_style_keybind_padding_line_into key_pad_line "$term_cols"
    ui_push_frame_line "$key_pad_line"
  fi

  if [ "${#UI_NEXT_LINES[@]}" -gt "$term_rows" ]; then
    UI_NEXT_LINES=("${UI_NEXT_LINES[@]:0:$term_rows}")
  fi

  for ((i = ${#UI_NEXT_LINES[@]}; i < term_rows; i++)); do
    ui_content_line_into framed_line "" "$content_width"
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
  local frame_overhead_base=5
  local frame_overhead
  local i=0
  local line
  local header_line
  local style_bold
  local style_reset
  local keys_line
  local keybind_content
  local key_pad_line
  local truncated_command
  local app_label
  local content_width
  local border_bottom
  local framed_line
  local show_keybind_padding=0
  local in_attr_block=1
  local in_open_files_section=0
  local in_top_section=0
  local line_text
  local content_after_indent
  local label
  local tail

  ui_get_terminal_size_into term_rows term_cols
  if [ "$term_cols" -lt 4 ]; then
    term_cols=4
  fi
  content_width="$term_cols"
  frame_overhead="$frame_overhead_base"
  if [ "$term_rows" -ge $((frame_overhead_base + 1)) ]; then
    frame_overhead=$((frame_overhead_base + 1))
    show_keybind_padding=1
  fi

  body_rows=$((term_rows - frame_overhead))
  if [ "$body_rows" -lt 0 ]; then
    body_rows=0
  fi

  UI_NEXT_LINES=()
  UI_NEXT_WIDTH="$term_cols"
  UI_NEXT_HEIGHT="$term_rows"

  style_bold="$(ui_term_code bold)"
  style_reset="$(ui_term_code sgr0)"
  app_label="$GATAN_APP_NAME ${APP_VERSION:-$(gatan_version)}"

  ui_truncate_into truncated_command "$command" 40
  header_line="  Inspect PID $pid ($truncated_command)"
  ui_truncate_into header_line "$header_line" "$content_width"
  ui_content_line_into framed_line "$header_line" "$content_width"
  ui_push_frame_line "${style_bold}${framed_line}${style_reset}"
  ui_content_line_into framed_line "" "$content_width"
  ui_push_frame_line "$framed_line"

  if [ -z "$content" ]; then
    content='No process details available.'
  fi

  while IFS= read -r line; do
    if [ "$i" -ge "$body_rows" ]; then
      break
    fi

    line_text="  $line"
    ui_truncate_into line_text "$line_text" "$content_width"
    ui_content_line_into framed_line "$line_text" "$content_width"

    if [ "$in_attr_block" -eq 1 ]; then
      if [ -z "$line" ]; then
        in_attr_block=0
      else
        content_after_indent="${framed_line:2}"
        label="${content_after_indent%%[[:space:]]*}"
        if [ -n "$label" ] && [ "$label" != "$content_after_indent" ]; then
          tail="${content_after_indent:${#label}}"
          framed_line="  ${style_bold}${label}${style_reset}${tail}"
        fi
      fi
    fi

    if [[ "$line" == Live\ metrics\ \(PID* ]]; then
      in_top_section=1
    elif [ "$in_top_section" -eq 1 ] && [ -n "$line" ]; then
      content_after_indent="${framed_line:2}"
      label="${content_after_indent%%[[:space:]]*}"
      if [ -n "$label" ] && [ "$label" != "$content_after_indent" ] && [[ "$label" =~ ^[A-Z][A-Z0-9_+-]*$ ]]; then
        tail="${content_after_indent:${#label}}"
        framed_line="  ${style_bold}${label}${style_reset}${tail}"
      fi
    fi

    if [[ "$line" == Open\ files\ \(first* ]]; then
      in_open_files_section=1
    elif [ "$in_open_files_section" -eq 1 ] && [[ "$line" == COMMAND* ]]; then
      framed_line="${style_bold}${framed_line}${style_reset}"
      in_open_files_section=0
    fi

    ui_push_frame_line "$framed_line"
    i=$((i + 1))
  done <<EOF_CONTENT
$content
EOF_CONTENT

  for (( ; i < body_rows; i++)); do
    ui_content_line_into framed_line "" "$content_width"
    ui_push_frame_line "$framed_line"
  done

  ui_truncate_into line "  $status_message" "$content_width"
  ui_style_status_line_into framed_line "$line" "$content_width"
  ui_push_frame_line "$framed_line"
  ui_bottom_link_line_into border_bottom "$term_cols"
  ui_push_frame_line "$border_bottom"
  ui_compose_keybind_content_into keybind_content "b back | k kill | r refresh | q quit" "$app_label" "$((term_cols - 4))"
  ui_style_keybind_line_into keys_line "$keybind_content" "$term_cols"
  ui_push_frame_line "$keys_line"
  if [ "$show_keybind_padding" -eq 1 ]; then
    ui_style_keybind_padding_line_into key_pad_line "$term_cols"
    ui_push_frame_line "$key_pad_line"
  fi

  if [ "${#UI_NEXT_LINES[@]}" -gt "$term_rows" ]; then
    UI_NEXT_LINES=("${UI_NEXT_LINES[@]:0:$term_rows}")
  fi

  for ((i = ${#UI_NEXT_LINES[@]}; i < term_rows; i++)); do
    ui_content_line_into line "" "$content_width"
    ui_push_frame_line "$line"
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

ui_draw_yes_no_modal() {
  local message="$1"
  local term_rows="$2"
  local term_cols="$3"
  local title="Confirm action"
  local hint="Press y/Enter to confirm, n/Esc to cancel"
  local min_inner=24
  local max_inner
  local desired_inner
  local inner_width
  local modal_width
  local modal_height=7
  local start_row
  local start_col
  local border_top
  local border_bottom
  local line
  local framed_line
  local blank_line
  local style_bold
  local style_reset

  if [ "$term_rows" -lt 1 ] || [ "$term_cols" -lt 1 ]; then
    return 0
  fi

  if [ "$term_rows" -lt "$modal_height" ] || [ "$term_cols" -lt 4 ]; then
    ui_term_emit cup "$((term_rows - 1))" 0
    ui_term_emit el
    printf '%s' "$(ui_truncate "$message" "$term_cols")"
    return 0
  fi

  max_inner=$((term_cols - 2))
  desired_inner="${#message}"
  if [ "${#title}" -gt "$desired_inner" ]; then
    desired_inner="${#title}"
  fi
  if [ "${#hint}" -gt "$desired_inner" ]; then
    desired_inner="${#hint}"
  fi
  if [ "$desired_inner" -lt "$min_inner" ]; then
    desired_inner="$min_inner"
  fi
  if [ "$desired_inner" -gt "$max_inner" ]; then
    desired_inner="$max_inner"
  fi
  if [ "$desired_inner" -lt 0 ]; then
    desired_inner=0
  fi

  inner_width="$desired_inner"
  modal_width=$((inner_width + 2))
  start_row=$(((term_rows - modal_height) / 2))
  start_col=$(((term_cols - modal_width) / 2))
  if [ "$start_row" -lt 0 ]; then
    start_row=0
  fi
  if [ "$start_col" -lt 0 ]; then
    start_col=0
  fi

  ui_border_line_into border_top "$inner_width" top
  ui_border_line_into border_bottom "$inner_width" bottom
  style_bold="$(ui_term_code bold)"
  style_reset="$(ui_term_code sgr0)"

  ui_term_emit cup "$start_row" "$start_col"
  printf '%s' "$border_top"

  ui_truncate_into line "$title" "$inner_width"
  ui_frame_line_into framed_line "$line" "$inner_width"
  ui_term_emit cup "$((start_row + 1))" "$start_col"
  printf '%s' "${style_bold}${framed_line}${style_reset}"

  ui_frame_line_into blank_line "" "$inner_width"
  ui_term_emit cup "$((start_row + 2))" "$start_col"
  printf '%s' "$blank_line"

  ui_truncate_into line "$message" "$inner_width"
  ui_frame_line_into framed_line "$line" "$inner_width"
  ui_term_emit cup "$((start_row + 3))" "$start_col"
  printf '%s' "$framed_line"

  ui_term_emit cup "$((start_row + 4))" "$start_col"
  printf '%s' "$blank_line"

  ui_truncate_into line "$hint" "$inner_width"
  ui_frame_line_into framed_line "$line" "$inner_width"
  ui_term_emit cup "$((start_row + 5))" "$start_col"
  printf '%s' "$framed_line"

  ui_term_emit cup "$((start_row + 6))" "$start_col"
  printf '%s' "$border_bottom"
}

ui_prompt_yes_no() {
  local prompt="$1"
  local term_rows
  local term_cols
  local key
  local result=1
  local render_rows=-1
  local render_cols=-1

  while true; do
    ui_get_terminal_size_into term_rows term_cols
    if [ "$term_rows" -ne "$render_rows" ] || [ "$term_cols" -ne "$render_cols" ]; then
      ui_draw_yes_no_modal "$prompt" "$term_rows" "$term_cols"
      render_rows="$term_rows"
      render_cols="$term_cols"
    fi

    key="$(ui_read_key 0.1 || true)"
    if [ -z "$key" ]; then
      continue
    fi

    case "$key" in
      Y | ENTER)
        result=0
        break
        ;;
      N | Q | ESC)
        result=1
        break
        ;;
    esac
  done

  # Modal is drawn outside the frame cache, so force a full redraw.
  ui_force_full_redraw

  return "$result"
}

ui_draw_sudo_explainer_screen() {
  local sudo_prompt="$1"
  local term_rows="$2"
  local term_cols="$3"
  local style_bold
  local style_reset
  local title="gatan requires administrator access"
  local body1="This allows gatan to:"
  local body2="- list listening ports across all users"
  local body3="- inspect process details and open files"
  local body4="- send termination signals to selected processes"
  local body5="Your password is read by sudo and is never stored by gatan."
  local prompt_line="Prompt: $sudo_prompt"
  local hint="Press Enter to continue, Esc/q to cancel."
  local block_height=9
  local start_row
  local row
  local line
  local draw_col
  local draw_line

  style_bold="$(ui_term_code bold)"
  style_reset="$(ui_term_code sgr0)"

  if [ "$term_rows" -lt 1 ] || [ "$term_cols" -lt 1 ]; then
    return 0
  fi

  printf '\033[H\033[2J'
  start_row=$(((term_rows - block_height) / 2))
  if [ "$start_row" -lt 0 ]; then
    start_row=0
  fi

  row="$start_row"
  for line in \
    "$title" \
    "" \
    "$body1" \
    "$body2" \
    "$body3" \
    "$body4" \
    "" \
    "$body5" \
    "$prompt_line" \
    "$hint"; do
    if [ "$row" -ge "$term_rows" ]; then
      break
    fi

    ui_truncate_into draw_line "$line" "$term_cols"
    draw_col=$(((term_cols - ${#draw_line}) / 2))
    if [ "$draw_col" -lt 0 ]; then
      draw_col=0
    fi

    ui_term_emit cup "$row" "$draw_col"
    case "$line" in
      "$title" | "$hint")
        printf '%s%s%s' "$style_bold" "$draw_line" "$style_reset"
        ;;
      "$prompt_line")
        printf '%s%s%s%s%s' "$style_bold" "$UI_COLOR_TEXT_LIGHT" "$draw_line" "$style_reset" "$UI_COLOR_RESET_FG"
        ;;
      *)
        printf '%s' "$draw_line"
        ;;
    esac
    row=$((row + 1))
  done
}

ui_prompt_sudo_explainer() {
  local sudo_prompt="$1"
  local term_rows
  local term_cols
  local render_rows=-1
  local render_cols=-1
  local key
  local result=1

  while true; do
    ui_get_terminal_size_into term_rows term_cols
    if [ "$term_rows" -ne "$render_rows" ] || [ "$term_cols" -ne "$render_cols" ]; then
      ui_draw_sudo_explainer_screen "$sudo_prompt" "$term_rows" "$term_cols"
      render_rows="$term_rows"
      render_cols="$term_cols"
    fi

    key="$(ui_read_key 0.1 || true)"
    if [ -z "$key" ]; then
      continue
    fi

    case "$key" in
      ENTER | Y)
        result=0
        break
        ;;
      ESC | Q | N)
        result=1
        break
        ;;
    esac
  done

  ui_force_full_redraw
  return "$result"
}
