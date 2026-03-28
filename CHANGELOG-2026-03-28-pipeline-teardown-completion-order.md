# Changelog — 2026-03-28

## Fix: pipeline teardown/completion ordering

### Problema trovato
- Il callback `onCompletion` della pipeline veniva eseguito prima della rimozione effettiva del runtime e prima della pubblicazione dello stato finale.
- Questo lasciava `isRunning(for:)` ancora vero durante il callback e rendeva il runtime ancora visibile a chi reagiva alla completion.
- In parallelo, il teardown non chiudeva in modo atomico il percorso degli eventi debounced della pipeline.

### Correzione applicata
- In `PipelineIntegrationService+Teardown.swift` il teardown ora marca il runtime come finalizing prima del flush degli eventi pendenti.
- Il callback `onCompletion` viene eseguito solo dopo che runtime, snapshot e stato task sono stati rimossi.
- Il debounce task della bridge pipeline viene cancellato durante il teardown per evitare callback tardive.

### Regresione aggiunta
- In `PipelineIntegrationServiceTests.swift` è stato aggiunto un test che verifica che, dentro `onCompletion`, la pipeline risulti già chiusa:
  - `isRunning(for:) == false`
  - `snapshot(for:) == nil`
  - `chatStore.isTaskActive(for:) == false`

### Impatto
- Riduce il rischio di callback che vedono stato stale.
- Evita che il completamento pipeline blocchi transizioni successive o reazioni di UI/flow che richiedono il runtime già chiuso.
