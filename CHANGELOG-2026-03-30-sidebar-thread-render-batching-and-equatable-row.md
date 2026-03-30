# Changelog — 2026-03-30

## Fix Sidebar: batching stato attività thread + row content Equatable

### Bug corretti

1. **Batch activity state for sidebar threads**
   - **Descrizione:** il builder dello stato render della sidebar filtrava `activities + pendingActivities` per ogni thread per capire se esisteva attività visibile non-swarm.
   - **Impatto:** refresh `O(thread * activity)` con costo ridondante ad ogni invalidazione di sidebar render state.
   - **Priorità:** alta.
   - **Area coinvolta:** `TaskActivityStore` scoped queries, `SidebarThreadSnapshotBuilder`.

2. **Invalidazione larga del subtree visivo della row**
   - **Descrizione:** la row SwiftUI della sidebar costruiva l’intero subtree visivo inline nell’extension di `SidebarView`, rendendo più facile invalidare tutte le row quando cambiava il render state globale.
   - **Impatto:** re-render completi non necessari di row non toccate dal cambiamento.
   - **Priorità:** alta.
   - **Area coinvolta:** `SidebarThreadCard.swift`.

### Cosa è cambiato
- `TaskActivityStore+ScopedQueries.swift`
  - aggiunto `concreteNonSwarmConversationScopesIncludingPending()` che precomputa una `Set<String>` con gli scope conversazione aventi attività concreta visibile non-swarm, includendo anche `pendingActivities`.
- `SidebarThreadRenderState.swift`
  - il builder dei render state crea una `RenderComputationContext` per refresh e riusa membership lookup `O(1)` per ogni thread invece di rifiltrare l’array attività per ciascuna conversazione.
  - invarianti mantenute:
    - una row è `active` solo se esiste attività concreta visibile non-swarm per quello scope conversazione;
    - `isStreaming` resta vero solo se il thread streamma **e** c’è attività visibile coerente;
    - gli eventi swarm non promuovono più da soli un thread a stato attivo.
- `SidebarThreadCard.swift`
  - estratto `SidebarThreadRowContent: View, Equatable` per confinare il subtree visivo della row a proprietà scalari/equatable.
  - mantenuti fuori dal subtree equatable solo i modifier interattivi (`contextMenu`, gesture di selezione).
- `Tests/SoloCodeAppTests/SidebarThreadSnapshotTests.swift`
  - aggiunti test per pending activity visibile e per esclusione degli eventi solo-swarm dal calcolo dei thread attivi.

### Perché
- Il collo di bottiglia osservato era la combinazione tra invalidazioni frequenti del render state e lavoro per-thread ripetuto sugli stessi array di attività.
- Il fix minimizza il lavoro per refresh senza cambiare il contratto dati tra store e sidebar.

### File toccati
- `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+ScopedQueries.swift`
- `App/SoloCodeApp/Sources/App/Sidebar/SidebarThreadRenderState.swift`
- `App/SoloCodeApp/Sources/App/Sidebar/Sections/SidebarThreadCard.swift`
- `Tests/SoloCodeAppTests/SidebarThreadSnapshotTests.swift`

### Validazione
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SidebarThreadSnapshotTests`
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SidebarViewTests`
- audit read-only:
  - `coderide_audit_bug_diff_risks` → nessun pattern di regressione evidente nel perimetro.
  - `coderide_audit_bug_test_impact` → nessun gap test evidente sui simboli pubblici toccati.

### Rischi / note
- `coderide_read_lints` non era disponibile per il perimetro Swift in questa sessione.
- `coderide_diagnostics` è andato in timeout a 120s; la compilazione del perimetro modificato è comunque passata durante le suite `SidebarThreadSnapshotTests` e `SidebarViewTests`.
- Il diff resta confinato al layer sidebar/task-activity e non modifica il protocollo eventi pipeline.
