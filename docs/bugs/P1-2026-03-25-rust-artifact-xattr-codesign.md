# P1 — com.apple.provenance su artifact Rust rompe codesign

**Date:** 2026-03-25
**Category:** B — Importante ma non bloccante
**Component:** Build scripts Rust (`build_rust_search_backend.sh`, `build_rust_mcp_server.sh`, `build_rust_mcp_lifecycle_backend.sh`)
**Status:** Risolto

---

## Bug

Dopo `cp` di artifact Rust compilati, macOS aggiunge l'extended attribute
`com.apple.provenance` (e talvolta resource fork) al file copiato.
Quando Xcode esegue il codesign dell'app bundle, trova questi xattr e fallisce con:
```
resource fork, Finder information, or similar detritus not allowed
```

## Sintomo

Codesign fallisce durante la build su artifact Rust gia correttamente compilati.

## Impatto

Build fallisce nella fase di signing. Workaround manuale era eseguire `xattr -cr`
a mano sul bundle.

## Causa

macOS aggiunge `com.apple.provenance` ai file copiati da determinate sorgenti.
Gli script di build Rust copiano i binari senza strippare gli xattr.

## Fix applicato

Aggiunto `xattr -cr <file> 2>/dev/null || true` dopo ogni `cp` nei tre script:
- `build_rust_search_backend.sh`: nella funzione `copy_artifact()`
- `build_rust_mcp_server.sh`: dopo cp in test output e bundle dir
- `build_rust_mcp_lifecycle_backend.sh`: dopo cp di tutti i binari

Aggiunta anche `add_strip_xattr_phase()` in `generate_xcode_project.rb` che
esegue `xattr -cr` sull'intero app bundle come safety net prima del codesign.

## Moduli confinanti

Nessun modulo confinante impattato — fix isolato negli script di copia.
