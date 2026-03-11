# P1 - Lo scheme app `Solo Code-Debug` non compila per simbolo `SidebarView` mancante

## Bug Fix Record
- Categoria: A - Critico
- Bug: il target app fallisce la compilazione per `SidebarView` non definito.
- Sintomo: `xcodebuild test -scheme 'Solo Code-Debug'` si interrompe in build con `cannot find 'SidebarView' in scope`.
- Impatto: impedisce l’esecuzione dei test `SoloCodeAppTests`, inclusi quelli che verificano struttura progetto e command loop app-side.
- Gravità: alta, blocca la validazione completa app-side.
- Steps to reproduce:
  1. eseguire `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  2. osservare l’errore in `ContentView+Layout+Composition.swift:212`
- Risultato attuale: il file usa `SidebarView(...)`, ma nel repository non esiste alcuna definizione del simbolo.
- Risultato atteso: il target app deve compilare e i test app-side devono poter partire.
- Causa probabile: simbolo rimosso o rinominato in una tranche preesistente senza aggiornare il call site.
- Causa probabile: confermata. Il target app aveva perso `SidebarView` e gli helper di fallback thread collegati (`resolveSidebarThreadDeletionFallback`, `shouldReselectAfterArchivingThread`) ma i call site e i test li referenziavano ancora.
- Scope consentito: target app e composizione UI collegata alla sidebar.
- Non-scope: harness `CoderEngineTests`, business logic review, persistence.
- Moduli confinanti da verificare: `ContentView+Layout+Composition.swift`, eventuali view/sidebar replacement.
- Test da aggiungere o aggiornare: test di compilazione/struttura app-side dopo il ripristino del simbolo corretto.
- Strategia di fix minimo:
  - ripristinare un `SidebarView` compatibile con il call site corrente
  - ripristinare gli helper strettamente necessari ai test/sidebar fallback
  - evitare di reimportare il vecchio sidebar completo se non serve
- Verifica post-fix:
  - il build del target app non fallisce più su `Cannot find 'SidebarView' in scope`
  - il build del target app non fallisce più sui simboli `resolveSidebarThreadDeletionFallback` / `shouldReselectAfterArchivingThread`
  - resta un fallimento generico del run `Solo Code-Debug` non più correlato alla sidebar
- Commit previsto: tranche separata sidebar + test isolation
