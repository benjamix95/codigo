# 2026-03-20 — Fix signing del runner test macOS

## Modifiche
- aggiornato [bootstrap_test_bundles.sh](/Users/benjaminstoica/SoloCode/scripts/bootstrap_test_bundles.sh) per:
  - rilevare l’identità di firma reale dell’host app buildato
  - rifirmare bundle `.xctest`, binari Mach-O e framework annidati con la stessa identità
  - rifirmare l’host app alla fine del bootstrap
  - usare un flow bash più robusto per l’iterazione sui bundle test

## Motivazione
- evitare che i bundle test annidati restino `adhoc` mentre l’host app è firmata `Apple Development`, condizione che portava il runner a `SIGKILL (Code Signature Invalid)`.

## Verifica
- `xcodebuild build-for-testing -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `scripts/bootstrap_test_bundles.sh /Users/benjaminstoica/Library/Developer/Xcode/DerivedData/Solo_Code-cfsobsdrrqgfsfahsxtjerkqwfos/Build/Products/Debug`
- `xcodebuild test-without-building -xctestrun '/Users/benjaminstoica/Library/Developer/Xcode/DerivedData/Solo_Code-cfsobsdrrqgfsfahsxtjerkqwfos/Build/Products/Solo Code-Debug_macosx26.2-arm64.xctestrun' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/PlanFlowPhaseTests -only-testing:SoloCodeAppTests/PlanBuildIntegrationFlowTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/PlanFlowPhaseTests -only-testing:SoloCodeAppTests/PlanBuildIntegrationFlowTests`
