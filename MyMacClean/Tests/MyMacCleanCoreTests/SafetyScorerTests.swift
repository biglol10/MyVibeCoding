import XCTest
@testable import MyMacCleanCore

final class SafetyScorerTests: XCTestCase {
    func testBundleIdentifierEvidenceInKnownCleanupRootIsSafeAndDefaultSelected() {
        let evidence = MatchEvidence(
            type: .bundleIdentifier,
            matchedValue: "com.example.app",
            sourcePath: "/Users/me/Library/Caches/com.example.app",
            strength: .strong
        )

        let score = SafetyScorer().score(
            evidence: [evidence],
            kind: .cache,
            isProtected: false,
            isKnownCleanupRoot: true
        )

        XCTAssertEqual(score.level, .safe)
        XCTAssertTrue(score.defaultSelected)
        XCTAssertFalse(score.requiresManualReview)
    }

    func testExactNameEvidenceInKnownCleanupRootRequiresReviewButCanBeDefaultSelected() {
        let evidence = MatchEvidence(
            type: .exactAppName,
            matchedValue: "Figma",
            sourcePath: "/Users/me/Library/Application Support/Figma",
            strength: .medium
        )

        let score = SafetyScorer().score(
            evidence: [evidence],
            kind: .applicationSupport,
            isProtected: false,
            isKnownCleanupRoot: true
        )

        XCTAssertEqual(score.level, .review)
        XCTAssertTrue(score.defaultSelected)
        XCTAssertTrue(score.requiresManualReview)
    }

    func testWeakEvidenceIsRiskyAndNeverDefaultSelected() {
        let evidence = MatchEvidence(
            type: .weakName,
            matchedValue: "cursor",
            sourcePath: "/Users/me/Library/Caches/Yarn/v6/npm-cli-cursor",
            strength: .weak
        )

        let score = SafetyScorer().score(
            evidence: [evidence],
            kind: .unknown,
            isProtected: false,
            isKnownCleanupRoot: false
        )

        XCTAssertEqual(score.level, .risky)
        XCTAssertFalse(score.defaultSelected)
        XCTAssertTrue(score.requiresManualReview)
    }

    func testProtectedPathIsRiskyAndNeverDefaultSelected() {
        let evidence = MatchEvidence(
            type: .bundleIdentifier,
            matchedValue: "com.example.app",
            sourcePath: "/Library/LaunchDaemons/com.example.app.plist",
            strength: .strong
        )

        let score = SafetyScorer().score(
            evidence: [evidence],
            kind: .launchDaemon,
            isProtected: true,
            isKnownCleanupRoot: true
        )

        XCTAssertEqual(score.level, .risky)
        XCTAssertFalse(score.defaultSelected)
        XCTAssertTrue(score.requiresManualReview)
    }
}
