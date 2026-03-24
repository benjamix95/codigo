# Changelog — 2026-03-25 — Fix UI Disappearing / Black Screen During Streaming

## Problema
La UI spariva per secondi durante lo streaming degli strumenti, riapparendo solo con resize della finestra o dopo un timeout. Causato da una "tempesta di rendering" — molteplici fonti di aggiornamento stato saturavano il main thread con layout pass e scroll operations sovrapposti.

## Fix applicati

### 1. scheduleAutoScroll — Throttle aggressivo (P0)
**File**: `ChatPanelView+PartE_TaskLifecycle.swift`
- Aumentato `autoScrollMinInterval` da 0.20s a **0.35s** per coalescere burst di scroll
- **Rimossa l'animazione `withAnimation(.easeOut)`** dallo scroll automatico — bloccava il layout engine durante streaming rapido
- Rimosso double-schedule (0s + 0.16s) in `handleActiveTaskConversationChange`, sostituito con singolo scroll a 0.08s

### 2. Window style reapplication — Da 6x a 1x (P0)
**File**: `ContentView+Layout+Composition.swift`
- **Eliminati 5 dei 6 `applyMainWindowStyle`** ritardati (0.3s, 0.6s, 1.0s, 1.5s, 2.0s). Ogni reapplicazione forzava un ridisegno completo della finestra.
- Mantenuta una sola applicazione ritardata a 0.3s (sufficiente per attendere il layout pass SwiftUI)

### 3. GeometryReader cascade — Threshold 4px (P1)
**File**: `ChatPanelView+PartC_MessageHeader.swift`
- Aggiunto threshold di **4px** prima di aggiornare `chatHeaderWidth` nel GeometryReader
- Rimosso `DispatchQueue.main.async` non necessario nell'onAppear (siamo già sul main thread)
- Spezza il loop: GeometryReader → state change → view rebuild → GeometryReader

### 4. DispatchQueue.main.async superflui — Rimossi (P1)
**File**: `ChatPanelView+PartC_MessageScrollState.swift`
- Rimossi `DispatchQueue.main.async { isFollowingLive = true }` — il codice è già sul main thread in SwiftUI, l'async dispatch aggiungeva un ciclo di run loop extra inutile

### 5. MessageRow double frame — Rimosso (P1)
**File**: `MessageRow.swift`
- Rimosso il primo `.frame(maxWidth: .infinity)` duplicato. Due `.frame()` consecutivi con `.fixedSize()` forzavano due layout pass separati per ogni messaggio visibile durante lo streaming.

### 6. Timer → TimelineView per indicatori animati (P2)
**File**: `MessageRow+Indicators.swift`
- `StreamingDots` e `TypingIndicator` sostituiti da `Timer.scheduledTimer` a `TimelineView`
- `TimelineView` è gestito dal lifecycle SwiftUI — nessun rischio di timer leak durante rapida aggiunta/rimozione views dallo streaming

### 7. onChange handlers — Delay staggerati (P1)
**File**: `ChatPanelView+PartC_MessageScrollState.swift`
- `handleMessagesCountChange`: delay da 0.05 → **0.12s** (prima si accavallava con streamContentVersion a 0.04s)
- `handleLiveTraceEventsChange`: delay da 0.05 → **0.14s** (fallback, non primario)
- Rimosso `animated: true` dal messagesCount handler (ora gestito centralmente senza animazione)

### 8. Stacked animation modifiers → Transaction (P2)
**File**: `ChatPanelView+RootLayout.swift`
- 5 `.animation(.none, value:)` impilati → singolo `.transaction { $0.animation = nil }`
- Riduce overhead di valutazione per ogni cambio stato dei pannelli

### 9. SPM Package.resolved — Sync versioni (P1)
**File**: `Solo Code.xcodeproj/.../Package.resolved`, `project.pbxproj`, `WorkspaceSettings.xcsettings`
- Sincronizzato swift-nio da 2.96.0 (con cycle bug Logging ↔ CNIOWindows) a **2.95.0**
- Allineati anche swift-argument-parser (1.7.1→1.7.0), swift-collections (1.4.1→1.4.0), SwiftTerm (1.12.0→1.11.2)
- Aggiunto `buildIndependentTargetsInParallel = YES` nel project
- Creato `WorkspaceSettings.xcsettings` per build system moderno

## File modificati
- `App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartE_TaskLifecycle.swift`
- `App/SoloCodeApp/Sources/App/Content/Sections/ContentView+Layout+Composition.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageHeader.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageScrollState.swift`
- `App/SoloCodeApp/Sources/ChatView/MessageRow/MessageRow.swift`
- `App/SoloCodeApp/Sources/ChatView/MessageRow/MessageRow+Indicators.swift`
- `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+RootLayout.swift`
- `Solo Code.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `Solo Code.xcodeproj/project.pbxproj`
- `Solo Code.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings`

## Documentazione bug
- `docs/bugs/P0-2026-03-25-ui-disappearing-rendering-storm.md`

## Verifica
- Build compilato con successo — workspace (`Solo Code-Debug` scheme) ✅
- Build compilato con successo — xcodeproj (`Solo Code-Debug` scheme) ✅
- Nessuna modifica funzionale — solo ottimizzazione dei cicli di rendering
