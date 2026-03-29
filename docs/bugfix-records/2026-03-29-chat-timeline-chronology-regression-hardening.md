# Bugfix Record — 2026-03-29

## Scope
- Rafforzare in modo aggressivo la copertura di regressione sulla cronologia della chat.
- Suddividere la suite della timeline in più file tematici per evitare un nuovo file-test monolitico.

## Modifiche
- Rimossa la vecchia suite monolitica `ChatTimelineInterleavingTests.swift` e suddivisa in:
  - [`ChatTimelineInterleavingSupport.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingSupport.swift)
  - [`ChatTimelineInterleavingCoreTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingCoreTests.swift)
  - [`ChatTimelineInterleavingToolGroupingTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingToolGroupingTests.swift)
  - [`ChatTimelineInterleavingSubagentTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingSubagentTests.swift)
  - [`ChatTimelineInterleavingSyntheticTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingSyntheticTests.swift)
- Aggiunte regressioni mirate per:
  - ordinamento per `sequence` e tie-break per timestamp;
  - grouping exploration/terminal e divieti di grouping cross-boundary;
  - ancoraggio live/snapshot dei subagent tramite `swarm_id`;
  - casi senza anchor che devono restare in coda cronologica;
  - preservazione dei blocchi testuali multipli e synthetic timeline fallback per evitare nuovi output monolitici.

## Test
- [`ChatTimelineInterleavingCoreTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingCoreTests.swift)
- [`ChatTimelineInterleavingToolGroupingTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingToolGroupingTests.swift)
- [`ChatTimelineInterleavingSubagentTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingSubagentTests.swift)
- [`ChatTimelineInterleavingSyntheticTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingSyntheticTests.swift)
- [`ChatTurnTimelineInterleaverTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTurnTimelineInterleaverTests.swift)
- [`ChatTurnTimelineOrderingTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTurnTimelineOrderingTests.swift)

## Rischi controllati
- Nessuna modifica runtime alla timeline.
- Solo hardening di regressione e miglioramento della manutenibilità della suite.
