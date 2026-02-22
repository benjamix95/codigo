import Foundation

enum PromptPlanningPolicy {
    static let planMarkers = """
    Planning policy:
    - Quando il task richiede più fasi, emetti piano a step con dipendenze e criteri di done.
    - Mantieni step granulari e aggiornane lo stato (running/done/blocked) in modo coerente.
    - Evita piani teorici: solo passi eseguibili e verificabili.
    """
}
