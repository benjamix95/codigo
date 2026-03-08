import XCTest
@testable import CoderIDE

final class EventNormalizerWebTests: XCTestCase {

    // MARK: - Helpers

    private func normalize(_ type: String, payload: [String: String] = [:]) -> [NormalizedEvent] {
        EventNormalizer.normalize(type: type, payload: payload)
    }

    private func envelope(_ type: String, payload: [String: String] = [:]) -> NormalizedEventEnvelope {
        EventNormalizer.normalizeEnvelope(sourceProvider: "test", type: type, payload: payload)
    }

    private func firstActivity(_ events: [NormalizedEvent]) -> TaskActivity? {
        for event in events {
            if case .taskActivity(let activity) = event { return activity }
        }
        return nil
    }

    // MARK: - Web Search Event Normalization

    func testWebSearchStartedEvent() {
        let events = normalize("web_search", payload: ["status": "started", "query": "swift concurrency"])
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, "web_search_started")
        XCTAssertTrue(activity?.isRunning ?? false, "web_search_started should be running")
    }

    func testWebSearchCompletedEvent() {
        let events = normalize("web_search", payload: ["status": "completed", "query": "swift concurrency", "resultCount": "5"])
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, "web_search_completed")
        XCTAssertFalse(activity?.isRunning ?? true, "web_search_completed should not be running")
    }

    func testWebSearchFailedEvent() {
        let events = normalize("web_search", payload: ["status": "failed", "error": "timeout"])
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, "web_search_failed")
        XCTAssertFalse(activity?.isRunning ?? true, "web_search_failed should not be running")
    }

    func testWebSearchDirectStartedType() {
        let events = normalize("web_search_started", payload: ["query": "test"])
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, "web_search_started")
        XCTAssertTrue(activity?.isRunning ?? false)
    }

    func testWebSearchDirectCompletedType() {
        let events = normalize("web_search_completed", payload: ["query": "test"])
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, "web_search_completed")
        XCTAssertFalse(activity?.isRunning ?? true)
    }

    func testWebSearchDirectFailedType() {
        let events = normalize("web_search_failed", payload: ["query": "test"])
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, "web_search_failed")
        XCTAssertFalse(activity?.isRunning ?? true)
    }

    // MARK: - Web Fetch Event Normalization

    func testWebFetchStartedEvent() {
        let events = normalize("web_fetch", payload: ["status": "started", "url": "https://example.com"])
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, "web_fetch_started")
        XCTAssertTrue(activity?.isRunning ?? false, "web_fetch_started should be running")
    }

    func testWebFetchCompletedEvent() {
        let events = normalize("web_fetch", payload: ["status": "completed", "url": "https://example.com", "detail": "4500 chars"])
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, "web_fetch_completed")
        XCTAssertFalse(activity?.isRunning ?? true, "web_fetch_completed should not be running")
    }

    func testWebFetchFailedEvent() {
        let events = normalize("web_fetch", payload: ["status": "failed", "error": "HTTP 404"])
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, "web_fetch_failed")
        XCTAssertFalse(activity?.isRunning ?? true, "web_fetch_failed should not be running")
    }

    func testWebFetchDirectStartedType() {
        let events = normalize("web_fetch_started", payload: ["url": "https://example.com"])
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, "web_fetch_started")
        XCTAssertTrue(activity?.isRunning ?? false)
    }

    func testWebFetchDirectCompletedType() {
        let events = normalize("web_fetch_completed", payload: ["url": "https://example.com"])
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, "web_fetch_completed")
        XCTAssertFalse(activity?.isRunning ?? true)
    }

    func testWebFetchDirectFailedType() {
        let events = normalize("web_fetch_failed", payload: ["url": "https://example.com"])
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.type, "web_fetch_failed")
        XCTAssertFalse(activity?.isRunning ?? true)
    }

    // MARK: - Phase Mapping

    func testWebSearchPhaseIsSearching() {
        let events = normalize("web_search_started", payload: ["query": "test"])
        let activity = firstActivity(events)
        XCTAssertEqual(activity?.phase, .searching)
    }

    func testWebFetchPhaseIsSearching() {
        let events = normalize("web_fetch_started", payload: ["url": "https://example.com"])
        let activity = firstActivity(events)
        XCTAssertEqual(activity?.phase, .searching)
    }

    func testWebSearchCompletedPhaseIsSearching() {
        let events = normalize("web_search_completed", payload: ["query": "test"])
        let activity = firstActivity(events)
        XCTAssertEqual(activity?.phase, .searching)
    }

    func testWebFetchCompletedPhaseIsSearching() {
        let events = normalize("web_fetch_completed", payload: ["url": "https://example.com"])
        let activity = firstActivity(events)
        XCTAssertEqual(activity?.phase, .searching)
    }

    // MARK: - Default Titles

    func testWebSearchDefaultTitles() {
        let startedActivity = firstActivity(normalize("web_search_started", payload: [:]))
        XCTAssertEqual(startedActivity?.title, "Web search started")

        let completedActivity = firstActivity(normalize("web_search_completed", payload: [:]))
        XCTAssertEqual(completedActivity?.title, "Web search completed")

        let failedActivity = firstActivity(normalize("web_search_failed", payload: [:]))
        XCTAssertEqual(failedActivity?.title, "Web search failed")
    }

    func testWebFetchDefaultTitles() {
        let startedActivity = firstActivity(normalize("web_fetch_started", payload: [:]))
        XCTAssertEqual(startedActivity?.title, "Fetching web page")

        let completedActivity = firstActivity(normalize("web_fetch_completed", payload: [:]))
        XCTAssertEqual(completedActivity?.title, "Web page fetched")

        let failedActivity = firstActivity(normalize("web_fetch_failed", payload: [:]))
        XCTAssertEqual(failedActivity?.title, "Web fetch failed")
    }

    // MARK: - Envelope Kind

    func testWebSearchEnvelopeKind() {
        let env = envelope("web_search", payload: ["status": "started", "query": "test"])
        XCTAssertEqual(env.kind, .instantGrep, "Web search events should use .instantGrep kind")
    }

    func testWebFetchEnvelopeKind() {
        let env = envelope("web_fetch", payload: ["status": "started", "url": "https://example.com"])
        XCTAssertEqual(env.kind, .instantGrep, "Web fetch events should use .instantGrep kind")
    }

    func testWebSearchStartedEnvelopeKind() {
        let env = envelope("web_search_started", payload: ["query": "test"])
        XCTAssertEqual(env.kind, .instantGrep)
    }

    func testWebFetchCompletedEnvelopeKind() {
        let env = envelope("web_fetch_completed", payload: ["url": "https://example.com"])
        XCTAssertEqual(env.kind, .instantGrep)
    }

    // MARK: - Custom Titles from Payload

    func testWebSearchUsesQueryAsTitle() {
        let events = normalize("web_search_started", payload: ["title": "Searching: swift actors", "query": "swift actors"])
        let activity = firstActivity(events)
        XCTAssertEqual(activity?.title, "Searching: swift actors")
    }

    func testWebFetchUsesURLInTitle() {
        let events = normalize("web_fetch_started", payload: ["title": "Fetching: https://docs.swift.org", "url": "https://docs.swift.org"])
        let activity = firstActivity(events)
        XCTAssertEqual(activity?.title, "Fetching: https://docs.swift.org")
    }

    // MARK: - Payload Passthrough

    func testPayloadIsPreservedInActivity() {
        let payload = ["query": "swift concurrency", "resultCount": "10", "status": "completed"]
        let events = normalize("web_search", payload: payload)
        let activity = firstActivity(events)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.payload["query"], "swift concurrency")
        XCTAssertEqual(activity?.payload["resultCount"], "10")
    }
}
