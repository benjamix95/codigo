# Changelog — 2026-03-27 — Todo pipeline follow-up fix

## Modifiche applicate
- aggiunto `TodoStore+FollowUpGating.swift` per bloccare l’aggiornamento dei follow-up canonici (`Code Review & Test`, `Doc Writer`) quando il piano non li contiene davvero
- aggiornato `PipelineIntegrationService+EventMapping.swift` per evitare che completion reviewer/testWriter/docWriter completi step canonici fuori contesto
- aggiornato `PipelineIntegrationService+EventSupport.swift` per ignorare `todo_write` di follow-up non previsti dal piano canonico
- aggiornato `ChatPanelView+PartF_TodoEvents.swift` per:
  - applicare lo stesso gating nel path plan-build
  - disabilitare l’injection implicita dei follow-up runtime
- aggiornato `TodoStore+Mutations+Lifecycle.swift` per preservare i todo `done` durante i clear standard, così restano visibili barrati

## Test / verifica
- aggiunti test di regressione in `PipelineIntegrationServiceTests.swift` per reviewer/raw follow-up senza entry canonica
- aggiunti test di regressione in `TodoStoreTests.swift` per la preservazione dei completed nei clear
- aggiunto test in `TodoExecutionRuntimeFollowUpTests.swift` per confermare che i follow-up runtime non vengono più inseriti implicitamente
- eseguito:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/TodoStoreTests -only-testing:SoloCodeAppTests/TodoExecutionRuntimeFollowUpTests CODE_SIGNING_ALLOWED=NO`
- risultato: **70 test eseguiti, 0 failure**

## Impatto funzionale atteso
- `Code Review & Test` e `Doc Writer` non compaiono o non avanzano più fuori contesto canonico
- l’ordine sequenziale non viene alterato da follow-up non previsti
- i todo completati restano nella lista con strikethrough invece di sparire al primo clear/reset
