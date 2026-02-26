#!/bin/bash
# Launch CoderIDE — useful when swift run doesn't show the window
cd "$(dirname "$0")"
swift build -c release 2>/dev/null || swift build
exec .build/debug/CoderIDE 2>/dev/null || .build/release/CoderIDE
