# P2 — Click su `x-xcode-log://…` in chat non apriva il log in Xcode

## Bug Fix Record

- Priorità: P2
- Categoria: B — Importante (integrazione IDE / flusso debug)
- Bug: nei messaggi chat e nel markdown inline i link con schema `x-xcode-log://` (riferimenti al log di build/IDE come mostrati da Xcode) non venivano aperti in modo affidabile perché il routing passava da `OpenURLAction.systemAction` senza una gestione esplicita dei deep link macOS/Xcode.
- Sintomo: l’utente clicca sul link `x-xcode-log://<UUID>` (es. copiato dall’UI Xcode) e l’azione non risolve correttamente verso Xcode, bloccando la lettura del log associato dal contesto chat.
- Impatto: frustrazione nel flusso “copia link log da Xcode → chat / click per riaprire”; dipendenza da workaround manuali (aprire Xcode a mano, cercare il log).
- Gravità: media-alta per chi usa la chat come bacheca operativa accanto a Xcode.
- Steps to reproduce:
  1. In Xcode, ottenere o visualizzare un riferimento tipo `x-xcode-log://<UUID>`.
  2. Incollare il testo in un messaggio assistente o riceverlo in markdown.
  3. Cliccare sul link nell’app Solo Code.
- Risultato attuale (prima del fix): il routing non garantiva l’apertura via Launch Services/Workspace per questo schema custom.
- Risultato atteso: il click apre il log/target gestito da `x-xcode-log` sul sistema (tipicamente Xcode), come per altri link esterni controllati.
- Causa probabile: uso generico di `.systemAction(url)` per URL non-`file://` senza allowlist né `NSWorkspace.shared.open` esplicito per schemi IDE noti.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Utilities/MessageLinkRouter.swift`
  - `App/SoloCodeApp/Sources/Chat/ClickableMessageContent.swift`
  - `App/SoloCodeApp/Sources/Editor/Markdown/MarkdownContentView+Renderers.swift`
  - `Tests/SoloCodeAppTests/MessageLinkRouterTests.swift`
  - documentazione `docs/bugs`, `docs/bugfix-records`, `docs/changelog`
- Non-scope:
  - registrare nuovi URL scheme nell’app per sostituire Xcode
  - parsing del contenuto interno del log o bridge MCP xcodebuild
- Moduli confinanti da verificare:
  - altre view che wrappano `OpenURLAction` con stesso pattern (eventuale allineamento futuro)
- Test da aggiungere o aggiornare:
  - `MessageLinkRouterTests` (disposition `x-xcode-log`, `file://`, schemi respinti tipo `javascript:`)
- Strategia di fix minimo:
  - centralizzare il routing in `MessageLinkRouter`: file interni → callback editor; `http`/`https`/`mailto`/`x-xcode-log` → `NSWorkspace.shared.open`; altro → `.discarded`
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/MessageLinkRouterTests -only-testing:SoloCodeAppTests/MarkdownFileReferenceLinkingTests`
  - smoke manuale: click su `x-xcode-log://…` in una bubble chat
- Commit previsto:
  - `fix(chat): route x-xcode-log links via MessageLinkRouter`
