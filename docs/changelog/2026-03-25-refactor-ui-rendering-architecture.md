# Changelog — 2026-03-25 — Refactoring Architetturale UI Rendering

## Contesto
Refactoring strutturale per risolvere 4 problemi architetturali che causavano re-rendering eccessivo durante lo streaming. Ogni task è un commit indipendente e revertibile.

## Task completati

### Task 1: MarkdownContentView @AppStorage → @Environment
**Commit**: `a3591348b`
- Creato `MarkdownSettings` struct + `EnvironmentKey` + `MarkdownSettingsProvider`
- 4 `@AppStorage` per-view → 1 `@Environment` read. Settings iniettati una volta al root messagesArea.
- Backward-compatible accessors preservano API per tutte le extension files.

### Task 2: ChatStore objectWillChange Throttle
**Commit**: `df6becbab`
- Rimosso `@Published` da `conversations` — il campo più mutato durante streaming.
- Aggiunto throttle 150ms (pattern ToolTraceStore): notifiche coalescate durante streaming, immediate fuori streaming.
- Le altre 5 `@Published` properties (rare mutazioni) invariate.

### Task 3: ChatStreamingState Split
**Commit**: `c1d6d60b7`
- Estratto `ChatScrollState` (3 campi auto-scroll) da `ChatStreamingState` (12 campi rimanenti).
- Mutazioni scroll non invalidano più i views che osservano content/reasoning.
- Aggiornati 5 file con rename meccanico `streaming.autoScroll*` → `scrollState.autoScroll*`.

### Task 4: ChatTurnView Equatable via Action Enum
**Commit**: `688ca8250`
- Creato `ChatTurnAction` enum (7 azioni) che sostituisce 7 closure parameters.
- Rimosso `@ObservedObject todoStore`, passato `todoItems: [TodoItem]` pre-computato.
- `canEdit`/`canDelete` Bool sostituiscono closure opzionali.
- Aggiunta conformance `Equatable` — SwiftUI può ora saltare re-render di messaggi invariati.

## Task non implementati (valutazione costi/benefici)

### Task 5: Conversation.messages Reference-Type Wrapper — SKIPPED
- **Motivo**: Con il throttle Task 2 (150ms), le notifiche COW sono già coalescate. Il COW di Swift arrays è O(1) amortizzato (reference counting). Il costo reale era la NOTIFICA, non la copia. ROI insufficiente vs rischio di dual-source-of-truth.

### Task 6: ChatPanelView EnvironmentObject Reduction — SKIPPED
- **Motivo**: Gli `@EnvironmentObject` sono usati direttamente nelle extension methods via `self.storeXYZ`. Rimuoverli richiede refactoring di tutte le extension che li referenziano — scope troppo ampio. I 3 store meno usati (`editorNavigationDispatchStore`, `browserTabManager`, `providerUsageStore`) cambiano raramente durante streaming, quindi l'impatto è minimo.

## Riepilogo impatto
| Fix | Riduzione re-render |
|-----|-------------------|
| ChatStore throttle 150ms | ~6x durante streaming (da ~50 notifiche/sec a ~7) |
| ChatScrollState separato | Elimina invalidazione content/reasoning su scroll |
| ChatTurnView Equatable | Elimina rebuild di messaggi invariati nel ForEach |
| MarkdownSettings Environment | N×4 → 1 UserDefaults read per ciclo render |
