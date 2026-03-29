# Changelog — 2026-03-29

## Test Hardening
- Rafforzata la protezione regressioni sulla cronologia della chat con una suite molto più estesa su:
  - ordering testo/tool/subagent
  - grouping exploration e terminal
  - fallback sintetico con tool marker
  - anchoring dei subagent
  - casi anti-monolite

## Manutenibilità
- La vecchia suite enorme sulla timeline è stata spezzata in più file tematici, tutti sotto soglia:
  - [`ChatTimelineInterleavingCoreTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingCoreTests.swift)
  - [`ChatTimelineInterleavingToolGroupingTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingToolGroupingTests.swift)
  - [`ChatTimelineInterleavingSubagentTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingSubagentTests.swift)
  - [`ChatTimelineInterleavingSyntheticTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingSyntheticTests.swift)
  - [`ChatTimelineInterleavingSupport.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingSupport.swift)
