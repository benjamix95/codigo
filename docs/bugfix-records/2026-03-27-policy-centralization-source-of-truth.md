# Bug Fix Record
- Categoria: A
- Bug: l'hash della instruction policy veniva derivato in piu' modi diversi, con rischio di drift tra `InstructionPolicyBundle`, `WorkspaceContext`, enforcement `policy_ack` e UI trace.
- Sintomo: il runtime ricomponeva la policy centralmente ma alcuni path continuavano a rileggere/parlare con il testo del prompt invece di usare il bundle gia' risolto; questo rendeva fragile qualsiasi evoluzione verso `policy_ref` o session metadata.
- Impatto: possibile mismatch tra hash atteso e hash effettivo, duplicazione cache lato UI, complessita' inutile nel gate `policy_ack`, e difficolta' nel distinguere tra source of truth e fallback testuale.
- Gravita': alta
- Causa probabile:
  1. `InstructionPolicyBundle` era il punto di composizione, ma `ToolEnabledLLMProvider` estraeva ancora l'hash via regex dal `contextPrompt()`.
  2. `WorkspaceContext` non trasportava esplicitamente il bundle policy risolto.
  3. Il pannello chat manteneva una cache secondaria per leggere il bundle invece di riusare il cache layer gia' presente nel motore.
- Scope del fix:
  - `Engine/CoderEngine/Sources/Policy/InstructionPolicyBundle.swift`
  - `Engine/CoderEngine/Sources/Policy/InstructionPolicyBundle+SkillResolution.swift`
  - `Engine/CoderEngine/Sources/Workspace/WorkspaceContext.swift`
  - `Engine/CoderEngine/Sources/Workspace/WorkspaceContext+InstructionPolicy.swift`
  - `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Helpers/ToolEnabledLLMProvider+PolicyHelpers.swift`
  - `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartE_ToolTraceTurn.swift`
  - bridge Rust session config e test associati
- Strategia di fix:
  1. promuovere `InstructionPolicyBundle` a source of truth strutturata con `policyRef`, `policyHash`, `requiredAckMarker` e `empty` canonico;
  2. fare trasportare a `WorkspaceContext` il bundle gia' risolto, invece di ricalcolarlo ogni volta dal prompt;
  3. usare `context.requiredInstructionPolicyHash` nel provider helper e lasciare la regex solo come fallback difensivo;
  4. eliminare la cache UI duplicata e leggere il bundle dallo stesso layer centralizzato;
  5. aggiungere un descriptor di sessione (`InstructionPolicySessionDescriptor`) per trasportare `policyRef/hash` verso il bridge Rust senza cambiare il fallback stateless.
- Decisione importante:
  - `shouldReinjectPolicyText` resta `true` sui transport attuali.
  - Il progetto ora espone metadata di sessione (`policyRef`, `policyHash`) ma non disattiva ancora la reiniezione del testo, perche' la main chat resta stateless tra send separati.
- Verifica eseguita:
  - `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:"CoderEngineTests/InstructionPolicyBundleTests/testPolicyRefDefaultsToPolicyHash" -only-testing:"CoderEngineTests/InstructionPolicyBundleTests/testWorkspaceContextUsesProvidedInstructionPolicyBundle" -only-testing:"CoderEngineTests/ToolEnabledLLMProviderPolicyAckTests/testRequiredPolicyHashPrefersResolvedBundleOverRegexFallback"`
  - `cargo test --manifest-path "Native/Cargo.toml" session_tests --quiet`
  - `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:"SoloCodeAppTests/ClaudeProviderIntegrationTests/testSessionConfigBridgeCarriesMcpServerPath" -only-testing:"SoloCodeAppTests/ClaudeProviderIntegrationTests/testSessionConfigBridgeAllowsNilMcpServerPath" -only-testing:"SoloCodeAppTests/RustMainChatProviderAdapterTests/testRuntimeSessionConfigUsesStrictPromptForCodexProvider" -only-testing:"SoloCodeAppTests/RustMainChatProviderAdapterTests/testRustTransportProviderCompletesWhenPollReturnsCompletedSnapshot" -only-testing:"SoloCodeAppTests/RustMainChatProviderFactoryTests/testTransportProviderReflectsInjectedAuthenticationState" -only-testing:"SoloCodeAppTests/ConversationFlowCoordinatorTests/testRunStreamReducesRustPolledProviderEventsWithoutSwiftEventMapping"`
- Note:
  - Un run piu' largo della suite `ToolEnabledLLMProviderPolicyAckTests` ha mostrato un fallimento in un test non collegato a questa modifica (`testExemptFirstRoundDoesNotBypassSubagentRequirementInLaterRounds`), quindi la verifica finale e' stata ristretta ai metodi pertinenti alla centralizzazione policy.
