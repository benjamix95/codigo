import UserNotifications
import XCTest
@testable import CoderIDE

final class TaskCompletionNotificationServiceTests: XCTestCase {
    func testDeliverRequestsAuthorizationWhenStatusIsNotDetermined() async {
        let adapter = MockUserNotificationCenterAdapter(
            status: .notDetermined,
            requestAuthorizationResult: true
        )
        let service = TaskCompletionNotificationService(centerAdapter: adapter)

        await service.deliver(payload: samplePayload())

        XCTAssertEqual(adapter.requestAuthorizationCallCount, 1)
        XCTAssertEqual(adapter.addCallCount, 1)
    }

    func testDeliverSkipsWhenAuthorizationDeniedAfterRequest() async {
        let adapter = MockUserNotificationCenterAdapter(
            status: .notDetermined,
            requestAuthorizationResult: false
        )
        let service = TaskCompletionNotificationService(centerAdapter: adapter)

        await service.deliver(payload: samplePayload())

        XCTAssertEqual(adapter.requestAuthorizationCallCount, 1)
        XCTAssertEqual(adapter.addCallCount, 0)
    }

    func testDeliverSendsWhenAuthorizedOrProvisional() async {
        let authorizedAdapter = MockUserNotificationCenterAdapter(status: .authorized)
        let provisionalAdapter = MockUserNotificationCenterAdapter(status: .provisional)
        let authorizedService = TaskCompletionNotificationService(centerAdapter: authorizedAdapter)
        let provisionalService = TaskCompletionNotificationService(centerAdapter: provisionalAdapter)

        await authorizedService.deliver(payload: samplePayload())
        await provisionalService.deliver(payload: samplePayload(assistantMessageId: UUID()))

        XCTAssertEqual(authorizedAdapter.addCallCount, 1)
        XCTAssertEqual(provisionalAdapter.addCallCount, 1)
    }

    func testDeliverSkipsWhenAuthorizationIsDenied() async {
        let adapter = MockUserNotificationCenterAdapter(status: .denied)
        let service = TaskCompletionNotificationService(centerAdapter: adapter)

        await service.deliver(payload: samplePayload())

        XCTAssertEqual(adapter.requestAuthorizationCallCount, 0)
        XCTAssertEqual(adapter.addCallCount, 0)
    }

    func testDeliverDeduplicatesByAssistantMessageId() async {
        let assistantMessageId = UUID()
        let adapter = MockUserNotificationCenterAdapter(status: .authorized)
        let service = TaskCompletionNotificationService(centerAdapter: adapter)
        let payload = samplePayload(assistantMessageId: assistantMessageId)

        await service.deliver(payload: payload)
        await service.deliver(payload: payload)

        XCTAssertEqual(adapter.addCallCount, 1)
        XCTAssertEqual(adapter.lastRequestIdentifier, TaskCompletionNotificationService.requestIdentifier(for: assistantMessageId))
        XCTAssertEqual(adapter.lastRequestTitle, payload.title)
        XCTAssertEqual(adapter.lastRequestBody, payload.body)
    }

    private func samplePayload(assistantMessageId: UUID = UUID()) -> TaskCompletionNotificationPayload {
        TaskCompletionNotificationPayload(
            conversationId: UUID(),
            assistantMessageId: assistantMessageId,
            title: "Domanda utente",
            body: "Risposta finale"
        )
    }
}

private final class MockUserNotificationCenterAdapter: UserNotificationCenterAdapter {
    var status: TaskCompletionNotificationAuthorizationStatus
    var requestAuthorizationResult: Bool
    var requestAuthorizationCallCount = 0
    var addCallCount = 0
    var lastRequestIdentifier: String?
    var lastRequestTitle: String?
    var lastRequestBody: String?

    init(
        status: TaskCompletionNotificationAuthorizationStatus,
        requestAuthorizationResult: Bool = true
    ) {
        self.status = status
        self.requestAuthorizationResult = requestAuthorizationResult
    }

    func authorizationStatus() async -> TaskCompletionNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization(options _: UNAuthorizationOptions) async -> Bool {
        requestAuthorizationCallCount += 1
        return requestAuthorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        addCallCount += 1
        lastRequestIdentifier = request.identifier
        lastRequestTitle = request.content.title
        lastRequestBody = request.content.body
    }
}
