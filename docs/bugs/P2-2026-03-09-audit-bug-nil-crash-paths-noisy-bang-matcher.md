# P2 — audit bug_nil_crash_paths rumoroso per matcher `!` generico

## Bug Fix Record
- Categoria: B
- Bug: `bug_nil_crash_paths` segnalava potenziali crash path anche su negazioni booleane o operatori di inequality, a causa di un matcher grezzo su `!`.
- Sintomo: finding rumorosi su righe come `value != nil` o `!flag`.
- Impatto: rumore nell'audit, fiducia ridotta nel motore e rischio di promozione di candidate inutili.
- Gravita': P2
- Steps to reproduce:
  1. Eseguire `audit_bug_nil_crash_paths` su un file con `!=` o `!flag`.
  2. Osservare i finding generati.
- Risultato attuale: il tool poteva segnalare crash path anche senza force unwrap reale.
- Risultato atteso: il tool deve segnalare solo `try!`, `as!`, `first!`, `last!` o veri postfix force unwrap plausibili.
- Causa probabile: uso di pattern matching testuale troppo ampio su `!`.
- Scope consentito: `CodeReviewAuditService+BugAdvanced.swift`, test `CodeReviewAuditAdvancedTests`.
- Non-scope: refactor completo dell'audit subsystem.
- Moduli confinanti da verificare: correlazione audit, candidate verification, summary payload.
- Test da aggiungere o aggiornare: regression test che non flagghi `!=` e `!flag`.
- Strategia di fix minimo: sostituire il matcher `!` grezzo con controlli specifici per force unwrap/cast/force-try.
- Verifica post-fix: build workspace + test audit aggiuntivo sui falsi positivi banali.
- Commit previsto: `fix(audit): reduce nil crash matcher false positives`
