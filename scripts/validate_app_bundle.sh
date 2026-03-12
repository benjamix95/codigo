#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 0 ]; then
  APP_PATH="$1"
elif [ -n "${APP_PATH:-}" ]; then
  APP_PATH="$APP_PATH"
else
  echo "usage: $0 '/path/to/Solo Code.app'" >&2
  exit 64
fi

if [ ! -d "$APP_PATH" ]; then
  echo "app bundle not found: $APP_PATH" >&2
  exit 66
fi

required_paths=(
  "$APP_PATH/Contents/MacOS/Solo Code"
  "$APP_PATH/Contents/MacOS/coderide-mcp-server"
  "$APP_PATH/Contents/MacOS/coderide-mcp-server-rust"
  "$APP_PATH/Contents/MacOS/mcp-lifecycle-backend-rust"
  "$APP_PATH/Contents/Frameworks/CoderEngine.framework/CoderEngine"
  "$APP_PATH/Contents/Frameworks/CoderIDEMCPServer.framework/CoderIDEMCPServer"
)

for required_path in "${required_paths[@]}"; do
  if [ ! -e "$required_path" ]; then
    echo "missing required runtime artifact: $required_path" >&2
    exit 67
  fi
done

if [ -f "$APP_PATH/Contents/MacOS/Solo Code.debug.dylib" ]; then
  if ! otool -L "$APP_PATH/Contents/MacOS/Solo Code.debug.dylib" | grep -q '@rpath/CoderEngine.framework/Versions/A/CoderEngine'; then
    echo "Solo Code.debug.dylib is missing the expected CoderEngine runtime link" >&2
    exit 68
  fi
fi

codesign --verify --deep --strict "$APP_PATH" >/dev/null

echo "validated app bundle: $APP_PATH"
