# Changelog — 2026-03-29

## Chat
- Il footer `Task completed` ora compare anche quando l’ultimo messaggio assistant è terminale ma il flag `isStreaming` è rimasto stale in memoria.

## Composer
- Il timer finale del composer usa un tone semantico:
  - verde su completamento corretto
  - rosso su interruzione/errore del programma
  - neutro su stop manuale utente
- La UI del timer runtime è stata estratta in [`ChatComposerView+RuntimeTimer.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+RuntimeTimer.swift).
