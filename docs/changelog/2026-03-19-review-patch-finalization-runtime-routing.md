# 2026-03-19 — Review patch finalization runtime routing

## Modifiche
- `ReviewPatchRuntimeFinalizationService` non costruisce più localmente la patch preview con `ReviewPatchWorkflowService`
- il path di finalizzazione deferred usa ora `VerifiedFindingsPatchExecutionService.execute(action: "prepare_patch", ...)`
- aggiunto supporto nell’executor patch a un execution provider diretto per riusare il runtime patch anche fuori dal command path
- corretta la risoluzione del provider in lazy mode, così `close_finding` e altre azioni che non ne hanno bisogno non falliscono per prerequisiti estranei
- aggiornati i test del patch workflow e del provider selection path

## Motivazione
- ridurre un altro ramo Swift-owned del patch workflow e far convergere `prepare_patch/verify_patch` sullo stesso boundary centrale

## Verifica
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests`
