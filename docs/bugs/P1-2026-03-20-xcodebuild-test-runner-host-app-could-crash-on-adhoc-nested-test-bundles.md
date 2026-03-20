# P1 - `xcodebuild test` poteva far crashare l’host app sui test bundle annidati firmati `adhoc`

## Bug Fix Record
- Categoria: A
- Bug: il runner `xcodebuild test` per lo scheme `Solo Code-Debug` continuava a morire in bootstrap con `SIGKILL (Code Signature Invalid)` quando i bundle `.xctest` annidati dentro `Solo Code.app/Contents/PlugIns` restavano firmati `adhoc`.
- Sintomo:
  - `xcodebuild build` verde
  - `xcodebuild test` rosso con `Early unexpected exit`
  - crash report `.ips` con namespace `CODESIGNING` e `Invalid Page`
  - `SoloCodeAppTests.xctest` e `SoloCodeIntegrationTests.xctest` risultavano `Signature=adhoc` mentre l’host app era firmata `Apple Development`
- Impatto: impossibilità di chiudere qualsiasi tranche app-side che richiedesse `xcodebuild test`, inclusa la migrazione Rust della `main chat`.
- Gravita': critica, perche' bloccava la validazione obbligatoria app-side.
- Steps to reproduce:
  1. Eseguire `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests`.
  2. Osservare il crash bootstrap del runner.
  3. Ispezionare `Solo Code.app/Contents/PlugIns/SoloCodeAppTests.xctest` con `codesign -dvv` e verificare `Signature=adhoc`.
- Risultato attuale: il runner host poteva venire terminato dal sistema prima dell’esecuzione dei test.
- Risultato atteso: i bundle test annidati devono essere firmati con la stessa identità reale dell’host, non `adhoc`, e il runner deve poter eseguire i test.
- Causa probabile: il bootstrap test post-build non riallineava la firma dei `.xctest` annidati all’identità dell’host app; `xcodebuild test-without-building` confermava che il problema restava anche fuori dal pre-action di build.
- Scope consentito:
  - [bootstrap_test_bundles.sh](/Users/benjaminstoica/SoloCode/scripts/bootstrap_test_bundles.sh)
  - scheme test `Solo Code-Debug`
  - docs bug/changelog
- Non-scope:
  - logica della `main chat`
  - provider transport
  - persistence `ChatStore`
- Moduli confinanti da verificare:
  - `SoloCodeAppTests`
  - `CoderEngineTests`
  - `SoloCodeIntegrationTests`
  - `bootstrap_test_bundles.sh`
- Test da aggiungere o aggiornare:
  - verifica manuale/operativa di `codesign -dvv` sui bundle annidati
  - smoke `build-for-testing -> bootstrap -> test-without-building`
- Strategia di fix minimo:
  - determinare l’identità di firma reale dell’host app
  - rifirmare bundle test, binari Mach-O e framework annidati con quella stessa identità
  - rifirmare infine l’host app dopo il bootstrap dei test bundle
  - rendere il bootstrap robusto anche su rilanci manuali
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `scripts/bootstrap_test_bundles.sh <BUILT_PRODUCTS_DIR>`
  - `xcodebuild test-without-building -xctestrun '/Users/benjaminstoica/Library/Developer/Xcode/DerivedData/Solo_Code-cfsobsdrrqgfsfahsxtjerkqwfos/Build/Products/Solo Code-Debug_macosx26.2-arm64.xctestrun' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/PlanFlowPhaseTests -only-testing:SoloCodeAppTests/PlanBuildIntegrationFlowTests`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/PlanFlowPhaseTests -only-testing:SoloCodeAppTests/PlanBuildIntegrationFlowTests`
- Commit previsto: `fix(test-runner): sign nested test bundles with host identity`

## Effetto osservato
- Il runner `xcodebuild test` torna a eseguire i test app-side mirati senza crash di bootstrap.
- I bundle test annidati non restano più `adhoc` quando l’host app usa una firma reale.
