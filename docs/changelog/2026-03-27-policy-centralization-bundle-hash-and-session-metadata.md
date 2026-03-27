# 2026-03-27 — Policy centralization: bundle hash and session metadata

## Cosa cambia

- `InstructionPolicyBundle` espone ora anche `policyRef`, oltre a `policyHash` e `requiredAckMarker`.
- `WorkspaceContext` trasporta il bundle policy gia' risolto e lo riusa per costruire `contextPrompt()`.
- il helper `ToolEnabledLLMProvider.requiredPolicyHash(from:)` legge prima l'hash dal bundle strutturato e usa la regex sul prompt solo come fallback difensivo.
- il pannello chat smette di mantenere una cache locale duplicata del bundle policy e usa direttamente il layer centralizzato del motore.
- il bridge Rust della main chat trasporta metadata di policy session-aware (`policyRef`, `policyHash`, `shouldReinjectPolicyText`) senza cambiare ancora il fallback stateless.

## File toccati

- `Engine/CoderEngine/Sources/Policy/InstructionPolicyBundle.swift`
- `Engine/CoderEngine/Sources/Policy/InstructionPolicyBundle+SkillResolution.swift`
- `Engine/CoderEngine/Sources/Workspace/WorkspaceContext.swift`
- `Engine/CoderEngine/Sources/Workspace/WorkspaceContext+InstructionPolicy.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Helpers/ToolEnabledLLMProvider+PolicyHelpers.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartE_ToolTraceTurn.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/MainChatProviderBridgeModels.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderAdapter.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/ChatPanelView+PartN_RuntimeTransportSelection.swift`
- test Swift e Rust collegati

## Note architetturali

- La source of truth della policy e' adesso il bundle strutturato, non il testo del prompt.
- La session metadata e' stata introdotta in modo non distruttivo: i transport attuali continuano a reiniettare il testo della policy per sicurezza, ma il runtime ha ora un contratto esplicito per distinguere tra `policyRef/hash` e contenuto testuale.
- Questo riduce il drift tra provider, UI trace e futura evoluzione verso una vera sticky session.

## Verifica

- test mirati `CoderEngineTests` per `InstructionPolicyBundle` e `ToolEnabledLLMProviderPolicyAckTests`
- `cargo test --manifest-path "Native/Cargo.toml" session_tests --quiet`
- test mirati `SoloCodeAppTests` per config bridge, provider Rust e `ConversationFlowCoordinator`

## Avanzamento

- tranche 1 completata
- tranche 2 completata come foundation metadata + fallback esplicito
- ottimizzazione vera della reiniezione testo: rimandata a un transport con session persistence verificabile
