# Changelog — 2026-03-25 — UI Rendering Performance Round 3

## Contesto
Terza passata di ottimizzazione. Focus su @Published notification frequency e hot-path allocations.

## Fix applicati

### 1. ChatStore fallbackUpdateAssistantContent — Singola mutazione
**File**: `ChatStore+RustBridge.swift`
- Due assegnazioni separate a `conversations[i].messages[j]` coalescete in una singola scrittura. Dimezza le @Published notifications durante streaming content.

### 2. scopedTaskActivities — Zero-allocation comparison
**File**: `ChatPanelView+PartS_End.swift`
- `.lowercased()` per-activity (nuova String allocation) → `.caseInsensitiveCompare()` (zero allocazioni).

### 3. PanelResizeHandle — 2pt threshold
**File**: `DesignSystem+ViewHelpers.swift`
- Binding setter da 60+ updates/sec durante drag → ~30/sec con threshold 2pt.

## File modificati
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartS_End.swift`
- `App/SoloCodeApp/Sources/App/DesignSystem/DesignSystem+ViewHelpers.swift`

## Verifica
- Build compilato con successo (`Solo Code-Debug` scheme) ✅
