#!/usr/bin/env bash

is_code_file_for_size_guard() {
  local path="$1"
  [[ "$path" == App/SoloCodeApp/Resources/* ]] && return 1
  [[ "$path" == *".xcassets/"* ]] && return 1
  [[ "$path" == App/SoloCodeApp/Resources/monaco/* ]] && return 1
  [[ "$path" == *.swift || "$path" == *.sh || "$path" == *.rb || "$path" == *.rs ]] || return 1
  return 0
}

line_count_for_size_guard() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
print(len(text.splitlines()) if text else 0)
PY
}

validate_code_size_limit() {
  local file=""
  for file in "$@"; do
    [[ -z "$file" ]] && continue
    is_code_file_for_size_guard "$file" || continue
    [[ -f "$file" ]] || continue
    local lines
    lines="$(line_count_for_size_guard "$file")"
    if [[ "$lines" -gt 300 ]]; then
      local old_lines=""
      if git cat-file -e "HEAD:$file" >/dev/null 2>&1; then
        old_lines="$(git show "HEAD:$file" | python3 -c 'import sys; print(len(sys.stdin.read().splitlines()))')"
      fi
      if [[ -z "$old_lines" || "$old_lines" -le 300 || "$lines" -gt "$old_lines" ]]; then
        return 1
      fi
    fi
  done
  return 0
}

dedupe_cli_args() {
  local deduped=()
  local arg=""
  for arg in "$@"; do
    [[ -z "$arg" ]] && continue
    local skip="false"
    local existing=""
    for existing in "${deduped[@]-}"; do
      [[ "$existing" == "$arg" ]] && skip="true"
    done
    [[ "$skip" == "false" ]] && deduped+=("$arg")
  done
  printf '%s\n' "${deduped[@]-}"
}
