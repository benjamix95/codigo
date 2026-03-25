# Changelog — 2026-03-25 — Swift Concurrency & Warning Fixes

## Categoria: B — Importante ma non bloccante
## Tipo: bug fix (strict concurrency compliance, warning cleanup)

---

## Riepilogo

Fix di 11 warning/errori di compilazione legati a Swift strict concurrency (main actor isolation) e warning minori (variabili inutilizzate, conformance protocollo).

---

## File modificati

### 1. `DesignSystem+ViewHelpers.swift`
- **Bug:** `WindowResizeHelper.adjustWidth` accedeva a API MainActor (`NSApplication.shared`, `NSWindow.frame`, `setFrame`) da contesto nonisolated
- **Fix:** Aggiunto `@MainActor` al metodo statico

### 2. `AppDelegate+DockMenu.swift`
- **Bug:** `openNewWindowFromDock` e `triggerMainMenuNewWindowAction` accedevano a `NSApplication.shared.sendAction`/`.mainMenu` da contesto nonisolated
- **Fix:** Aggiunto `@MainActor` a entrambi i metodi

### 3. `ComposerTextView.swift`
- **Bug:** `ComposerTextViewFocusCoordinator` e `ComposerTextViewUpdateCoordinator` accedevano a proprietà MainActor (`window`, `firstResponder`, `string`, `text`, `onSubmit`, `onTextChange`, `onFocusChange`, `isFocused`)
- **Fix:** Marcati entrambi gli enum come `@MainActor`

### 4. `InlineEditTextView.swift`
- **Bug:** `handleReturn()` e `handleCancel()` accedevano a `parent.onSubmit`/`parent.onCancel` da contesto nonisolated
- **Fix:** Aggiunto `@MainActor` a entrambi i metodi

### 5. `BrowserPanelView+WebView.swift`
- **Bug:** Firma di `webView(_:decidePolicyFor:decisionHandler:)` non matchava esattamente il protocollo `WKNavigationDelegate` (nomi parametri + `@MainActor` sulla closure)
- **Fix:** Corretti nomi parametri (`wv` → `webView`, `nav` → `navigationAction`) e aggiunto `@MainActor` alla closure `decisionHandler`

### 6. `SwarmPanelView+Detail.swift`
- **Bug:** Variabile `cardAccent` inizializzata ma mai usata
- **Fix:** Rimossa la dichiarazione

### 7. `ChatPanelView+PartB_ComposerUI.swift`
- **Bug:** `Self.attachmentPastedNotification` (proprietà MainActor-isolated statica) referenziata da dentro una Sendable closure
- **Fix:** Catturata in variabile locale `notificationName` prima della closure

### 8. `MessageToolTraceView+EventMetadata.swift` + `MessageToolTraceView+Helpers.swift`
- **Bug:** `isErrorType` e `isWarningType` (metodi statici su View, quindi MainActor-isolated) chiamati da `MessageToolTraceToolIdentity.resolve` (nonisolated)
- **Fix:** Marcati `nonisolated` nella definizione in Helpers.swift

### 9. `MessageToolTraceView+State.swift`
- **Bug:** `hardErrorTypes` (static let su View) referenziato da contesto nonisolated in `DerivedState.isErrorEvent`
- **Fix:** Marcato `nonisolated(unsafe) static let`

### 10. `EventDeliveryManager.swift`
- **Bug:** `await self.drainWaitingQueue()` — metodo sincrono dell'actor chiamato con `await` non necessario
- **Fix:** Rimosso `await`

### 11. `ClaudeCLIProvider+Parsing.swift`
- **Bug:** `normalizedTool` dichiarato ma mai usato
- **Fix:** Rimossa la dichiarazione

---

## Rischi laterali
- Nessuno. Tutti i fix aggiungono annotazioni di isolation o rimuovono codice morto. Nessuna modifica alla logica di business.
- `nonisolated` su `isErrorType`/`isWarningType` è sicuro perché accedono solo ai parametri e a `hardErrorTypes` (costante immutabile).
- `nonisolated(unsafe)` su `hardErrorTypes` è sicuro perché è un `let` inizializzato staticamente (thread-safe per definizione).
