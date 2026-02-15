#!/usr/bin/env bats

load '../helpers/test_helper.bash'

setup() {
  setup_test_paths
}

@test "ui_read_key parses arrow down" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"
    printf "\033[B" | ui_read_key 0.1
  '

  [ "$status" -eq 0 ]
  [ "$output" = "DOWN" ]
}

@test "ui_read_key parses enter" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"
    printf "\n" | ui_read_key 0.1
  '

  [ "$status" -eq 0 ]
  [ "$output" = "ENTER" ]
}

@test "ui_get_terminal_size_into prefers stty size" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    stty() {
      if [ "${1:-}" = "size" ]; then
        printf "33 120\n"
        return 0
      fi
      return 1
    }

    tput() {
      case "$1" in
        lines) printf "24\n" ;;
        cols) printf "80\n" ;;
        *) return 0 ;;
      esac
    }

    ui_get_terminal_size_into rows cols
    printf "%s %s\n" "$rows" "$cols"
  '

  [ "$status" -eq 0 ]
  [ "$output" = "33 120" ]
}

@test "ui_get_terminal_size_into falls back to tput" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    stty() {
      return 1
    }

    tput() {
      case "$1" in
        lines) printf "44\n" ;;
        cols) printf "132\n" ;;
        *) return 0 ;;
      esac
    }

    ui_get_terminal_size_into rows cols
    printf "%s %s\n" "$rows" "$cols"
  '

  [ "$status" -eq 0 ]
  [ "$output" = "44 132" ]
}

@test "ui_prompt_yes_no forces full redraw after response" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    tput() {
      case "$1" in
        lines) printf "10\n" ;;
        cols) printf "60\n" ;;
        *) return 0 ;;
      esac
    }

    ui_term_emit() {
      :
    }

    UI_FORCE_FULL_REDRAW=0
    ui_prompt_yes_no "Terminate PID 42? [y/N] " <<<"y"
    rc="$?"
    printf "rc=%s force=%s\n" "$rc" "$UI_FORCE_FULL_REDRAW"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"Confirm action"* ]]
  [[ "$output" == *"Terminate PID 42? [y/N]"* ]]
  [[ "$output" == *"Press y/Enter to confirm, n/Esc to cancel"* ]]
  [[ "$output" == *"rc=0 force=1"* ]]
}

@test "ui_prompt_yes_no renders modal in center area" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    tput() {
      case "$1" in
        lines) printf "10\n" ;;
        cols) printf "60\n" ;;
        *) return 0 ;;
      esac
    }

    ui_term_emit() {
      printf "<%s" "$1"
      if [ -n "${2:-}" ]; then
        printf ",%s" "$2"
      fi
      if [ -n "${3:-}" ]; then
        printf ",%s" "$3"
      fi
      printf ">"
    }

    ui_prompt_yes_no "Terminate PID 42? [y/N] " <<<"y"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"<cup,1,"* ]]
  [[ "$output" == *"<cup,7,"* ]]
  [[ "$output" == *"<cup,4,"* ]]
}

@test "ui_prompt_yes_no treats enter as confirm and esc as cancel" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    tput() {
      case "$1" in
        lines) printf "10\n" ;;
        cols) printf "60\n" ;;
        *) return 0 ;;
      esac
    }

    ui_term_emit() {
      :
    }

    ui_prompt_yes_no "Terminate PID 42? [y/N] " <<<""
    enter_rc="$?"
    ui_prompt_yes_no "Terminate PID 42? [y/N] " <<<$'\''\033'\''
    esc_rc="$?"
    printf "enter=%s esc=%s\n" "$enter_rc" "$esc_rc"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"enter=0 esc=1"* ]]
}

@test "ui_prompt_sudo_explainer confirms on enter and forces full redraw" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    tput() {
      case "$1" in
        lines) printf "18\n" ;;
        cols) printf "80\n" ;;
        *) return 0 ;;
      esac
    }

    ui_term_emit() {
      :
    }

    UI_FORCE_FULL_REDRAW=0
    ui_prompt_sudo_explainer "[gatan] Administrator password: " <<<""
    rc="$?"
    printf "rc=%s force=%s\n" "$rc" "$UI_FORCE_FULL_REDRAW"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"gatan requires administrator access"* ]]
  [[ "$output" == *"Prompt: [gatan] Administrator password:"* ]]
  [[ "$output" == *"rc=0 force=1"* ]]
}

