# Changelog - 2026-03-29 - Codex snapshot partial grace fix

- La grace lunga anti-store-vuoto resta attiva solo quando lo store torna **completamente vuoto**.
- Le riduzioni parziali del numero messaggi tornano a usare una finestra breve, così Codex non resta bloccato su snapshot vecchi e monolitici.
- Aggiunta regressione in [`ChatPanelMessageSnapshotPolicyTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatPanelMessageSnapshotPolicyTests.swift) per il caso `partial loss` ritardato.
