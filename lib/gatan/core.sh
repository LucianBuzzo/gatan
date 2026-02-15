#!/usr/bin/env bash

core_require_dependencies() {
  local cmd
  local missing=()

  for cmd in sudo lsof awk ps kill tput stty sort cut; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'Missing required commands: %s\n' "${missing[*]}" >&2
    return 1
  fi

  return 0
}

core_raw_lsof() {
  # `+c 0` asks lsof for full command names (no default 9-char truncation).
  sudo lsof +c 0 -nP -iTCP -sTCP:LISTEN 2>/dev/null
}

# Emit normalized listener rows as tab-delimited fields:
# command, pid, user, fd, name, port, bind, proto
core_collect_listeners() {
  core_raw_lsof | awk '
    NR == 1 { next }
    NF < 9 { next }
    {
      command = $1
      pid = $2
      user = $3
      fd = $4
      name = $9

      gsub(/\(LISTEN\)/, "", name)
      gsub(/[[:space:]]+/, "", name)

      port = ""
      bind = name
      if (name ~ /:[0-9]+$/) {
        port = name
        sub(/^.*:/, "", port)

        bind = name
        sub(/:[0-9]+$/, "", bind)
        if (bind == "") {
          bind = "*"
        }
      }

      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\tTCP\n", command, pid, user, fd, name, port, bind
    }
  '
}

core_sort_rows() {
  awk -F '\t' '
    {
      sort_port = $6
      if (sort_port == "" || sort_port !~ /^[0-9]+$/) {
        sort_port = 999999
      }

      sort_pid = $2
      if (sort_pid == "" || sort_pid !~ /^[0-9]+$/) {
        sort_pid = 999999
      }

      printf "%09d\t%09d\t%s\n", sort_port + 0, sort_pid + 0, $0
    }
  ' | sort | cut -f 3-
}

core_collect_sorted_listeners() {
  core_collect_listeners | core_sort_rows
}

core_row_field() {
  local row="$1"
  local index="$2"

  printf '%s\n' "$row" | awk -F '\t' -v idx="$index" '{print $idx}'
}
