# P1 - Notification tap opened legacy bundle

## Bug Fix Record
- Categoria: A - Critico
- Bug: il click sulle notifiche locali di completamento task poteva riattivare un bundle legacy invece dell'app corrente `Solo Code`
- Sintomo: cliccando una notifica, macOS portava in primo piano un'altra app legacy o un bundle registrato con naming storico
- Impatto: routing errato del tap notifica, UX rotta e rischio di riaprire un bundle non più supportato
- Gravità: alta
- Steps to reproduce:
  1. avere nel sistema artefatti legacy o registrazioni LaunchServices residue
  2. inviare una notifica locale di completamento task
  3. cliccare la notifica dal Notification Center o dal banner
- Risultato attuale: il sistema poteva riattivare il bundle legacy associato alla notifica
- Risultato atteso: il click deve riaprire solo l'app `Solo Code` corrente
- Causa probabile: rename brand e identità bundle non completati; artefatti, risorse, manifest, path persistenti e riferimenti runtime mantenevano ancora naming legacy, lasciando spazio a registrazioni e associazioni ambigue
- Scope consentito:
  - plist bundle e risorse app
  - script release/update
  - path persistenti e namespace runtime
  - test e riferimenti di progetto necessari al rename
- Non-scope:
  - refactor funzionali non legati al rename
  - modifiche di feature non connesse a notifiche/distribuzione
- Moduli confinanti da verificare:
  - bootstrap app e bundle build
  - notifiche task completion
  - update manifest/release packaging
  - runtime paths per debug/tool trace/CLI profiles
- Test da aggiungere o aggiornare:
  - aggiornare test che verificano prompt, pipeline debug e percorsi runtime con il naming `Solo Code`
- Strategia di fix minimo:
  - rimuovere il bundle legacy locale dal package workspace
  - eliminare il naming legacy dal perimetro distribuito e runtime
  - riallineare progetto Xcode, file rinominati e test
- Verifica post-fix:
  - `rg` senza residui legacy fuori da `docs/**`
  - build `Solo Code-Debug`
  - suite mirate app + engine verdi
- Commit previsto: `fix(app): remove legacy bundle identity from app and distribution`
