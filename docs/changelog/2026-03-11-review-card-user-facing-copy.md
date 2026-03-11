# 2026-03-11 — Review card user-facing copy

## Cosa cambia

- Rimosso il naming tecnico `Unified Review Pipeline` dal card di stato review.
- Rimappate le fasi visibili a label utente-facing:
  - `Avvio`
  - `Controlli`
  - `Verifica`
  - `Preparazione fix`
  - `Risultati pronti`
- Il contatore del card ora mostra `Fase X di 5` invece di `X/6 steps`.
- Aggiornati anche i copy secondari del card e dell’empty state per non esporre il termine `pipeline`.

## Verifica eseguita

- `cargo test --manifest-path Native/RustCore/Cargo.toml review_reduce::panel::tests::derive_review_panel_state_exposes_progressive_buckets`
- `xcodebuild -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64' build`
