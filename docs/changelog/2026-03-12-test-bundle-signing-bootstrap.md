# 2026-03-12 — Fix bootstrap firma test bundle

## Modifiche
- aggiornato [bootstrap_test_bundles.sh](/Users/benjaminstoica/SoloCode/scripts/bootstrap_test_bundles.sh)

## Cosa cambia
- il bootstrap dei bundle test continua a rimuovere `com.apple.provenance` e `com.apple.quarantine`
- la rifirma non avviene più in modo indiscriminato
- se la firma esistente è già valida, lo script non la sostituisce
- se la firma va rigenerata, viene preferita l’identità di build di Xcode (`EXPANDED_CODE_SIGN_IDENTITY`) invece della firma ad-hoc

## Validazione eseguita
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests`

## Esito
- il runner `xctest` non si blocca più sul `library load denied by system policy` del bundle `CoderEngineTests.xctest`
