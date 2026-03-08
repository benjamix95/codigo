# 2026-03-08 - Review panel chat autoscroll fix

## Obiettivo
Correggere l’assenza di auto-scroll nel pannello Code Review, sia nella lista messaggi della chat sia nella card `ACTIVITY` renderizzata dentro le bubble `REVIEW RUN`.

## Modifiche
- aggiunto `ReviewPanelChatAutoscroll.swift` per centralizzare i fingerprint che determinano quando la chat deve ri-ancorarsi in basso
- aggiornata `ReviewPanelChatTab.swift` per usare un bottom anchor dedicato e reagire non solo al testo, ma anche ai cambiamenti della `presentation` e dello stato streaming dell’ultimo messaggio
- aggiunto `ReviewPanelChatStructuredLogView.swift` per gestire l’auto-scroll interno delle sezioni structured di tipo log
- aggiornata `ReviewPanelChatStructuredSectionsView.swift` per delegare il rendering dei log al nuovo componente specializzato
- aggiunti test in `ReviewPanelChatAutoscrollTests.swift` per coprire i trigger di auto-scroll della chat e del log activity

## Verifica
- tentata esecuzione di:
  - `xcodebuild test -project '/Users/benjaminstoica/SoloCode/Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -configuration Debug -derivedDataPath '/Users/benjaminstoica/SoloCode/.build/SoloCodeDebugDerivedData' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelChatAutoscrollTests -only-testing:SoloCodeAppTests/ReviewPanelChatStructuredContentTests`
- esito: build bloccata da errore preesistente fuori scope in `Engine/CoderEngine/Sources/Providers/Core/ToolEnabledLLMProvider/Subagents/ToolEnabledLLMProvider+SkillExecution.swift`
- verifica manuale richiesta dopo il fix: avviare una review live e confermare che la chat e la sezione `ACTIVITY` seguano sempre l’ultimo evento

## Note
- non sono stati modificati runtime, provider o skill execution path per evitare espansione silenziosa del perimetro
