## 2026-03-22

## Modifiche
- corretto il wrapper di validazione in [scripts/solocode-validate](/Users/benjaminstoica/SoloCode/scripts/solocode-validate) per non crashare quando `FILES` o `TEST_ARGS` sono vuoti sotto Bash 3.2 con `set -u`
- aggiunta una regressione in [SoloCodeValidateScriptTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/Validation/SoloCodeValidateScriptTests.swift) per coprire:
  - `ciFull` senza file espliciti
  - validazione native-only con target test vuoti
- documentato il failure in [P1-2026-03-22-solocode-validate-ciFull-crash-bash-3.2-empty-array.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-22-solocode-validate-ciFull-crash-bash-3.2-empty-array.md)

## Test
- verifica manuale del wrapper:
  - `scripts/solocode-validate --trigger ciFull --workspace /Users/benjaminstoica/SoloCode --format text`
- verifica della pipeline macOS di supporto:
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Release' -destination 'platform=macOS'`
- verifica della regressione:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/SoloCodeValidateScriptTests`

## Validazione
- la `ciFull` ora supera i gate `codeSize` e `rustCutoverBoundary`
- la release build del workspace completa con successo sullo stato corrente del repo

## Rischio controllato
- nessuna modifica alla semantica dei gate esistenti
- nessun fallback nuovo nel validation pipeline, solo hardening contro array vuoti
