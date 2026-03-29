# Changelog — 2026-03-29

## Test Hardening
- Aggiunta una suite dedicata di regressione sullo streaming Codex:
  - [`CodexStreamingPolicyRegressionTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodexStreamingPolicyRegressionTests.swift)
  - [`CodexStreamingContentRegressionTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodexStreamingContentRegressionTests.swift)
  - [`CodexStreamingCompletionRegressionTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodexStreamingCompletionRegressionTests.swift)

## Copertura nuova
- Regole di routing testo/reasoning specifiche di Codex.
- Merge e promozione dei chunk streaming.
- Finalizzazione terminale con flag streaming stale.
- Outcome completion/abort/failure.
