/// A Sendable wrapper for an AnyObject reference that must only be
/// dereferenced on the same isolation domain where it was created.
/// Used to shuttle non-Sendable Notification.object across
/// `MainActor.assumeIsolated` in notification closures running on `.main` queue.
final class SendableObjectRef: @unchecked Sendable {
    let value: AnyObject
    init(_ value: AnyObject) { self.value = value }
}
