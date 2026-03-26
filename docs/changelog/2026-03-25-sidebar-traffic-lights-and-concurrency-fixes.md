# Changelog — 2026-03-25 — Sidebar Traffic Lights + Concurrency Fixes

## Commit 1: fix(ui): restore custom traffic lights and sidebar toggle button

### Problema
I semafori nativi macOS (close/minimize/zoom) e il pulsante custom per aprire/chiudere
la sidebar erano spariti dall'interfaccia. Il vecchio `WindowChromeAccessor` (NSViewRepresentable
invisibile) non renderizzava più correttamente i controlli.

### Modifiche
| File | Azione |
|------|--------|
| `App/SoloCodeApp/Sources/App/Content/WindowChromeControls.swift` | Riscritto: da NSViewRepresentable invisibile a HStack SwiftUI con cerchi colorati custom |
| `App/SoloCodeApp/Sources/App/Content/WindowControlKind.swift` | **Nuovo file**: enum `WindowControlKind` con colori, glifi hover e azioni finestra |

### Dettagli
- Rimosso `WindowChromeAccessor` (NSViewRepresentable) che controllava alpha/enabled dei bottoni nativi
- Creati cerchi SwiftUI custom (rosso/giallo/verde) con glifo overlay al hover (×, −, ↗)
- Ripristinato pulsante sidebar toggle con styling coerente (icona `sidebar.leading`, bordo sottile, background semi-trasparente)
- Controlli allineati sulla stessa riga del titolo chat tramite HStack
- Rispetto dello stato `controlActiveState` per opacità in finestra inattiva

---

## Commit 2: fix(swift): resolve strict concurrency warnings across 5 modules

### Problema
Warning di strict concurrency (Swift 6 readiness) su 5 moduli dopo abilitazione
di `-strict-concurrency=complete`.

### Modifiche
| File | Fix |
|------|-----|
| `WorkspaceStore+ProjectContextSync.swift` | Cattura copie locali di `pendingReasoningSnapshot` e `renderedTextSnapshot` prima di attraversare il boundary `MainActor.run`, evitando violazioni Sendable su stato mutabile |
| `AppUpdateCenter.swift` | `static let defaultManifestURL` → `nonisolated static let` per conformità Sendable |
| `MessageToolTraceView+State.swift` | `nonisolated(unsafe) static let hardErrorTypes` → `nonisolated static let` (Set immutabile, inherentemente Sendable) |
| `VectorSearchEngineBackend.swift` | `private let store` → `private nonisolated(unsafe) let store` per conformità Sendable mantenendo semantica reference |
| `MCPLifecycleRustBackend.swift` | `managedProcess` marcato `nonisolated(unsafe)` per cleanup da `deinit` nonisolated; `terminateBackendProcess()` → `nonisolated func`; rimosso `self.managedProcess = nil` da scope nonisolated |
