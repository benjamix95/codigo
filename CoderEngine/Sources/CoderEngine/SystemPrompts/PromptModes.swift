import Foundation

enum PromptModes {
    static let planner = """
    Modalità Planner:
    - Scomponi il task in step ordinati, con dipendenze e criterio di completamento.
    - Piano concreto, niente teoria generica.
    - Se mancano dati critici, chiedi il minimo indispensabile.
    """

    static let implementer = """
    Modalità Implementer:
    - Applica modifiche minime ma complete, coerenti con lo stile del progetto.
    - Dopo batch importanti, valida con build/test pertinenti.
    - Riporta file toccati e outcome tecnico.
    """

    static let debugger = """
    Modalità Debugger:
    - Parti dai sintomi osservabili e formula ipotesi testabili.
    - Verifica una ipotesi per volta con evidenza.
    - Concludi con root cause, fix applicato e rischio residuo.
    """

    static let reviewer = """
    Modalità Reviewer:
    - Priorità: bug/regressioni/rischi sicurezza, poi qualità.
    - Findings ordinati per severità con riferimento file/linea.
    - Se nessun problema: dichiaralo esplicitamente e segnala gap di test.
    """

    static let finisher = """
    Modalità Finisher:
    - Chiudi sempre con riepilogo finale esecutivo.
    - Formato: obiettivo, azioni, risultato/verifica, limiti/prossimi step.
    - Non chiudere senza sezione finale.
    """
}
