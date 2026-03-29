# [P2] Le card file-edit mostrano già il delta anche da collassate

## Bug Fix Record
- Categoria: B
- Bug: nella timeline chat, le righe `Modifica apportata ...` mostrano il delta direttamente sotto l'header anche quando la card non è espansa.
- Sintomo: compaiono righe rosse/verdi sotto il titolo file-change prima dell'espansione manuale.
- Impatto: la chat perde densità e l'interazione expand/collapse diventa incoerente.
- Gravità: media
- Steps to reproduce:
  1. Aprire una conversazione con file editati e diff disponibile.
  2. Lasciare la riga file-edit collassata.
  3. Osservare che il delta è già visibile.
- Risultato attuale: la riga collassata mostra già il preview del diff.
- Risultato atteso: il delta deve comparire solo dopo espansione manuale della card.
- Causa probabile: la row inline dei file editati renderizzava sempre il compact preview nel ramo `else`, anche in stato collassato.
- Scope consentito: policy preview delle row file-edit nella timeline chat.
- Non-scope: TODO cards, renderer del diff espanso, terminali, sidebar.
- Moduli confinanti da verificare: row file-edit inline, policy di preview, test di regressione.
- Test da aggiungere o aggiornare: test sulla policy che impone `expandedOnly`.
- Strategia di fix minimo: separare la policy della row inline e nascondere il compact preview nella card collassata.
- Verifica post-fix: test unitari mirati sulla policy.
- Commit previsto: `fix(chat): hide collapsed inline edit diffs`
