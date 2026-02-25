#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOWLIST_FILE="$ROOT_DIR/scripts/english_only_allowlist.txt"

TARGETS=(
  "$ROOT_DIR/CoderEngine/Sources"
  "$ROOT_DIR/Sources/CoderIDE"
  "$ROOT_DIR/CoderEngine/Tests"
  "$ROOT_DIR/Tests/CoderIDETests"
)

# High-signal Italian words and accented vowels that should not appear
# in runtime prompts, user-facing text, tests, or comments.
PATTERN='\b(aggiorna|allineare|analisi|analizzo|atteso|avviato|avviata|completato|completata|contesto|elenca|errore|esegui|eseguo|esito|fallita|fallito|mancante|mancanti|nessun|obbligatorio|obbligatoria|permesso|rilevato|selezione|simbolo|simboli|stato|trovato|trovata|turno|ragionamento)\b|[àèéìòù]'

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required" >&2
  exit 2
fi

matches="$(rg -n --pcre2 -i "$PATTERN" "${TARGETS[@]}" || true)"
if [[ -z "$matches" ]]; then
  echo "english-only check passed"
  exit 0
fi

if [[ -f "$ALLOWLIST_FILE" ]]; then
  filtered=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    keep=1
    while IFS= read -r allow; do
      [[ -z "$allow" || "$allow" =~ ^# ]] && continue
      if [[ "$line" =~ $allow ]]; then
        keep=0
        break
      fi
    done < "$ALLOWLIST_FILE"

    if [[ $keep -eq 1 ]]; then
      filtered+="$line"$'\n'
    fi
  done <<< "$matches"
  matches="$filtered"
fi

if [[ -n "$matches" ]]; then
  echo "english-only check failed. Non-English snippets detected:" >&2
  echo "$matches" >&2
  exit 1
fi

echo "english-only check passed"
