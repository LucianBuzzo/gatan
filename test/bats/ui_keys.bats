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
  [ "$output" = "Terminate PID 42? [y/N] rc=0 force=1" ]
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
