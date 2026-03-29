# P1 — Grace lunga dello snapshot su partial message loss reintroduceva chat Codex monolitica

## Bug Fix Record
- Categoria: A
- Bug: la policy `shouldPreserveSnapshotAgainstTransientEmptyStore` usava una grace lunga anche quando lo store non era vuoto ma restituiva meno messaggi del precedente snapshot.
- Sintomo: su Codex la chat poteva continuare a mostrare per molti secondi uno snapshot vecchio e monolitico, anche quando il problema reale non era "store vuoto" ma un aggiornamento parziale o incompleto.
- Impatto: perdita della resa interleaved `text/tool/text` proprio nel path Codex standard stream; Claude risultava spesso indenne perché non usa lo stesso layout/ownership.
- Gravita': P1
- Steps to reproduce:
  1. usare Codex con standard stream e snapshot chat già popolato
  2. far arrivare uno store parziale con meno messaggi dello snapshot ma non completamente vuoto
  3. osservare che lo snapshot vecchio resta visibile troppo a lungo
  4. vedere risposte ancora monolitiche/non interleaved mentre il runtime più fresco non viene mostrato
- Risultato attuale: stessa grace lunga per store vuoto e per riduzione parziale
- Risultato atteso: la grace lunga deve valere solo per store totalmente vuoto; le riduzioni parziali devono decadere rapidamente
- Causa probabile: il fix per il caso `2fa5b8` (store vuoto a ~22s) è stato esteso troppo e ha coperto anche un caso semanticamente diverso
- Scope consentito:
  - `ChatPanelView+PartC_MessageSnapshotPolicy.swift`
  - `ChatPanelMessageSnapshotPolicyTests.swift`
- Non-scope:
  - refactor della timeline
  - modifiche a `ChatStreamingTimelineTurnResolver`
  - cambi ai provider Claude/Gemini
- Moduli confinanti da verificare:
  - refresh snapshot messaggi
  - codex standard stream / linear chat
  - test snapshot policy esistenti
- Test da aggiungere o aggiornare:
  - store vuoto lungo continua a essere preservato
  - partial message loss lungo non deve più essere preservato
- Strategia di fix minimo:
  - grace lunga solo per `freshMessageCount == 0`
  - tornare a finestra breve per riduzioni parziali
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPanelMessageSnapshotPolicyTests`
- Commit previsto: `fix(chat): scope long snapshot grace to empty-store codex path`
