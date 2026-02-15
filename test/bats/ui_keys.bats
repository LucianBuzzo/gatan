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
    row="${UI_NEXT_LINES[5]}"
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
    done
    printf "width_ok=%s\n" "$ok"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"rows=18"* ]]
  [[ "$output" == *"width_ok=1"* ]]
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
    printf "last=%s\n" "${UI_NEXT_LINES[7]}"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"rows=8"* ]]
  [[ "$output" == *"last=+--------------------------------------+"* ]]
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

    ui_render_inspect 123 "node server.js" "Ready."
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"+------------------------------------------------+"* ]]
  [[ "$output" == *"|Inspect PID 123 (node server.js)"* ]]
  [[ "$output" == *"|Keys: b back  k kill  r refresh  q quit"* ]]
  [[ "$output" == *"|cwd: /tmp"* ]]
  [[ "$output" == *"|Ready."* ]]
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
