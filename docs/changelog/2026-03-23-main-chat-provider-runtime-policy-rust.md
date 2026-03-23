# 2026-03-23 — Main chat provider/runtime policy moved further to Rust

## Cosa cambia

- il provider read-only del plan flow non decide più localmente backend e policy di accesso: Swift usa la `runtime transport resolution` del core Rust e applica solo la config risultante;
- la `thread/provider selection` della main chat passa al core Rust lo stato di autenticazione reale del registry, invece di marcare tutti i provider come autenticati lato Swift;
- il fallback legacy read-only plan resta disponibile solo quando la `runtime transport resolution` Rust non è disponibile.

## File toccati

- `App/SoloCodeApp/Sources/Chat/Support/Providers/Runtime/ChatPanelView+PartN_RuntimeProvider.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderFactory.swift`
- `Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift`
- `Tests/SoloCodeAppTests/ThreadProviderSelectionServiceTests.swift`

## Ownership

- la policy `plan read-only` del dominio main chat è ora guidata dal core Rust anche quando Swift deve ancora costruire un `LLMProvider` host-side;
- la selezione provider/thread nel core Rust riceve dati di autenticazione veri, non placeholder host-side;
- restano ancora host-side le sorgenti dei dati sensibili e operativi: keychain, env/path, CLI account snapshot shaping e provider object construction.

## Verifica

- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/ThreadProviderSelectionServiceTests`

## Avanzamento piano

- tranche 1 completata
- tranche 2 completata
- tranche 3 completata
- tranche 4 avviata e parzialmente assorbita
- avanzamento complessivo: `70%`