@test "ui_prompt_sudo_explainer cancels on esc" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    tput() {
      case "$1" in
        lines) printf "18\n" ;;
        cols) printf "80\n" ;;
        *) return 0 ;;
      esac
    }

    ui_term_emit() {
      :
    }

    ui_prompt_sudo_explainer "[gatan] Administrator password: " <<<$'\''\033'\''
    printf "rc=%s\n" "$?"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=1"* ]]
}

@test "ui_pad_to_width right pads text" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"
    out="$(ui_pad_to_width "abc" 5)"
    printf "<%s>\n" "$out"
  '

  [ "$status" -eq 0 ]
  [ "$output" = "<abc  >" ]
}

@test "ui_pad_to_width truncates when longer than width" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"
    out="$(ui_pad_to_width "abcdef" 4)"
    printf "<%s>\n" "$out"
  '

  [ "$status" -eq 0 ]
  [ "$output" = "<abc~>" ]
}

@test "ui_style_keybind_line_into applies cyan background when available" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"
    UI_BORDER_H="─"

    ui_style_keybind_line_into out "keys" 8
    clean="$(printf "%s" "$out" | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
    has_fg=0
    has_bg=0
    has_text=0
    [[ "$out" == *$'\''\033[38;2;42;161;152m'\''* ]] && has_fg=1
    [[ "$out" == *$'\''\033[48;2;42;161;152m'\''* ]] && has_bg=1
    [[ "$out" == *$'\''\033[38;2;253;246;227m'\''* ]] && has_text=1
    printf "has_fg=%s\n" "$has_fg"
    printf "has_bg=%s\n" "$has_bg"
    printf "has_text=%s\n" "$has_text"
    printf "clean=<%s>\n" "$clean"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"has_fg=1"* ]]
  [[ "$output" == *"has_bg=1"* ]]
  [[ "$output" == *"has_text=1"* ]]
  [[ "$output" == *"clean=<█ keys █>"* ]]
}

@test "ui_style_keybind_padding_line_into renders cyan upper half blocks" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"
    UI_BORDER_H="─"

    ui_style_keybind_padding_line_into out 8
    clean="$(printf "%s" "$out" | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
    has_fg=0
    has_bg=0
    [[ "$out" == *$'\''\033[38;2;42;161;152m'\''* ]] && has_fg=1
    [[ "$out" == *$'\''\033[48;2;42;161;152m'\''* ]] && has_bg=1
    printf "has_fg=%s\n" "$has_fg"
    printf "has_bg=%s\n" "$has_bg"
    printf "clean=<%s>\n" "$clean"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"has_fg=1"* ]]
  [[ "$output" == *"has_bg=0"* ]]
  [[ "$output" == *"clean=<▀▀▀▀▀▀▀▀>"* ]]
}

@test "ui_style_status_line_into applies lighter status foreground" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    ui_style_status_line_into out "Ready." 8
    clean="$(printf "%s" "$out" | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
    has_status_fg=0
    [[ "$out" == *$'\''\033[38;2;147;161;161m'\''* ]] && has_status_fg=1
    printf "has_status_fg=%s\n" "$has_status_fg"
    printf "clean=<%s>\n" "$clean"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"has_status_fg=1"* ]]
  [[ "$output" == *"clean=<Ready.  >"* ]]
}

@test "ui_bottom_link_line_into keeps default background in unicode mode" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    UI_BORDER_H="─"
    UI_BORDER_BOTTOM_LEFT="└"
    UI_BORDER_BOTTOM_RIGHT="┘"

    ui_bottom_link_line_into out 8
    clean="$(printf "%s" "$out" | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
    has_fg=0
    has_bg=0
    [[ "$out" == *$'\''\033[38;2;42;161;152m'\''* ]] && has_fg=1
    [[ "$out" == *$'\''\033[48;2;42;161;152m'\''* ]] && has_bg=1
    printf "has_fg=%s\n" "$has_fg"
    printf "has_bg=%s\n" "$has_bg"
    printf "clean=<%s>\n" "$clean"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"has_fg=1"* ]]
  [[ "$output" == *"has_bg=0"* ]]
  [[ "$output" == *"clean=<▄▄▄▄▄▄▄▄>"* ]]
}

@test "ui_render_main includes selected row marker" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/constants.sh"
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    APP_ROWS=($'\''node\t123\talice\t22u\t*:3000\t3000\t*\tTCP'\'' $'\''nginx\t45\troot\t6u\t127.0.0.1:80\t80\t127.0.0.1\tTCP'\'')
    APP_STATUS_MESSAGE="Ready."

    tput() {
      case "$1" in
        lines) printf "20\n" ;;
        cols) printf "80\n" ;;
        *) return 0 ;;
      esac
    }

    ui_render_main 1 0 "Ready."
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"> 80"* ]]
}

