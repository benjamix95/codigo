# 2026-03-23 - Codex app-server UI panel open and delta whitespace

## Modifiche

- estratta la policy di apertura del plan panel in helper testabile
- estratta la policy di visibilita' del task panel in helper testabile
- aggiornato il bridge `ChatPanelView` per usare le nuove policy invece di affidarsi a stato UI implicito
- corretto il transport Rust `codex_app_server` per preservare whitespace e newline nei delta della risposta

## Verifica

- test app-side sulle policy di apertura pannelli
- test Rust-side sulla preservazione del testo delta
