import Foundation

enum PromptOutputStyles {
    static let concise = """
    Stile output concise:
    - Risposte brevi e operative.
    - Evidenzia solo decisioni e risultati essenziali.
    """

    static let normal = """
    Stile output normal:
    - Struttura chiara con contesto minimo necessario.
    - Include evidenza tecnica quando utile.
    """

    static let audit = """
    Stile output audit:
    - Dettaglio alto, con rationale, verifiche e rischi residui.
    - Adatto a review e incidenti.
    """

    static let executionLog = """
    Stile output execution_log:
    - Sequenza cronologica: azione, evidenza, outcome.
    """

    static let handoff = """
    Stile output handoff:
    - Conclusione pronta per passaggio a un altro engineer.
    - Includi stato attuale, blocchi e next actions.
    """
}
