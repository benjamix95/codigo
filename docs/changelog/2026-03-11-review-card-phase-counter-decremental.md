# 2026-03-11 — Review card phase counter decremental

## Cosa cambia

- Il contatore fasi del card review passa da progressivo a decrementale.
- Le label utente-facing ora leggono il countdown atteso:
  - `Avvio` = `Fase 5 di 5`
  - `Controlli` = `Fase 4 di 5`
  - `Verifica` = `Fase 3 di 5`
  - `Preparazione fix` = `Fase 2 di 5`
  - `Risultati pronti` = `Fase 1 di 5`

## Verifica eseguita

- `xcodebuild -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64' build`