@test "ui_render_main keeps long command visible on wide terminal" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/constants.sh"
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    APP_ROWS=($'\''this-is-a-very-long-command-name-which-should-fit\t123\talice\t22u\t*:3000\t3000\t*\tTCP'\'')
    APP_STATUS_MESSAGE="Ready."

    tput() {
      case "$1" in
        lines) printf "20\n" ;;
        cols) printf "120\n" ;;
        *) return 0 ;;
      esac
    }

    ui_render_main 0 0 "Ready."
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"this-is-a-very-long-command-name-which-should-fit"* ]]
}

@test "ui_build_main_frame truncates command and bind to column widths" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/constants.sh"
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    APP_ROWS=($'\''super-super-long-command-name-that-must-be-truncated\t123\talice\t22u\t*:3000\t3000\tvery-long-bind-hostname-value\tTCP'\'')
    APP_STATUS_MESSAGE="Ready."

    tput() {
      case "$1" in
        lines) printf "20\n" ;;
        cols) printf "70\n" ;;
        *) return 0 ;;
      esac
    }

    ui_build_main_frame 1 0 "Ready."
    row=""
    for line in "${UI_NEXT_LINES[@]}"; do
      clean_line="$(printf "%s" "$line" | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
      if [[ "$clean_line" == *"super-super-long-command"* ]]; then
        row="$line"
        break
      fi
    done
    clean="$(printf "%s" "$row" | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
    tildes="$(printf "%s" "$clean" | awk -F"~" "{print NF-1}")"

    printf "len=%s\n" "${#clean}"
    printf "tildes=%s\n" "$tildes"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"len=70"* ]]
  [[ "$output" == *"tildes=2"* ]]
}

@test "ui_build_main_frame fills full terminal dimensions" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/constants.sh"
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    APP_ROWS=($'\''node\t123\talice\t22u\t*:3000\t3000\t*\tTCP'\'')
    APP_VERSION="0.1.0"

    tput() {
      case "$1" in
        lines) printf "18\n" ;;
        cols) printf "60\n" ;;
        *) return 0 ;;
      esac
    }

    ui_build_main_frame 0 0 "Ready."
    printf "rows=%s\n" "${#UI_NEXT_LINES[@]}"

    ok=1
    for line in "${UI_NEXT_LINES[@]}"; do
      clean="$(printf "%s" "$line" | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
      if [ "${#clean}" -ne 60 ]; then
        ok=0
      fi
      if [[ "$clean" == *"gatan 0.1.0"* ]]; then
        has_label=1
      fi
    done
    printf "width_ok=%s\n" "$ok"
    printf "has_label=%s\n" "${has_label:-0}"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"rows=18"* ]]
  [[ "$output" == *"width_ok=1"* ]]
  [[ "$output" == *"has_label=1"* ]]
}

@test "ui_build_main_frame keeps exact height when terminal is compact and no rows" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/constants.sh"
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    APP_ROWS=()
    APP_VERSION="0.1.0"

    tput() {
      case "$1" in
        lines) printf "8\n" ;;
        cols) printf "40\n" ;;
        *) return 0 ;;
      esac
    }

    ui_build_main_frame 0 0 "Ready."
    printf "rows=%s\n" "${#UI_NEXT_LINES[@]}"
    clean_border="$(printf "%s" "${UI_NEXT_LINES[5]}" | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
    printf "border=%s\n" "$clean_border"
    clean_last="$(printf "%s" "${UI_NEXT_LINES[6]}" | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
    printf "last=%s\n" "$clean_last"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"rows=8"* ]]
  [[ "$output" == *"border=+--------------------------------------+"* ]]
  [[ "$output" == *"last=  ↑/↓ move | Enter inspec~ gatan 0.1.0"* ]]
}

