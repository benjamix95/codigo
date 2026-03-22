#!/bin/zsh
set -euo pipefail

REAL_SWIFTC="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
IDENTITY="Apple Development: BENIAMIN JONY STOICA (D882NQ3CY3)"
LOG_FILE="/tmp/swift_exec_manifest_wrapper.log"

printf '%s\n' "$0 $*" >> "$LOG_FILE"
"$REAL_SWIFTC" "$@"

output=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then
    output="$arg"
    break
  fi
  prev="$arg"
done

if [[ -n "$output" && -f "$output" ]]; then
  /usr/bin/codesign --force --sign "$IDENTITY" "$output" >> "$LOG_FILE" 2>&1 || true
fi
