# [P1] `bootstrap_test_bundles.sh` poteva sostituire la firma valida dei test bundle con una firma ad-hoc non caricabile da `xctest`

## Contesto
- emerso durante i rilanci di `xcodebuild test` su `CoderEngineTests-Debug`
- il bundle `CoderEngineTests.xctest` era stato già costruito e firmato da Xcode, ma il bootstrap post-build interveniva di nuovo su firme e xattr

## Sintomo
- `xctest` falliva a caricare `CoderEngineTests.xctest` con:
  - `code signature ... not valid for use in process: library load denied by system policy`

## Causa probabile
- lo script [bootstrap_test_bundles.sh](/Users/benjaminstoica/SoloCode/scripts/bootstrap_test_bundles.sh) rifirmava sempre con `codesign --sign -`
- questo comportamento poteva rimpiazzare una firma valida emessa da Xcode con una firma ad-hoc meno adatta al caricamento del bundle da parte del runner test

## Fix applicato
- strip degli xattr lasciato invariato
- la rifirma ora avviene solo se la firma esistente è davvero invalida
- quando serve rifirmare, lo script usa prima `EXPANDED_CODE_SIGN_IDENTITY` se disponibile e degrada a `-` solo in fallback

## Validazione
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests`

## Stato
- risolto