@test "ui_render_inspect uses framed layout" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    APP_INSPECT_CONTENT=$'\''cwd: /tmp\ncmdline: node server.js'\''

    tput() {
      case "$1" in
        lines) printf "12\n" ;;
        cols) printf "50\n" ;;
        *) return 0 ;;
      esac
    }

    ui_build_inspect_frame 123 "node server.js" "Ready."
    for idx in 0 1 2 8 10; do
      clean="$(printf "%s" "${UI_NEXT_LINES[$idx]}" | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
      printf "line%s=<%s>\n" "$idx" "$clean"
    done
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"line0=<  Inspect PID 123 (node server.js)"* ]]
  [[ "$output" == *"line1=<                                                  >"* ]]
  [[ "$output" == *"line2=<  cwd: /tmp"* ]]
  [[ "$output" == *"line8=<  Ready."* ]]
  [[ "$output" == *"line10=<"* ]]
  [[ "$output" == *"b back | k kill | r refresh | q quit"* ]]
}

@test "ui_build_inspect_frame bolds top labels and open-files header" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    APP_INSPECT_CONTENT=$'\''PID      123\nPPID     1\nUSER     alice\nCOMMAND  /usr/bin/node\nCWD      /tmp\n\nOpen files (first 20):\nCOMMAND PID USER FD\nnode 123 alice cwd\n\nTop snapshot (PID 123):\nPID         123\nCOMMAND     node\nCPU         0.0\nMEM         20M'\''

    tput() {
      case "$1" in
        lines) printf "24\n" ;;
        cols) printf "80\n" ;;
        bold) printf "\033[1m" ;;
        sgr0) printf "\033[0m" ;;
        *) return 0 ;;
      esac
    }

    ui_build_inspect_frame 123 "node server.js" "Ready."

    pid_line=""
    header_line=""
    cpu_line=""
    for idx in "${!UI_NEXT_LINES[@]}"; do
      clean="$(printf "%s" "${UI_NEXT_LINES[$idx]}" | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
      case "$clean" in
        "  PID"*) pid_line="${UI_NEXT_LINES[$idx]}" ;;
        "  COMMAND PID USER FD"*) header_line="${UI_NEXT_LINES[$idx]}" ;;
        "  CPU"*) cpu_line="${UI_NEXT_LINES[$idx]}" ;;
      esac
    done

    has_pid_bold=0
    has_header_bold=0
    has_cpu_bold=0
    [[ "$pid_line" == *$'\''\033[1m'\''* ]] && has_pid_bold=1
    [[ "$header_line" == *$'\''\033[1m'\''* ]] && has_header_bold=1
    [[ "$cpu_line" == *$'\''\033[1m'\''* ]] && has_cpu_bold=1
    printf "pid_bold=%s\n" "$has_pid_bold"
    printf "header_bold=%s\n" "$has_header_bold"
    printf "cpu_bold=%s\n" "$has_cpu_bold"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"pid_bold=1"* ]]
  [[ "$output" == *"header_bold=1"* ]]
  [[ "$output" == *"cpu_bold=1"* ]]
}

@test "ui_paint_frame updates only changed rows in incremental mode" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    ui_term_emit() {
      printf "<%s" "$1"
      if [ -n "${2:-}" ]; then
        printf ",%s" "$2"
      fi
      if [ -n "${3:-}" ]; then
        printf ",%s" "$3"
      fi
      printf ">"
    }

    UI_INCREMENTAL_SUPPORTED=1
    UI_FORCE_FULL_REDRAW=0
    UI_FRAME_WIDTH=10
    UI_FRAME_HEIGHT=2
    UI_FRAME_LINES=("row0" "old")
    UI_NEXT_WIDTH=10
    UI_NEXT_HEIGHT=2
    UI_NEXT_LINES=("row0" "new")

    ui_paint_frame
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"<cup,1,0><el>new"* ]]
  [[ "$output" != *$'\033[H\033[2J'* ]]
}

@test "ui_paint_frame performs full redraw when forced" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    source "$PROJECT_ROOT/lib/gatan/ui.sh"

    ui_term_emit() {
      printf "<%s" "$1"
      if [ -n "${2:-}" ]; then
        printf ",%s" "$2"
      fi
      if [ -n "${3:-}" ]; then
        printf ",%s" "$3"
      fi
      printf ">"
    }

    UI_INCREMENTAL_SUPPORTED=1
    UI_FORCE_FULL_REDRAW=1
    UI_FRAME_WIDTH=10
    UI_FRAME_HEIGHT=2
    UI_FRAME_LINES=("old0" "old1")
    UI_NEXT_WIDTH=10
    UI_NEXT_HEIGHT=2
    UI_NEXT_LINES=("new0" "new1")

    ui_paint_frame
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[H\033[2J'* ]]
  [[ "$output" == *"<cup,0,0><el>new0<cup,1,0><el>new1"* ]]
}
