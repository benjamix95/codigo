import Foundation
import UserNotifications

enum TaskCompletionNotificationAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown
}

protocol UserNotificationCenterAdapter {
    func authorizationStatus() async -> TaskCompletionNotificationAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

final class DisabledUserNotificationCenterAdapter: UserNotificationCenterAdapter {
    func authorizationStatus() async -> TaskCompletionNotificationAuthorizationStatus {
        .denied
    }

    func requestAuthorization(options _: UNAuthorizationOptions) async -> Bool {
        false
    }

    func add(_ request: UNNotificationRequest) async throws {}
}

final class UNUserNotificationCenterAdapter: UserNotificationCenterAdapter {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> TaskCompletionNotificationAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: Self.map(settings.authorizationStatus))
            }
        }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: options) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func map(_ status: UNAuthorizationStatus) -> TaskCompletionNotificationAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .unknown
        }
    }
}

actor TaskCompletionNotificationService {
    static let shared = TaskCompletionNotificationService()

    private let centerAdapter: any UserNotificationCenterAdapter
    private var deliveredAssistantMessageIds: Set<UUID> = []

    init(centerAdapter: (any UserNotificationCenterAdapter)? = nil) {
        self.centerAdapter = centerAdapter ?? Self.makeDefaultCenterAdapter()
    }

    func deliver(payload: TaskCompletionNotificationPayload) async {
        guard !deliveredAssistantMessageIds.contains(payload.assistantMessageId) else { return }
        guard await canDeliverNotification() else { return }

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.requestIdentifier(for: payload.assistantMessageId),
            content: content,
            trigger: nil
        )

        do {
            try await centerAdapter.add(request)
            deliveredAssistantMessageIds.insert(payload.assistantMessageId)
        } catch {
            NSLog(
                "[TaskCompletionNotificationService] delivery failed for assistant %@: %@",
                payload.assistantMessageId.uuidString,
                error.localizedDescription
            )
        }
    }

    func hasDelivered(assistantMessageId: UUID) -> Bool {
        deliveredAssistantMessageIds.contains(assistantMessageId)
    }

    static func requestIdentifier(for assistantMessageId: UUID) -> String {
        "coderide.task-completion.\(assistantMessageId.uuidString)"
    }

    private static func makeDefaultCenterAdapter() -> any UserNotificationCenterAdapter {
        guard isUserNotificationEnvironmentSupported() else {
            NSLog("[TaskCompletionNotificationService] notifications disabled: invalid app bundle metadata")
            return DisabledUserNotificationCenterAdapter()
        }
        return UNUserNotificationCenterAdapter()
    }

    private static func isUserNotificationEnvironmentSupported() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty
        else {
            return false
        }
        return Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    private func canDeliverNotification() async -> Bool {
        let status = await centerAdapter.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await centerAdapter.requestAuthorization(options: [.alert, .sound, .badge])
        case .denied, .unknown:
            return false
        }
    }
}
