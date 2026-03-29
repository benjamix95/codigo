# Changelog - 2026-03-29 - Completed subagents collapsible section

## Modifiche

- aggiunto il modello `ChatTurnCompletedSubagentsGroup` per rappresentare in modo canonico i sub-agent terminali aggregati nella timeline
- introdotta una sezione collassabile dedicata ai sub-agent completati/falliti con header compatto, badge numerico e stato iniziale collassato
- spostato il rendering dei segmenti timeline in `ChatTurnSegmentView.swift` e la categorizzazione tool in `ChatTurnView+ToolGrouping.swift` per mantenere `ChatTurnView.swift` sotto la soglia dimensionale richiesta
- aggiornato `ChatTurnTimelineInterleaver` per:
  - lasciare inline solo le live card `running`
  - raccogliere i terminali in un unico segmento `completedSubagentsGroup`
  - ancorare cronologicamente il gruppo alla prima `sequence` utile
  - deduplicare per `swarmId`, escludendo snapshot stale se esiste un live `running` e preferendo il live terminale al persistito
- riallineato il fallback legacy `subagentCardsSection(...)` alla nuova presentazione aggregata

## Test

- aggiornati i test di interleaving sub-agent per coprire:
  - gruppo terminale ancorato alla sequence corretta
  - stato misto `running` + `completed`
  - ordine interno del gruppo con più sub-agent
  - precedenza live vs snapshot persistito
- aggiunti test dedicati alla presentazione della nuova sezione collassabile
- validazione eseguita con:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTimelineInterleavingSubagentTests -only-testing:SoloCodeAppTests/ChatTimelineInterleavingToolGroupingTests -only-testing:SoloCodeAppTests/ChatTurnCompletedSubagentsGroupPresentationTests`

## Note

- nessuna modifica a persistenza `subagentCards`, runtime swarm o protocollo eventi
- warning esterni di `xcodebuild` su device passcode-protected e linking XCTest/macOS 14 non hanno impedito il completamento della suite selezionata
