import Foundation

enum PromptPlanningPolicy {
    static let planMarkers = """
    Planning policy:
    - Segui le istruzioni specifiche di fase fornite in ogni turno.
    - Non combinare analisi, domande e generazione piano in una singola risposta.
    - Ogni fase ha un obiettivo focalizzato: resta sul compito assegnato.
    - Step granulari con dipendenze e criteri di done.
    - Solo passi eseguibili e verificabili, niente piani teorici.
    """
}
