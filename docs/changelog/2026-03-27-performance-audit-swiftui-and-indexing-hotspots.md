# 2026-03-27 - Audit performance: SwiftUI invalidation fan-out e indexing I/O

## Cosa ho fatto

- verificato lo stack reale del repo e confinato l'analisi ai path chat/sidebar/indexing;
- letto il sample esistente `.cursor/debug-7e54b6-sample.txt`;
- eseguito benchmark smoke selettivo con `xcodebuild` sul test `CodebaseIndexIndexingBenchmarkSmokeTests`;
- ispezionato i path di runtime e persistenza con riferimenti puntuali di codice;
- documentato i colli di bottiglia confermati in `docs/bugs`.

## Finding confermati

- la sidebar continua a ricostruire snapshot/render state globali durante lo streaming;
- il path `refreshMessagesSnapshot()` della chat resta troppo ampio e mantiene lavoro ripetuto sul `MainActor`;
- il full indexing del workspace fa ancora traversal filesystem e metadata collection seriali prima del lavoro parallelo;
- la persistenza/load dell'indice semantico mantiene path bulk con allocazioni e rewrite completi;
- nel build/test path esiste anche un overhead secondario: la fase `Sync tool_descriptions Swift` viene eseguita ad ogni build perche' non usa dependency analysis.

## Misure ed evidenze

- sample esistente:
  - peak physical footprint osservato: `490.1M`
  - main thread dominato da layout/render SwiftUI-AppKit
- benchmark smoke selettivo:
  - comando usato: `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodebaseIndexIndexingBenchmarkSmokeTests/testIndexingBenchmarkSmoke`
  - esito: test passato
  - sul dataset sintetico default da 40 file, il log mostra `SemanticIndex.buildIndex` completato in circa `12-14 ms`, segnale che il collo di bottiglia principale non e' il micro-dataset sintetico ma il lavoro di traversal/index bootstrap e la UI invalidation sui workspace reali

## Documentazione creata

- `docs/bugs/P1-2026-03-27-sidebar-thread-snapshot-refresh-recomputes-whole-list-during-streaming.md`
- `docs/bugs/P1-2026-03-27-chat-snapshot-refresh-fanout-keeps-main-thread-hot.md`
- `docs/bugs/P2-2026-03-27-codebase-index-full-scan-still-does-serial-filesystem-traversal.md`
- `docs/bugs/P2-2026-03-27-semantic-index-persistence-still-rewrites-large-snapshots.md`

## Verifica

- nessuna modifica runtime applicata in questo passaggio
- benchmark smoke selettivo passato
- audit statico completato con riferimenti di codice e sample reale
