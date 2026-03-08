import XCTest
@testable import CoderEngine

final class ContextWeightProfileTests: XCTestCase {

    // MARK: - Default Profiles

    func testDefaultProfiles_coverAllTaskTypes() {
        for taskType in TaskType.allCases {
            let w = ContextWeightProfile.defaultProfiles[taskType]
            XCTAssertNotNil(w, "\(taskType) should have default weights")
        }
    }

    func testDefaultProfiles_areNormalized() {
        for (taskType, weights) in ContextWeightProfile.defaultProfiles {
            XCTAssertTrue(
                weights.isNormalized,
                "\(taskType) weights should sum to 1.0"
            )
        }
    }

    func testFeatureProfile_correctValues() {
        guard let w = ContextWeightProfile.defaultProfiles[.feature] else {
            XCTFail("Missing profile for .feature")
            return
        }
        XCTAssertEqual(w.semantic, 0.40, accuracy: 0.001)
        XCTAssertEqual(w.callGraph, 0.25, accuracy: 0.001)
        XCTAssertEqual(w.dependency, 0.25, accuracy: 0.001)
        XCTAssertEqual(w.recency, 0.10, accuracy: 0.001)
    }

    func testBugfixProfile_correctValues() {
        guard let w = ContextWeightProfile.defaultProfiles[.bugfix] else {
            XCTFail("Missing profile for .bugfix")
            return
        }
        XCTAssertEqual(w.semantic, 0.20, accuracy: 0.001)
        XCTAssertEqual(w.callGraph, 0.40, accuracy: 0.001)
        XCTAssertEqual(w.dependency, 0.15, accuracy: 0.001)
        XCTAssertEqual(w.recency, 0.25, accuracy: 0.001)
    }

    func testDocsProfile_semanticDominant() {
        guard let w = ContextWeightProfile.defaultProfiles[.docs] else {
            XCTFail("Missing profile for .docs")
            return
        }
        XCTAssertEqual(w.semantic, 0.50, accuracy: 0.001)
    }

    // MARK: - ContextWeightProfile

    func testWeights_returnDefaultForKnownType() {
        let profile = ContextWeightProfile()
        let w = profile.weights(for: .refactor)
        XCTAssertEqual(w.semantic, 0.30, accuracy: 0.001)
    }

    func testSetWeights_overridesProfile() {
        var profile = ContextWeightProfile()
        let custom = ContextWeights(
            semantic: 0.1, callGraph: 0.2,
            dependency: 0.3, recency: 0.4
        )
        profile.setWeights(custom, for: .feature)
        let w = profile.weights(for: .feature)
        XCTAssertEqual(w.semantic, 0.1, accuracy: 0.001)
        XCTAssertEqual(w.recency, 0.4, accuracy: 0.001)
    }

    // MARK: - ContextWeights

    func testIsNormalized_true() {
        let w = ContextWeights(
            semantic: 0.25, callGraph: 0.25,
            dependency: 0.25, recency: 0.25
        )
        XCTAssertTrue(w.isNormalized)
    }

    func testIsNormalized_false() {
        let w = ContextWeights(
            semantic: 0.5, callGraph: 0.5,
            dependency: 0.5, recency: 0.5
        )
        XCTAssertFalse(w.isNormalized)
    }

    func testNormalize_fixesSum() {
        var w = ContextWeights(
            semantic: 2, callGraph: 2,
            dependency: 2, recency: 2
        )
        w.normalize()
        XCTAssertTrue(w.isNormalized)
        XCTAssertEqual(w.semantic, 0.25, accuracy: 0.001)
    }

    // MARK: - Codable

    func testContextWeights_roundTrip() throws {
        let w = ContextWeights(
            semantic: 0.40, callGraph: 0.25,
            dependency: 0.25, recency: 0.10
        )
        let data = try JSONEncoder().encode(w)
        let decoded = try JSONDecoder().decode(
            ContextWeights.self, from: data
        )
        XCTAssertEqual(w, decoded)
    }
}
