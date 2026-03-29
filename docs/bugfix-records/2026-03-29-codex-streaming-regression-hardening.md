# Bugfix Record — 2026-03-29

## Scope
- Rafforzare in modo mirato la copertura di regressione sullo streaming Codex.

## Modifiche
- Aggiunte suite dedicate:
  - [`CodexStreamingPolicyRegressionTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodexStreamingPolicyRegressionTests.swift)
  - [`CodexStreamingContentRegressionTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodexStreamingContentRegressionTests.swift)
  - [`CodexStreamingCompletionRegressionTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodexStreamingCompletionRegressionTests.swift)
- Le nuove regressioni coprono:
  - routing del testo Codex verso la bolla risposta e non nel canale reasoning;
  - alias/provider codex-based;
  - routing standard stream vs fallback pipeline;
  - ownership dei raw callback per assistant update e turn started;
  - promozione dei partial assistant update;
  - merge reasoning e strip dei marker;
  - finalizzazione terminale con `isStreaming` stale;
  - mapping degli outcome finali.

## Test
- `xcodebuild test` mirato sulle tre nuove suite.

## Rischi controllati
- Nessuna modifica runtime.
- Solo hardening di regressione sul comportamento già funzionante.
