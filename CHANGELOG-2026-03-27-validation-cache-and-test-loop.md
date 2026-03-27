# Changelog

Data: 2026-03-27
Tema: validation/build loop

## Modifiche

- estratto helper shell condiviso per i path Xcode e per la validazione file-size, portando `scripts/solocode-validate` sotto il limite di righe richiesto
- introdotte cache persistenti per `DerivedData` e package resolution
- resa condizionale la `-resolvePackageDependencies` sia in `scripts/solocode-validate` sia in `scripts/build-xcode-stable.sh`
- eliminata la build debug ridondante quando i targeted tests usano già `build-for-testing`
- mantenuta la build `Release` solo sul trigger `ciFull`
- riabilitato `parallel-testing-enabled YES` per i test mirati

## Test

- `xcodebuild test -quiet -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/SoloCodeValidateScriptTests`
