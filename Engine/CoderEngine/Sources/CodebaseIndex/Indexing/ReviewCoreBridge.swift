import Foundation

public enum ReviewCoreBridge {
    public static func loadedVersion() -> String? {
        RustSearchFFIClient.shared.loadedReviewCoreVersion()
    }

    public static func loadedState() -> ReviewCoreLoadedState {
        RustSearchFFIClient.shared.reviewCoreLoadedState()
    }

    public static func call<Request: Encodable, Response: Decodable>(
        functionName: String,
        request: Request
    ) -> Response? {
        guard isEnabled else { return nil }
        do {
            let payload = try JSONEncoder().encode(request)
            return try RustSearchFFIClient.shared.callReviewFunction(functionName, payloadData: payload)
        } catch {
            return nil
        }
    }

    public static var isEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        let forceSwift = env["SOLOCODE_REVIEW_CORE_FORCE_SWIFT"] == "1"
            || env["SOLOCODE_REVIEW_CORE_DISABLE_RUST"] == "1"
        return !forceSwift
            && !shouldDeferRustReviewCoreBootstrap(environment: env)
            && loadedVersion() != nil
    }

    public static func userFacingDisabledReason() -> String {
        if isEnabled {
            return ""
        }
        let env = ProcessInfo.processInfo.environment
        if env["SOLOCODE_REVIEW_CORE_FORCE_SWIFT"] == "1"
            || env["SOLOCODE_REVIEW_CORE_DISABLE_RUST"] == "1" {
            return "Review Core disabilitato da variabile d’ambiente (SOLOCODE_REVIEW_CORE_FORCE_SWIFT / DISABLE_RUST). Rimuovi la flag e riavvia l’app."
        }
        if shouldDeferRustReviewCoreBootstrap(environment: env) {
            return "Review Core non caricato in questo processo (es. test XCTest o bootstrap differito). Apri l’app normalmente o imposta SOLOCODE_REVIEW_CORE_LIBRARY_PATH."
        }
        let state = loadedState()
        if let reason = state.failureReason, !reason.isEmpty {
            return "Libreria Review Core non caricata: \(reason). Esegui una build completa dell’app (script Rust) o verifica il bundle."
        }
        return "Review Core Rust non disponibile: simbolo review_core_version assente. Ricompila il target con lo step “Build Rust Review Core”."
    }

    public static func resetForTests() {
        RustSearchFFIClient.shared.resetForTests()
    }
}
