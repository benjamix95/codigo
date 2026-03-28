# Changelog — 2026-03-28

## Fix Sidebar: snapshot refresh now captures filter inputs before debounce

### Cosa è cambiato
- La Sidebar cattura `contextId`, `query`, `showArchived` e `favoritesOnly` al momento in cui pianifica il refresh della lista thread.
- Il refresh differito non rilegge più lo stato live dopo 120ms, evitando che un cambio di contesto successivo svuoti o alteri la lista precedente.
- `SidebarThreadSnapshotBuilder` ora espone un request object riusabile per costruire snapshot e fingerprint in modo deterministico.
- È stata aggiunta una regressione che verifica che una snapshot costruita con un request catturato rimanga stabile anche se lo stato della chat cambia dopo.

### Perché
- La lista thread della Sidebar poteva cambiare contesto durante il debounce e mostrare una lista vuota o incompleta dopo la creazione di un nuovo thread.
- Il bug era intermittente perché dipendeva dal timing tra gli aggiornamenti di stato e il refresh differito della UI.

### File toccati
- `App/SoloCodeApp/Sources/App/Sidebar/SidebarThreadListSnapshot.swift`
- `App/SoloCodeApp/Sources/App/Sidebar/SidebarView+Support.swift`
- `Tests/SoloCodeAppTests/SidebarThreadSnapshotTests.swift`
