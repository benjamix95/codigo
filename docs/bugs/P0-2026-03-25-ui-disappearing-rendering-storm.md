# P0 — UI Disappearing / Black Screen During Streaming

**Data**: 2026-03-25
**Categoria**: A — Critico
**Sintomo**: La UI sparisce per secondi durante lo streaming e riappare solo con resize della finestra o dopo un timeout.
**Stato**: ✅ TUTTI I BUG FIXATI — build verificato

---

## Root Cause Analysis

Il problema è causato da una **tempesta di re-rendering** durante lo streaming. Molteplici fattori concorrono:

### BUG 1 — streamContentVersion onChange troppo frequente (P0) ✅ FIXATO
- **File**: `ChatPanelView+PartC_MessageHeader.swift:255`
- **Problema**: `streamContentVersion` viene incrementato da **17 punti diversi** nel codice. Ogni incremento scatena `onChange` → `handleStreamContentVersionChange` → `scheduleAutoScroll(delay: 0.04)`.
- **Fix**: Throttle centralizzato in `scheduleAutoScroll` con minInterval a 0.35s coalesce tutti i burst.

### BUG 2 — 5x delayed window style reapplication (P0) ✅ FIXATO
- **File**: `ContentView+Layout+Composition.swift:156-162`
- **Problema**: Ad ogni cambio di `coderMode`, `applyMainWindowStyle` veniva chiamato **6 volte** (1 immediata + 5 ritardate fino a 2.0s).
- **Fix**: Ridotto a una singola applicazione ritardata a 0.3s.

### BUG 3 — scheduleAutoScroll throttle insufficiente (P0) ✅ FIXATO
- **File**: `ChatPanelView+PartE_TaskLifecycle.swift:215-252`
- **Problema**: Throttle di soli 0.20s. `withAnimation(.easeOut)` bloccava il layout engine.
- **Fix**: Throttle aumentato a 0.35s. Rimossa `withAnimation` dallo scroll automatico. Rimosso double-schedule in `handleActiveTaskConversationChange`.

### BUG 4 — GeometryReader cascade nel chatHeader (P1) ✅ FIXATO
- **File**: `ChatPanelView+PartC_MessageHeader.swift:133-143`
- **Problema**: GeometryReader aggiornava stato via `DispatchQueue.main.async` ad ogni sub-pixel change → loop di feedback.
- **Fix**: Threshold di 4px prima dell'update. Rimosso `DispatchQueue.main.async` superfluo.

### BUG 5 — Double frame + fixedSize su MessageRow (P1) ✅ FIXATO
- **File**: `MessageRow.swift:66-68`
- **Problema**: Doppio `.frame(maxWidth:)` + `.fixedSize()` = doppio layout pass per messaggio.
- **Fix**: Rimosso il primo `.frame(maxWidth: .infinity)` ridondante.

### BUG 6 — Timer-based animations senza cleanup robusto (P2) ✅ FIXATO
- **File**: `MessageRow+Indicators.swift:10-63`
- **Problema**: `Timer.scheduledTimer` + `withAnimation` poteva leakare timer durante rapida aggiunta/rimozione views.
- **Fix**: Sostituito con `TimelineView` — lifecycle gestito nativamente da SwiftUI.

### BUG 7 — Multiple onChange handlers tutti schedulando scroll (P1) ✅ FIXATO
- **File**: `ChatPanelView+PartC_MessageScrollState.swift:25-82`
- **Problema**: 6 handler con delay 0.04-0.16s si accavallavano, generando scroll duplicati.
- **Fix**: Delay staggerati (0.04, 0.12, 0.14) + rimozione `animated: true` + rimozione `DispatchQueue.main.async` superflui per `isFollowingLive`.

### BUG 8 — Stacked .animation(.none, value:) (P2) ✅ FIXATO
- **File**: `ChatPanelView+RootLayout.swift:121-125`
- **Problema**: 5 modifier `.animation(.none, value:)` impilati con overhead di valutazione.
- **Fix**: Sostituiti con singolo `.transaction { $0.animation = nil }`.

### BUG 9 — SPM Package.resolved divergente (P1) ✅ FIXATO
- **File**: `Solo Code.xcodeproj/.../Package.resolved`
- **Problema**: swift-nio 2.96.0 nel `.xcodeproj` aveva un cycle bug (Logging ↔ CNIOWindows). Il `.xcworkspace` usava correttamente 2.95.0.
- **Fix**: Sincronizzati i Package.resolved. Aggiunto `buildIndependentTargetsInParallel = YES` e `WorkspaceSettings.xcsettings`.

---

## File Modificati

| File | Tipo di Fix |
|------|------------|
| `ChatPanelView+PartE_TaskLifecycle.swift` | Throttle 0.35s, rimossa withAnimation scroll |
| `ContentView+Layout+Composition.swift` | Window style reapply da 6x a 1x |
| `ChatPanelView+PartC_MessageHeader.swift` | GeometryReader threshold 4px |
| `ChatPanelView+PartC_MessageScrollState.swift` | Delay staggerati, rimossi async superflui |
| `MessageRow.swift` | Rimosso double frame |
| `MessageRow+Indicators.swift` | Timer → TimelineView |
| `ChatPanelView+RootLayout.swift` | 5x animation(.none) → 1x transaction |
| `Solo Code.xcodeproj/.../Package.resolved` | Sync swift-nio 2.95.0 |
| `Solo Code.xcodeproj/project.pbxproj` | buildIndependentTargetsInParallel |
| `Solo Code.xcodeproj/.../WorkspaceSettings.xcsettings` | Build system settings |

---

## Verifica

- [x] Build passa con workspace (`Solo Code-Debug` scheme)
- [x] Build passa con xcodeproj (`Solo Code-Debug` scheme)
- [ ] La UI non sparisce durante streaming prolungato
- [ ] Il resize della finestra non è più necessario per ripristinare la visibilità
- [ ] Lo scroll automatico funziona ancora correttamente durante lo streaming
- [ ] Nessuna regressione nei pannelli laterali (Plan, Debug, Swarm, CodeReview, Git)
