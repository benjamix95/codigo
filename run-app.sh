#!/bin/bash
# Avvia CoderIDE – utile se swift run non mostra la finestra
cd "$(dirname "$0")"
swift build -c release 2>/dev/null || swift build
exec .build/debug/CoderIDE 2>/dev/null || .build/release/CoderIDE
