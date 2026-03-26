import Foundation

extension Notification.Name {
    /// Published when the pipeline debug event buffer prunes events (includes `conversationId` and `dropped` in userInfo).
    static let soloCodeDebugEventBufferDropped = Notification.Name("SoloCodeDebugEventBufferDropped")
}

enum DebugPipelineBufferNotificationUserInfoKey {
    static let conversationId = "conversationId"
    static let dropped = "dropped"
}
