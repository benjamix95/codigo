import SwiftUI

private enum ConversationBootstrapIfNeededKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Imposta `selectedConversationId` se è ancora nil (stesso comportamento di `configureInitialConversationSelection`).
    /// Usato dal pannello chat per anticipare il bootstrap rispetto all’`onAppear` del root `ContentView`, riducendo sfarfallii allo startup.
    var conversationBootstrapIfNeeded: () -> Void {
        get { self[ConversationBootstrapIfNeededKey.self] }
        set { self[ConversationBootstrapIfNeededKey.self] = newValue }
    }
}
