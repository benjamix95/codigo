# [P2] Il delta dei file editati viene mostrato senza colorazione semantica

## Bug Fix Record
- Categoria: B
- Bug: il diff dei file editati nella timeline chat viene renderizzato come testo uniforme, senza distinguere visivamente righe aggiunte, rimosse e header del patch.
- Sintomo: aprendo una card `Modifica apportata ...`, il delta resta tutto grigio anche se i contatori `+/-` sono corretti.
- Impatto: il delta è difficile da leggere e riduce la fiducia nel preview live dei file editati.
- Gravità: media
- Steps to reproduce:
  1. Aprire una riga `Modifica apportata ...` con diff disponibile.
  2. Espandere la card `Delta modifiche`.
  3. Osservare che tutte le righe hanno lo stesso colore.
- Risultato attuale: nessuna colorazione semantica per aggiunte, rimozioni e hunk.
- Risultato atteso: righe `+` verdi, righe `-` rosse, header/hunk con stile dedicato.
- Causa probabile: la preview usava un singolo `Text(previewText)` monospaced, senza parsing per riga del unified diff.
- Scope consentito: presentazione del diff file-change e helper di parsing/stile righe.
- Non-scope: layout della card, grouping chat, sidebar, terminali.
- Moduli confinanti da verificare: compact preview, expanded preview card, helper `fullPreviewText`.
- Test da aggiungere o aggiornare: regressioni su classificazione righe full/compact.
- Strategia di fix minimo: introdurre un renderer a righe con stile semantico e riusarlo nelle preview compatte ed espanse.
- Verifica post-fix: test unitari mirati su classificazione righe diff.
- Commit previsto: `fix(chat): colorize inline edit diffs`
