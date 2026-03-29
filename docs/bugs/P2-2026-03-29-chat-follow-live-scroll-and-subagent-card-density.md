# [P2] Chat follow-live non si sgancia allo scroll manuale e card subagent troppo alte

## Bug Fix Record
- Categoria: B
- Bug: la chat principale continua ad auto-scrollare verso il fondo anche quando l'utente prova a risalire manualmente; inoltre le card subagent occupano più altezza del necessario in stato compatto.
- Sintomo: appena l'utente scrolla verso l'alto durante una run, la viewport torna subito giù. Le card subagent mostrano header, task prompt e preview con troppo spazio verticale.
- Impatto: lettura della history quasi impossibile durante un task live; densità della timeline peggiorata e minore spazio utile.
- Gravità: media
- Steps to reproduce:
  1. Avviare un task con output streaming nella chat principale.
  2. Scorrere manualmente verso l'alto mentre arrivano nuovi eventi.
  3. Osservare che la chat torna subito in basso.
  4. Osservare le card subagent nella timeline: l'altezza compatta è superiore al necessario.
- Risultato attuale: follow-live sempre attivo anche quando l'utente si allontana dal fondo; card subagent poco compatte.
- Risultato atteso: se l'utente non è più vicino al fondo, il follow-live si sospende finché non torna vicino al fondo; card subagent più basse a parità di layout.
- Causa probabile: la chat usava solo il flag `isFollowingLive` senza osservare la posizione reale dello `NSScrollView`; le card subagent avevano padding e preview compatti troppo generosi.
- Scope consentito: observer viewport della chat, policy follow-live, metriche di presentazione card subagent.
- Non-scope: layout complessivo della chat, sidebar, composer, tool trace.
- Moduli confinanti da verificare: refresh modifiers della messages area, schedule auto-scroll, card subagent live e snapshot.
- Test da aggiungere o aggiornare: regressioni su policy follow-live e helper di compact preview subagent.
- Strategia di fix minimo: aggiungere un observer del viewport dello scroll per sganciare/riagganciare il follow-live; compattare solo padding e limiti preview delle card subagent.
- Verifica post-fix: test unitari mirati e smoke test della suite chat/swarm.
- Commit previsto: `fix(chat): pause follow-live on manual scroll`
