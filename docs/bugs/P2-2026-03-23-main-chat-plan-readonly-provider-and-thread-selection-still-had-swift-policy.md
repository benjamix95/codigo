# Bug Fix Record
- Categoria: B
- Bug: una parte della policy provider/runtime della main chat era ancora posseduta da Swift, in particolare il provider read-only del plan flow e la thread/provider selection con autenticazione del registry.
- Sintomo:
  - `resolveReadOnlyPlanRuntimeProvider()` decideva localmente backend, sandbox e tool policy read-only;
  - `ThreadProviderSelectionService` passava al core Rust registry entries con `isAuthenticated = true` per tutti i provider.
- Impatto: il core Rust decideva già gran parte della transport policy, ma Swift continuava a pre-filtrare il path effettivo con regole locali o dati di autenticazione falsati.
- Gravità: media
- Steps to reproduce:
  1. Ispezionare `ChatPanelView+PartN_RuntimeProvider.swift` e verificare la costruzione locale del provider read-only per `Plan`.
  2. Ispezionare `RustMainChatProviderFactory.swift` e verificare che `registryEntries` marchi ogni provider come autenticato.
  3. Eseguire i test di provider/runtime factory e thread selection.
- Risultato attuale: la policy main chat provider/runtime era ancora ibrida fra core Rust e binding Swift.
- Risultato atteso: Swift deve costruire provider host-side solo dopo avere ricevuto dal core Rust la risoluzione read-only/transport e deve passare al core lo stato di autenticazione reale del registry.
- Causa probabile: il cutover Rust del dominio provider/runtime era arrivato alla transport resolution, ma non aveva ancora drenato del tutto la policy residua lato host.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/Providers/Runtime/ChatPanelView+PartN_RuntimeProvider.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderFactory.swift`
  - test app-side di provider factory/thread selection
- Non-scope:
  - `ToolEnabledLLMProvider`
  - `UnifiedToolRuntime`
  - provider object construction generica
  - secret storage / keychain / env host-side
- Moduli confinanti da verificare:
  - `RustMainChatProviderFactoryTests`
  - `ThreadProviderSelectionServiceTests`
- Test da aggiungere o aggiornare:
  - regression sulla risoluzione read-only del plan provider guidata dal response Rust
  - regression su fallback thread selection con provider non autenticati nel registry
- Strategia di fix minimo:
  - usare `MainChatRustTransportSupport.resolveTransportConfig(...)` anche per costruire il provider read-only del plan flow
  - passare a `ThreadProviderSelectionService` lo stato di autenticazione reale del registry
  - mantenere fallback legacy solo quando il bridge Rust non è disponibile
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/ThreadProviderSelectionServiceTests`
- Commit previsto: `refactor(chat): move plan readonly provider policy toward rust`
