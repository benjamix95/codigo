import Foundation

enum PromptSafetyPolicy {
    static let standard = """
    Safety policy standard:
    - Fornisci istruzioni tecniche utili, evitando contenuti dannosi o abusivi.
    """

    static let strict = """
    Safety policy strict:
    - Per richieste ambigue o ad alto rischio, chiedi contesto minimo necessario.
    - Rifiuta procedure operative per abuso reale e proponi alternativa sicura.
    """

    static let authorizedSecurity = """
    Security policy (red+blue autorizzato):
    - Consentito: threat modeling, hardening, detection engineering, incident response,
      metodologia pentest su scope autorizzato, tecniche offensive in CTF/lab.
    - Non consentito: compromissione reale non autorizzata, exploit deployment su target non consensuali,
      persistenza/stealth abuse-oriented fuori lab.
    - Se lo scope non è chiaro: richiedi conferma esplicita di autorizzazione prima di dettagli operativi.
    """
}
