# MyMacClean Deletion Trust Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Milestone 1 from the trust-and-app-management spec: safety scores, structured match evidence, post-delete verification reports, persistent deletion receipts, a working Delete History screen, and Orphan Files Finder.

**Architecture:** Keep filesystem logic in `MyMacCleanCore`, presentation state in `MyMacCleanAppSupport`, and SwiftUI rendering in `MyMacCleanApp`. Extend the existing app deletion flow instead of replacing it: scanner creates candidates with structured evidence and safety, executor deletes, verifier confirms path-level outcomes, receipt store persists results, and view models expose report/history/orphan screens.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI, Observation, Foundation, XCTest, local JSONL receipt storage.

---

## Scope Check

This plan intentionally covers only Milestone 1 from `docs/superpowers/specs/2026-06-20-mymacclean-trust-and-app-management-design.md`.

Included:

- Safety score and structured match-reason explanations.
- Post-delete verification report.
- Deletion receipts and Delete History.
- Orphan Files Finder.

Excluded from this plan:

- App Reset.
- Search, filter, and sort.
- Startup Items manager.

Those excluded features are independent subsystems and should get separate implementation plans after this milestone is verified.

## File Structure

Create:

- `Sources/MyMacCleanCore/Models/MatchEvidence.swift`: evidence types, evidence strength, safety level, and path-level verification status.
- `Sources/MyMacCleanCore/Deletion/DeletionVerifier.swift`: checks whether planned paths are deleted, still present, missing before deletion, or inaccessible.
- `Sources/MyMacCleanCore/Journal/DeletionReceiptStore.swift`: appends and reads receipt records with execution and verification results.
- `Sources/MyMacCleanCore/Orphans/OrphanFileScanner.swift`: finds leftover files whose owning app bundle is no longer installed.
- `Sources/MyMacCleanAppSupport/DeletionReportViewModel.swift`: summarizes verification and receipt data for UI.
- `Sources/MyMacCleanAppSupport/DeleteHistoryViewModel.swift`: loads, searches, and presents receipts.
- `Sources/MyMacCleanAppSupport/OrphanFilesViewModel.swift`: scans, groups, selects, deletes, verifies, and records orphan leftovers.
- `Tests/MyMacCleanCoreTests/SafetyScorerTests.swift`
- `Tests/MyMacCleanCoreTests/DeletionVerifierTests.swift`
- `Tests/MyMacCleanCoreTests/DeletionReceiptStoreTests.swift`
- `Tests/MyMacCleanCoreTests/OrphanFileScannerTests.swift`
- `Tests/MyMacCleanAppSupportTests/DeletionReportViewModelTests.swift`
- `Tests/MyMacCleanAppSupportTests/DeleteHistoryViewModelTests.swift`
- `Tests/MyMacCleanAppSupportTests/OrphanFilesViewModelTests.swift`

Modify:

- `Sources/MyMacCleanCore/Models/RelatedFileCandidate.swift`: add evidence and safety fields while preserving existing compatibility where possible.
- `Sources/MyMacCleanCore/Scanning/CandidateMatcher.swift`: return structured `MatchEvidence`.
- `Sources/MyMacCleanCore/Scanning/RelatedFileScanner.swift`: assign safety and evidence for each candidate.
- `Sources/MyMacCleanAppSupport/ApplicationListViewModel.swift`: run verification and receipt persistence after deletion.
- `Sources/MyMacCleanAppSupport/SidebarDestination.swift`: add `orphanFiles` to the current-release navigation.
- `Sources/MyMacCleanApp/Views/Components.swift`: show safety badge and evidence text in candidate rows.
- `Sources/MyMacCleanApp/Views/ContentView.swift`: add deletion report state, real Delete History, and Orphan Files screen.
- Existing tests that construct `RelatedFileCandidate`: update calls with defaulted or explicit evidence/safety values after the model change.

---

### Task 1: Add Safety and Evidence Domain Models

**Files:**

- Create: `Sources/MyMacCleanCore/Models/MatchEvidence.swift`
- Modify: `Sources/MyMacCleanCore/Models/RelatedFileCandidate.swift`
- Test: `Tests/MyMacCleanCoreTests/SafetyScorerTests.swift`

- [ ] **Step 1: Write failing safety scorer tests**

Create `Tests/MyMacCleanCoreTests/SafetyScorerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter SafetyScorerTests
```

Expected: FAIL because `MatchEvidence`, `SafetyScorer`, `SafetyScore`, and `CandidateSafetyLevel` do not exist.

- [ ] **Step 3: Add evidence and safety models**

Create `Sources/MyMacCleanCore/Models/MatchEvidence.swift`:

```swift
import Foundation

public enum MatchEvidenceType: String, Codable, Equatable, Sendable {
    case selectedAppBundle
    case bundleIdentifier
    case exactAppName
    case executableName
    case knownUpdaterName
    case receiptHistory
    case weakName
}

public enum MatchEvidenceStrength: String, Codable, Equatable, Sendable {
    case strong
    case medium
    case weak
}

public struct MatchEvidence: Codable, Equatable, Sendable {
    public let type: MatchEvidenceType
    public let matchedValue: String
    public let sourcePath: String
    public let strength: MatchEvidenceStrength

    public init(type: MatchEvidenceType, matchedValue: String, sourcePath: String, strength: MatchEvidenceStrength) {
        self.type = type
        self.matchedValue = matchedValue
        self.sourcePath = sourcePath
        self.strength = strength
    }
}

public enum CandidateSafetyLevel: String, Codable, Equatable, Sendable {
    case safe
    case review
    case risky
}

public struct SafetyScore: Codable, Equatable, Sendable {
    public let level: CandidateSafetyLevel
    public let defaultSelected: Bool
    public let requiresManualReview: Bool

    public init(level: CandidateSafetyLevel, defaultSelected: Bool, requiresManualReview: Bool) {
        self.level = level
        self.defaultSelected = defaultSelected
        self.requiresManualReview = requiresManualReview
    }
}

public struct SafetyScorer: Sendable {
    public init() {}

    public func score(
        evidence: [MatchEvidence],
        kind: RelatedFileKind,
        isProtected: Bool,
        isKnownCleanupRoot: Bool
    ) -> SafetyScore {
        if isProtected {
            return SafetyScore(level: .risky, defaultSelected: false, requiresManualReview: true)
        }

        if evidence.contains(where: { $0.type == .weakName || $0.strength == .weak }) {
            return SafetyScore(level: .risky, defaultSelected: false, requiresManualReview: true)
        }

        if evidence.contains(where: { $0.type == .bundleIdentifier || $0.type == .selectedAppBundle }) && isKnownCleanupRoot {
            return SafetyScore(level: .safe, defaultSelected: true, requiresManualReview: false)
        }

        if evidence.contains(where: { $0.type == .exactAppName || $0.type == .executableName || $0.type == .knownUpdaterName }) && isKnownCleanupRoot {
            return SafetyScore(level: .review, defaultSelected: true, requiresManualReview: true)
        }

        return SafetyScore(level: .risky, defaultSelected: false, requiresManualReview: true)
    }
}
```

- [ ] **Step 4: Extend `RelatedFileCandidate` with defaulted evidence and safety**

Modify `Sources/MyMacCleanCore/Models/RelatedFileCandidate.swift`:

```swift
public struct RelatedFileCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let kind: RelatedFileKind
    public let size: Int64
    public let matchReason: String
    public let confidence: MatchConfidence
    public let evidence: [MatchEvidence]
    public let safety: CandidateSafetyLevel
    public let defaultSelected: Bool
    public let requiresManualReview: Bool
    public let isProtected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        kind: RelatedFileKind,
        size: Int64,
        matchReason: String,
        confidence: MatchConfidence,
        evidence: [MatchEvidence] = [],
        safety: CandidateSafetyLevel = .review,
        defaultSelected: Bool,
        requiresManualReview: Bool,
        isProtected: Bool
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.size = size
        self.matchReason = matchReason
        self.confidence = confidence
        self.evidence = evidence
        self.safety = safety
        self.defaultSelected = defaultSelected
        self.requiresManualReview = requiresManualReview
        self.isProtected = isProtected
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter SafetyScorerTests
swift test
```

Expected: `SafetyScorerTests` PASS and the full suite PASS after updating any compile errors from new initializer parameters.

- [ ] **Step 6: Commit**

```bash
git add Sources/MyMacCleanCore/Models/MatchEvidence.swift Sources/MyMacCleanCore/Models/RelatedFileCandidate.swift Tests/MyMacCleanCoreTests/SafetyScorerTests.swift Tests
git commit -m "feat: add candidate safety scoring"
```

---

### Task 2: Return Structured Evidence From Candidate Matching

**Files:**

- Modify: `Sources/MyMacCleanCore/Scanning/CandidateMatcher.swift`
- Modify: `Sources/MyMacCleanCore/Scanning/RelatedFileScanner.swift`
- Test: `Tests/MyMacCleanCoreTests/CandidateMatcherTests.swift`
- Test: `Tests/MyMacCleanCoreTests/RelatedFileScannerTests.swift`

- [ ] **Step 1: Write failing matcher evidence tests**

Append to `Tests/MyMacCleanCoreTests/CandidateMatcherTests.swift`:

```swift
func testBundleIdentifierMatchCarriesStrongEvidence() {
    let app = InstalledApp(
        displayName: "Cursor",
        bundleIdentifier: "com.todesktop.230313mzl4w4u92",
        version: nil,
        executableName: "Cursor",
        bundleURL: URL(fileURLWithPath: "/Applications/Cursor.app"),
        iconIdentifier: nil,
        bundleSize: 0,
        lastOpenedAt: nil
    )

    let match = CandidateMatcher().match(
        url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.todesktop.230313mzl4w4u92"),
        app: app,
        kind: .cache
    )

    XCTAssertEqual(match?.evidence, [
        MatchEvidence(
            type: .bundleIdentifier,
            matchedValue: "com.todesktop.230313mzl4w4u92",
            sourcePath: "/Users/me/Library/Caches/com.todesktop.230313mzl4w4u92",
            strength: .strong
        )
    ])
}

func testFullAppNameMatchCarriesExactNameEvidence() {
    let app = InstalledApp(
        displayName: "MyMacClean Delete Test",
        bundleIdentifier: "com.local.MyMacCleanDeleteTest",
        version: nil,
        executableName: "MyMacClean Delete Test",
        bundleURL: URL(fileURLWithPath: "/Users/me/Applications/MyMacClean Delete Test.app"),
        iconIdentifier: nil,
        bundleSize: 0,
        lastOpenedAt: nil
    )

    let match = CandidateMatcher().match(
        url: URL(fileURLWithPath: "/Users/me/Library/Application Support/MyMacClean Delete Test"),
        app: app,
        kind: .applicationSupport
    )

    XCTAssertEqual(match?.evidence.first?.type, .exactAppName)
    XCTAssertEqual(match?.evidence.first?.strength, .medium)
}
```

- [ ] **Step 2: Run matcher tests to verify failure**

Run:

```bash
swift test --filter CandidateMatcherTests
```

Expected: FAIL because `CandidateMatch` has no `evidence` property.

- [ ] **Step 3: Add evidence to `CandidateMatch` and matcher results**

Modify `Sources/MyMacCleanCore/Scanning/CandidateMatcher.swift`:

```swift
public struct CandidateMatch: Equatable, Sendable {
    public let matchReason: String
    public let confidence: MatchConfidence
    public let evidence: [MatchEvidence]
    public let defaultSelected: Bool
    public let requiresManualReview: Bool
}
```

Update bundle identifier match return:

```swift
let evidence = MatchEvidence(
    type: .bundleIdentifier,
    matchedValue: bundleIdentifier,
    sourcePath: url.path,
    strength: .strong
)
return CandidateMatch(
    matchReason: "bundle identifier match",
    confidence: .high,
    evidence: [evidence],
    defaultSelected: true,
    requiresManualReview: false
)
```

Update full-name match return:

```swift
let evidence = MatchEvidence(
    type: .exactAppName,
    matchedValue: app.displayName,
    sourcePath: url.path,
    strength: .medium
)
return CandidateMatch(
    matchReason: "full app name match",
    confidence: kind == .unknown ? .low : .medium,
    evidence: [evidence],
    defaultSelected: kind != .unknown,
    requiresManualReview: kind == .unknown
)
```

- [ ] **Step 4: Update scanner to score candidates from evidence**

Modify `Sources/MyMacCleanCore/Scanning/RelatedFileScanner.swift`:

```swift
private let safetyScorer: SafetyScorer
```

Update the initializer:

```swift
public init(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    extraScanRoots: [URL] = [],
    matcher: CandidateMatcher = CandidateMatcher(),
    protectionPolicy: ProtectionPolicy? = nil,
    sizeCalculator: FileSizeCalculator = FileSizeCalculator(),
    safetyScorer: SafetyScorer = SafetyScorer()
) {
    self.homeDirectory = homeDirectory
    self.extraScanRoots = extraScanRoots
    self.matcher = matcher
    self.protectionPolicy = protectionPolicy ?? ProtectionPolicy(homeDirectory: homeDirectory)
    self.sizeCalculator = sizeCalculator
    self.safetyScorer = safetyScorer
}
```

For the app bundle candidate:

```swift
let appBundleEvidence = MatchEvidence(
    type: .selectedAppBundle,
    matchedValue: app.displayName,
    sourcePath: app.bundleURL.path,
    strength: .strong
)
let appBundleSafety = safetyScorer.score(
    evidence: [appBundleEvidence],
    kind: .appBundle,
    isProtected: protectionPolicy.isProtected(app.bundleURL),
    isKnownCleanupRoot: true
)
```

Use `evidence: [appBundleEvidence]`, `safety: appBundleSafety.level`, `defaultSelected: appBundleSafety.defaultSelected`, and `requiresManualReview: appBundleSafety.requiresManualReview`.

For scanned candidates:

```swift
let isProtected = protectionPolicy.isProtected(url)
let safety = safetyScorer.score(
    evidence: match.evidence,
    kind: kind,
    isProtected: isProtected,
    isKnownCleanupRoot: kind != .unknown
)
candidates.append(
    RelatedFileCandidate(
        url: url,
        kind: kind,
        size: (try? sizeCalculator.sizeOfItem(at: url)) ?? 0,
        matchReason: match.matchReason,
        confidence: match.confidence,
        evidence: match.evidence,
        safety: safety.level,
        defaultSelected: safety.defaultSelected,
        requiresManualReview: safety.requiresManualReview,
        isProtected: isProtected
    )
)
```

- [ ] **Step 5: Add scanner evidence assertions**

Append to `Tests/MyMacCleanCoreTests/RelatedFileScannerTests.swift`:

```swift
func testScannerAttachesEvidenceAndSafetyToCandidates() async throws {
    let home = try TestFixtures.temporaryDirectory(named: "scanner-evidence-home")
    let app = InstalledApp(
        displayName: "Cursor",
        bundleIdentifier: "com.todesktop.230313mzl4w4u92",
        version: nil,
        executableName: "Cursor",
        bundleURL: home.appendingPathComponent("Applications/Cursor.app"),
        iconIdentifier: nil,
        bundleSize: 10,
        lastOpenedAt: nil
    )
    let cache = home.appendingPathComponent("Library/Caches/com.todesktop.230313mzl4w4u92", isDirectory: true)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

    let candidates = try await RelatedFileScanner(homeDirectory: home).scanRelatedFiles(for: app)
    let scanned = try XCTUnwrap(candidates.first { $0.url == cache })

    XCTAssertEqual(scanned.safety, .safe)
    XCTAssertEqual(scanned.evidence.first?.type, .bundleIdentifier)
    XCTAssertEqual(scanned.evidence.first?.matchedValue, "com.todesktop.230313mzl4w4u92")
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
swift test --filter 'CandidateMatcherTests|RelatedFileScannerTests|SafetyScorerTests'
swift test
```

Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MyMacCleanCore/Scanning Sources/MyMacCleanCore/Models Tests/MyMacCleanCoreTests
git commit -m "feat: attach evidence to related files"
```

---

### Task 3: Add Path-Level Deletion Verification

**Files:**

- Create: `Sources/MyMacCleanCore/Deletion/DeletionVerifier.swift`
- Modify: `Sources/MyMacCleanCore/Models/RelatedFileCandidate.swift`
- Test: `Tests/MyMacCleanCoreTests/DeletionVerifierTests.swift`

- [ ] **Step 1: Write failing verifier tests**

Create `Tests/MyMacCleanCoreTests/DeletionVerifierTests.swift`:

```swift
import XCTest
@testable import MyMacCleanCore

final class DeletionVerifierTests: XCTestCase {
    func testVerifierClassifiesDeletedAndStillExistingPaths() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "verifier")
        let deletedURL = root.appendingPathComponent("deleted-cache", isDirectory: true)
        let remainingURL = root.appendingPathComponent("remaining-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: deletedURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remainingURL, withIntermediateDirectories: true)

        let app = InstalledApp(displayName: "Verifier", bundleIdentifier: "com.example.verifier", version: nil, executableName: nil, bundleURL: root.appendingPathComponent("Verifier.app"), iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let deletedCandidate = RelatedFileCandidate(url: deletedURL, kind: .cache, size: 1, matchReason: "test", confidence: .high, safety: .safe, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let remainingCandidate = RelatedFileCandidate(url: remainingURL, kind: .cache, size: 1, matchReason: "test", confidence: .high, safety: .safe, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [deletedCandidate, remainingCandidate])
        try FileManager.default.removeItem(at: deletedURL)

        let results = await DeletionVerifier().verify(plan: plan)

        XCTAssertEqual(results.map(\.status), [.deleted, .stillExists])
        XCTAssertEqual(results.map(\.path), [deletedURL.path, remainingURL.path])
    }

    func testVerifierClassifiesSkippedCandidates() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "verifier-skipped")
        let skippedURL = root.appendingPathComponent("skipped-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: skippedURL, withIntermediateDirectories: true)

        let candidate = RelatedFileCandidate(url: skippedURL, kind: .cache, size: 1, matchReason: "test", confidence: .high, safety: .safe, defaultSelected: false, requiresManualReview: false, isProtected: false)
        let result = await DeletionVerifier().verify(candidate: candidate, wasSelected: false)

        XCTAssertEqual(result.status, .skipped)
        XCTAssertEqual(result.path, skippedURL.path)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter DeletionVerifierTests
```

Expected: FAIL because `DeletionVerifier`, `DeletionVerificationResult`, and `DeletionVerificationStatus` do not exist.

- [ ] **Step 3: Add verification status and result models**

Add to `Sources/MyMacCleanCore/Models/MatchEvidence.swift`:

```swift
public enum DeletionVerificationStatus: String, Codable, Equatable, Sendable {
    case deleted
    case stillExists
    case notFoundBeforeDelete
    case permissionDenied
    case skipped
}

public struct DeletionVerificationResult: Codable, Equatable, Sendable {
    public let path: String
    public let status: DeletionVerificationStatus
    public let errorMessage: String?

    public init(path: String, status: DeletionVerificationStatus, errorMessage: String?) {
        self.path = path
        self.status = status
        self.errorMessage = errorMessage
    }
}
```

- [ ] **Step 4: Implement `DeletionVerifier`**

Create `Sources/MyMacCleanCore/Deletion/DeletionVerifier.swift`:

```swift
import Foundation

public struct DeletionVerifier: Sendable {
    public init() {}

    public func verify(plan: DeletionPlan) async -> [DeletionVerificationResult] {
        plan.candidates.map { candidate in
            verifyExistingPath(candidate.url)
        }
    }

    public func verify(candidate: RelatedFileCandidate, wasSelected: Bool) async -> DeletionVerificationResult {
        guard wasSelected else {
            return DeletionVerificationResult(path: candidate.url.path, status: .skipped, errorMessage: nil)
        }
        return verifyExistingPath(candidate.url)
    }

    private func verifyExistingPath(_ url: URL) -> DeletionVerificationResult {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else {
            return DeletionVerificationResult(path: url.path, status: .deleted, errorMessage: nil)
        }

        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return DeletionVerificationResult(path: url.path, status: .stillExists, errorMessage: nil)
        } catch CocoaError.fileReadNoPermission, CocoaError.fileNoSuchFile {
            return DeletionVerificationResult(path: url.path, status: .permissionDenied, errorMessage: "permission denied")
        } catch {
            return DeletionVerificationResult(path: url.path, status: .permissionDenied, errorMessage: error.localizedDescription)
        }
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter DeletionVerifierTests
swift test
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MyMacCleanCore/Deletion/DeletionVerifier.swift Sources/MyMacCleanCore/Models/MatchEvidence.swift Tests/MyMacCleanCoreTests/DeletionVerifierTests.swift
git commit -m "feat: verify deletion results"
```

---

### Task 4: Persist Deletion Receipts With Verification Results

**Files:**

- Create: `Sources/MyMacCleanCore/Journal/DeletionReceiptStore.swift`
- Modify: `Sources/MyMacCleanCore/Journal/DeletionJournal.swift`
- Test: `Tests/MyMacCleanCoreTests/DeletionReceiptStoreTests.swift`

- [ ] **Step 1: Write failing receipt store tests**

Create `Tests/MyMacCleanCoreTests/DeletionReceiptStoreTests.swift`:

```swift
import XCTest
@testable import MyMacCleanCore

final class DeletionReceiptStoreTests: XCTestCase {
    func testAppendsAndReadsDeletionReceiptWithVerificationResults() throws {
        let root = try TestFixtures.temporaryDirectory(named: "receipt-store")
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        let receipt = DeletionReceipt(
            appName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            bundlePath: "/Applications/Cursor.app",
            action: .uninstall,
            completedAt: Date(timeIntervalSince1970: 100),
            selectedCandidates: [
                DeletionReceiptCandidate(path: "/Applications/Cursor.app", kind: .appBundle, size: 10, safety: .safe, evidence: [])
            ],
            executionResults: [
                DeletionItemResult(path: "/Applications/Cursor.app", success: true, errorMessage: nil)
            ],
            verificationResults: [
                DeletionVerificationResult(path: "/Applications/Cursor.app", status: .deleted, errorMessage: nil)
            ],
            confirmationMatched: true
        )

        try store.append(receipt)

        XCTAssertEqual(try store.readReceipts(), [receipt])
    }

    func testClearReceiptsRemovesHistoryFile() throws {
        let root = try TestFixtures.temporaryDirectory(named: "receipt-store-clear")
        let receiptURL = root.appendingPathComponent("receipts.jsonl")
        let store = DeletionReceiptStore(fileURL: receiptURL)
        let receipt = DeletionReceipt(appName: "App", bundleIdentifier: nil, bundlePath: "/Applications/App.app", action: .uninstall, completedAt: Date(timeIntervalSince1970: 0), selectedCandidates: [], executionResults: [], verificationResults: [], confirmationMatched: true)

        try store.append(receipt)
        try store.clear()

        XCTAssertFalse(FileManager.default.fileExists(atPath: receiptURL.path))
        XCTAssertEqual(try store.readReceipts(), [])
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter DeletionReceiptStoreTests
```

Expected: FAIL because receipt types and store do not exist.

- [ ] **Step 3: Implement receipt models and store**

Create `Sources/MyMacCleanCore/Journal/DeletionReceiptStore.swift`:

```swift
import Foundation

public enum DeletionAction: String, Codable, Equatable, Sendable {
    case uninstall
    case orphanCleanup
}

public struct DeletionReceiptCandidate: Codable, Equatable, Sendable {
    public let path: String
    public let kind: RelatedFileKind
    public let size: Int64
    public let safety: CandidateSafetyLevel
    public let evidence: [MatchEvidence]

    public init(path: String, kind: RelatedFileKind, size: Int64, safety: CandidateSafetyLevel, evidence: [MatchEvidence]) {
        self.path = path
        self.kind = kind
        self.size = size
        self.safety = safety
        self.evidence = evidence
    }
}

public struct DeletionReceipt: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let appName: String
    public let bundleIdentifier: String?
    public let bundlePath: String
    public let action: DeletionAction
    public let completedAt: Date
    public let selectedCandidates: [DeletionReceiptCandidate]
    public let executionResults: [DeletionItemResult]
    public let verificationResults: [DeletionVerificationResult]
    public let confirmationMatched: Bool

    public init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String?,
        bundlePath: String,
        action: DeletionAction,
        completedAt: Date = Date(),
        selectedCandidates: [DeletionReceiptCandidate],
        executionResults: [DeletionItemResult],
        verificationResults: [DeletionVerificationResult],
        confirmationMatched: Bool
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.action = action
        self.completedAt = completedAt
        self.selectedCandidates = selectedCandidates
        self.executionResults = executionResults
        self.verificationResults = verificationResults
        self.confirmationMatched = confirmationMatched
    }
}

public struct DeletionReceiptStore: Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ receipt: DeletionReceipt) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try encoder.encode(receipt)
        data.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: fileURL)
        }
    }

    public func readReceipts() throws -> [DeletionReceipt] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return try text.split(separator: "\n").map { line in
            try decoder.decode(DeletionReceipt.self, from: Data(line.utf8))
        }
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
```

- [ ] **Step 4: Leave `DeletionJournal` in place for compatibility**

Do not remove `DeletionJournal` in this task. Existing tests should keep passing while new code starts using `DeletionReceiptStore`.

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter 'DeletionReceiptStoreTests|DeletionJournalTests'
swift test
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MyMacCleanCore/Journal/DeletionReceiptStore.swift Tests/MyMacCleanCoreTests/DeletionReceiptStoreTests.swift
git commit -m "feat: persist deletion receipts"
```

---

### Task 5: Summarize Verification Reports in App Support

**Files:**

- Create: `Sources/MyMacCleanAppSupport/DeletionReportViewModel.swift`
- Modify: `Sources/MyMacCleanAppSupport/ApplicationListViewModel.swift`
- Test: `Tests/MyMacCleanAppSupportTests/DeletionReportViewModelTests.swift`
- Test: `Tests/MyMacCleanAppSupportTests/ApplicationListViewModelTests.swift`

- [ ] **Step 1: Write failing report summary tests**

Create `Tests/MyMacCleanAppSupportTests/DeletionReportViewModelTests.swift`:

```swift
import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

final class DeletionReportViewModelTests: XCTestCase {
    func testSummarizesVerifiedDeletion() {
        let report = DeletionReportViewModel(
            receipt: DeletionReceipt(
                appName: "Cursor",
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                bundlePath: "/Applications/Cursor.app",
                action: .uninstall,
                selectedCandidates: [],
                executionResults: [],
                verificationResults: [
                    DeletionVerificationResult(path: "/Applications/Cursor.app", status: .deleted, errorMessage: nil),
                    DeletionVerificationResult(path: "/Users/me/Library/Caches/com.todesktop.230313mzl4w4u92", status: .deleted, errorMessage: nil)
                ],
                confirmationMatched: true
            )
        )

        XCTAssertEqual(report.statusTitle, "Deleted and verified")
        XCTAssertEqual(report.deletedCount, 2)
        XCTAssertEqual(report.remainingCount, 0)
        XCTAssertTrue(report.remainingPaths.isEmpty)
    }

    func testSummarizesPartialDeletion() {
        let report = DeletionReportViewModel(
            receipt: DeletionReceipt(
                appName: "Cursor",
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                bundlePath: "/Applications/Cursor.app",
                action: .uninstall,
                selectedCandidates: [],
                executionResults: [],
                verificationResults: [
                    DeletionVerificationResult(path: "/Applications/Cursor.app", status: .deleted, errorMessage: nil),
                    DeletionVerificationResult(path: "/Users/me/Library/Caches/com.todesktop.230313mzl4w4u92", status: .stillExists, errorMessage: nil)
                ],
                confirmationMatched: true
            )
        )

        XCTAssertEqual(report.statusTitle, "Deleted with remaining items")
        XCTAssertEqual(report.deletedCount, 1)
        XCTAssertEqual(report.remainingCount, 1)
        XCTAssertEqual(report.remainingPaths, ["/Users/me/Library/Caches/com.todesktop.230313mzl4w4u92"])
    }
}
```

- [ ] **Step 2: Run report tests to verify failure**

Run:

```bash
swift test --filter DeletionReportViewModelTests
```

Expected: FAIL because `DeletionReportViewModel` does not exist.

- [ ] **Step 3: Implement report view model**

Create `Sources/MyMacCleanAppSupport/DeletionReportViewModel.swift`:

```swift
import Foundation
import MyMacCleanCore

public struct DeletionReportViewModel: Equatable, Sendable {
    public let receipt: DeletionReceipt

    public init(receipt: DeletionReceipt) {
        self.receipt = receipt
    }

    public var statusTitle: String {
        if receipt.verificationResults.contains(where: { $0.status == .stillExists || $0.status == .permissionDenied }) {
            return "Deleted with remaining items"
        }
        if receipt.executionResults.contains(where: { !$0.success }) {
            return "Deletion failed"
        }
        return "Deleted and verified"
    }

    public var deletedCount: Int {
        receipt.verificationResults.filter { $0.status == .deleted }.count
    }

    public var remainingCount: Int {
        receipt.verificationResults.filter { $0.status == .stillExists || $0.status == .permissionDenied }.count
    }

    public var remainingPaths: [String] {
        receipt.verificationResults
            .filter { $0.status == .stillExists || $0.status == .permissionDenied }
            .map(\.path)
    }
}
```

- [ ] **Step 4: Add deletion report state to `ApplicationListViewModel`**

Modify `Sources/MyMacCleanAppSupport/ApplicationListViewModel.swift`:

```swift
private let verifier: DeletionVerifier
private let receiptStore: DeletionReceiptStore
public var deletionReport: DeletionReportViewModel?
```

Update initializer:

```swift
public init(
    discoveryService: AppDiscoveryService = AppDiscoveryService(),
    scanner: RelatedFileScanner = RelatedFileScanner(),
    planner: DeletionPlanner = DeletionPlanner(),
    executor: DeletionExecutor = DeletionExecutor(),
    verifier: DeletionVerifier = DeletionVerifier(),
    receiptStore: DeletionReceiptStore = DeletionReceiptStore(
        fileURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MyMacClean/deletion-receipts.jsonl")
    )
) {
    self.discoveryService = discoveryService
    self.scanner = scanner
    self.planner = planner
    self.executor = executor
    self.verifier = verifier
    self.receiptStore = receiptStore
}
```

In `selectApp(_:)`, clear stale reports:

```swift
deletionReport = nil
```

Update `deleteConfirmedItems(confirmation:)`:

```swift
let plan = try makePlan()
let results = await executor.execute(plan: plan, confirmation: confirmation)
let verificationResults = await verifier.verify(plan: plan)
let receipt = DeletionReceipt(
    appName: plan.app.displayName,
    bundleIdentifier: plan.app.bundleIdentifier,
    bundlePath: plan.app.bundleURL.path,
    action: .uninstall,
    selectedCandidates: plan.candidates.map {
        DeletionReceiptCandidate(path: $0.url.path, kind: $0.kind, size: $0.size, safety: $0.safety, evidence: $0.evidence)
    },
    executionResults: results,
    verificationResults: verificationResults,
    confirmationMatched: results.allSatisfy { $0.errorMessage != "confirmation phrase mismatch" }
)
try? receiptStore.append(receipt)
deletionResults = results
deletionReport = DeletionReportViewModel(receipt: receipt)
reconcileSuccessfulDeletion(plan: plan, results: results)
```

- [ ] **Step 5: Add view model test for report creation**

Append to `Tests/MyMacCleanAppSupportTests/ApplicationListViewModelTests.swift`:

```swift
func testSuccessfulDeletionCreatesVerifiedReport() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanReportTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let appURL = root.appendingPathComponent("Report.app", isDirectory: true)
    try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
    let receiptURL = root.appendingPathComponent("receipts.jsonl")
    let app = InstalledApp(displayName: "Report", bundleIdentifier: "com.example.report", version: nil, executableName: nil, bundleURL: appURL, iconIdentifier: nil, bundleSize: 1, lastOpenedAt: nil)
    let candidate = RelatedFileCandidate(url: appURL, kind: .appBundle, size: 1, matchReason: "app bundle", confidence: .high, safety: .safe, defaultSelected: true, requiresManualReview: false, isProtected: false)
    let viewModel = ApplicationListViewModel(receiptStore: DeletionReceiptStore(fileURL: receiptURL))

    viewModel.apps = [app]
    viewModel.selectApp(app)
    viewModel.candidates = [candidate]
    viewModel.selectedCandidateIDs = [candidate.id]

    await viewModel.deleteConfirmedItems(confirmation: "DELETE")

    XCTAssertEqual(viewModel.deletionReport?.statusTitle, "Deleted and verified")
    XCTAssertEqual(try DeletionReceiptStore(fileURL: receiptURL).readReceipts().count, 1)
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
swift test --filter 'DeletionReportViewModelTests|ApplicationListViewModelTests'
swift test
```

Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MyMacCleanAppSupport/ApplicationListViewModel.swift Sources/MyMacCleanAppSupport/DeletionReportViewModel.swift Tests/MyMacCleanAppSupportTests
git commit -m "feat: report verified deletions"
```

---

### Task 6: Build a Real Delete History Screen

**Files:**

- Create: `Sources/MyMacCleanAppSupport/DeleteHistoryViewModel.swift`
- Modify: `Sources/MyMacCleanApp/Views/ContentView.swift`
- Test: `Tests/MyMacCleanAppSupportTests/DeleteHistoryViewModelTests.swift`

- [ ] **Step 1: Write failing history view model tests**

Create `Tests/MyMacCleanAppSupportTests/DeleteHistoryViewModelTests.swift`:

```swift
import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class DeleteHistoryViewModelTests: XCTestCase {
    func testLoadsReceiptsNewestFirst() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanHistory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        try store.append(DeletionReceipt(appName: "Old", bundleIdentifier: nil, bundlePath: "/Applications/Old.app", action: .uninstall, completedAt: Date(timeIntervalSince1970: 1), selectedCandidates: [], executionResults: [], verificationResults: [], confirmationMatched: true))
        try store.append(DeletionReceipt(appName: "New", bundleIdentifier: nil, bundlePath: "/Applications/New.app", action: .uninstall, completedAt: Date(timeIntervalSince1970: 2), selectedCandidates: [], executionResults: [], verificationResults: [], confirmationMatched: true))
        let viewModel = DeleteHistoryViewModel(receiptStore: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.receipts.map(\.appName), ["New", "Old"])
    }

    func testSearchFiltersByAppNameAndPath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanHistorySearch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        try store.append(DeletionReceipt(appName: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92", bundlePath: "/Applications/Cursor.app", action: .uninstall, selectedCandidates: [], executionResults: [], verificationResults: [], confirmationMatched: true))
        try store.append(DeletionReceipt(appName: "Figma", bundleIdentifier: "com.figma.Desktop", bundlePath: "/Applications/Figma.app", action: .uninstall, selectedCandidates: [], executionResults: [], verificationResults: [], confirmationMatched: true))
        let viewModel = DeleteHistoryViewModel(receiptStore: store)

        await viewModel.load()
        viewModel.searchText = "cursor"

        XCTAssertEqual(viewModel.filteredReceipts.map(\.appName), ["Cursor"])
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter DeleteHistoryViewModelTests
```

Expected: FAIL because `DeleteHistoryViewModel` does not exist.

- [ ] **Step 3: Implement `DeleteHistoryViewModel`**

Create `Sources/MyMacCleanAppSupport/DeleteHistoryViewModel.swift`:

```swift
import Foundation
import Observation
import MyMacCleanCore

@MainActor
@Observable
public final class DeleteHistoryViewModel {
    private let receiptStore: DeletionReceiptStore

    public var receipts: [DeletionReceipt] = []
    public var searchText = ""
    public var errorMessage: String?

    public init(receiptStore: DeletionReceiptStore = DeletionReceiptStore(
        fileURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MyMacClean/deletion-receipts.jsonl")
    )) {
        self.receiptStore = receiptStore
    }

    public var filteredReceipts: [DeletionReceipt] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return receipts }
        return receipts.filter { receipt in
            receipt.appName.lowercased().contains(query)
                || (receipt.bundleIdentifier?.lowercased().contains(query) ?? false)
                || receipt.bundlePath.lowercased().contains(query)
                || receipt.selectedCandidates.contains { $0.path.lowercased().contains(query) }
        }
    }

    public func load() async {
        do {
            receipts = try receiptStore.readReceipts()
                .sorted { $0.completedAt > $1.completedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func clearHistory() {
        do {
            try receiptStore.clear()
            receipts = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Wire Delete History UI**

Modify `Sources/MyMacCleanApp/Views/ContentView.swift`:

Add state:

```swift
@State private var historyViewModel = DeleteHistoryViewModel()
```

In `featureContent(for:)`, route `.deleteHistory` to the real history view before the generic feature view:

```swift
case .deleteHistory:
    deleteHistoryContent
```

In `featureDetail(for:)`, route `.deleteHistory`:

```swift
case .deleteHistory:
    deleteHistoryDetail
```

Add:

```swift
private var deleteHistoryContent: some View {
    VStack(spacing: 0) {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Delete History")
                    .font(.title2.weight(.semibold))
                Text("Review completed deletions and failed cleanup attempts.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh History") {
                Task { await historyViewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()

        List(historyViewModel.filteredReceipts) { receipt in
            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.appName)
                    .font(.headline)
                Text(receipt.bundleIdentifier ?? receipt.bundlePath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .task {
        await historyViewModel.load()
    }
}

private var deleteHistoryDetail: some View {
    VStack(alignment: .leading, spacing: 16) {
        Text("Delete History")
            .font(.title2.weight(.semibold))
        Text("\(historyViewModel.filteredReceipts.count) receipts")
            .foregroundStyle(.secondary)
        Divider()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(historyViewModel.filteredReceipts) { receipt in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(receipt.appName)
                            .font(.headline)
                        Text(receipt.completedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("\(receipt.verificationResults.count) verified paths")
                            .font(.callout)
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
    }
    .padding(22)
}
```

- [ ] **Step 5: Run tests and build**

Run:

```bash
swift test --filter DeleteHistoryViewModelTests
swift test
swift build
```

Expected: all commands PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MyMacCleanAppSupport/DeleteHistoryViewModel.swift Sources/MyMacCleanApp/Views/ContentView.swift Tests/MyMacCleanAppSupportTests/DeleteHistoryViewModelTests.swift
git commit -m "feat: show deletion history"
```

---

### Task 7: Implement Orphan Files Scanner

**Files:**

- Create: `Sources/MyMacCleanCore/Orphans/OrphanFileScanner.swift`
- Test: `Tests/MyMacCleanCoreTests/OrphanFileScannerTests.swift`

- [ ] **Step 1: Write failing orphan scanner tests**

Create `Tests/MyMacCleanCoreTests/OrphanFileScannerTests.swift`:

```swift
import XCTest
@testable import MyMacCleanCore

final class OrphanFileScannerTests: XCTestCase {
    func testFindsBundleIdentifierLeftoversForMissingApp() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "orphans-home")
        let cache = home.appendingPathComponent("Library/Caches/com.todesktop.230313mzl4w4u92", isDirectory: true)
        let prefs = home.appendingPathComponent("Library/Preferences/com.todesktop.230313mzl4w4u92.plist")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefs.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4).write(to: prefs)

        let groups = try await OrphanFileScanner(homeDirectory: home, installedApps: []).scan()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].inferredIdentifier, "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(Set(groups[0].candidates.map(\.url)), [cache, prefs])
    }

    func testDoesNotFlagInstalledAppLeftoversAsOrphans() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "orphans-installed-home")
        let cache = home.appendingPathComponent("Library/Caches/com.figma.Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: nil, executableName: "Figma", bundleURL: home.appendingPathComponent("Applications/Figma.app"), iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)

        let groups = try await OrphanFileScanner(homeDirectory: home, installedApps: [app]).scan()

        XCTAssertTrue(groups.isEmpty)
    }

    func testDoesNotTreatGenericCursorNamedDevelopmentPackagesAsCursorOrphans() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "orphans-yarn-home")
        let yarnPackage = home.appendingPathComponent("Library/Caches/Yarn/v6/npm-cli-cursor-3.1.0-integrity", isDirectory: true)
        try FileManager.default.createDirectory(at: yarnPackage, withIntermediateDirectories: true)

        let groups = try await OrphanFileScanner(homeDirectory: home, installedApps: []).scan()

        XCTAssertTrue(groups.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter OrphanFileScannerTests
```

Expected: FAIL because `OrphanFileScanner` and `OrphanFileGroup` do not exist.

- [ ] **Step 3: Implement orphan scanner**

Create `Sources/MyMacCleanCore/Orphans/OrphanFileScanner.swift`:

```swift
import Foundation

public struct OrphanFileGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let inferredName: String
    public let inferredIdentifier: String
    public let candidates: [RelatedFileCandidate]
    public let totalSize: Int64

    public init(inferredName: String, inferredIdentifier: String, candidates: [RelatedFileCandidate]) {
        self.id = inferredIdentifier
        self.inferredName = inferredName
        self.inferredIdentifier = inferredIdentifier
        self.candidates = candidates
        self.totalSize = candidates.reduce(0) { $0 + $1.size }
    }
}

public struct OrphanFileScanner: Sendable {
    private let homeDirectory: URL
    private let installedApps: [InstalledApp]
    private let protectionPolicy: ProtectionPolicy
    private let sizeCalculator: FileSizeCalculator
    private let safetyScorer: SafetyScorer

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        installedApps: [InstalledApp],
        protectionPolicy: ProtectionPolicy? = nil,
        sizeCalculator: FileSizeCalculator = FileSizeCalculator(),
        safetyScorer: SafetyScorer = SafetyScorer()
    ) {
        self.homeDirectory = homeDirectory
        self.installedApps = installedApps
        self.protectionPolicy = protectionPolicy ?? ProtectionPolicy(homeDirectory: homeDirectory)
        self.sizeCalculator = sizeCalculator
        self.safetyScorer = safetyScorer
    }

    public func scan() async throws -> [OrphanFileGroup] {
        let installedIdentifiers = Set(installedApps.compactMap { $0.bundleIdentifier?.lowercased() })
        var grouped: [String: [RelatedFileCandidate]] = [:]

        for (root, kind) in scanRoots() where FileManager.default.fileExists(atPath: root.path) {
            let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            for url in urls {
                guard let identifier = bundleIdentifierCandidate(from: url.lastPathComponent) else { continue }
                guard !installedIdentifiers.contains(identifier.lowercased()) else { continue }

                let evidence = MatchEvidence(type: .bundleIdentifier, matchedValue: identifier, sourcePath: url.path, strength: .strong)
                let isProtected = protectionPolicy.isProtected(url)
                let safety = safetyScorer.score(evidence: [evidence], kind: kind, isProtected: isProtected, isKnownCleanupRoot: true)
                let candidate = RelatedFileCandidate(
                    url: url,
                    kind: kind,
                    size: (try? sizeCalculator.sizeOfItem(at: url)) ?? 0,
                    matchReason: "orphan bundle identifier match",
                    confidence: .high,
                    evidence: [evidence],
                    safety: safety.level,
                    defaultSelected: safety.defaultSelected,
                    requiresManualReview: safety.requiresManualReview,
                    isProtected: isProtected
                )
                grouped[identifier, default: []].append(candidate)
            }
        }

        return grouped
            .map { identifier, candidates in
                OrphanFileGroup(inferredName: identifier, inferredIdentifier: identifier, candidates: candidates.sorted { $0.url.path < $1.url.path })
            }
            .sorted { $0.inferredIdentifier.localizedCaseInsensitiveCompare($1.inferredIdentifier) == .orderedAscending }
    }

    private func scanRoots() -> [(URL, RelatedFileKind)] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return [
            (library.appendingPathComponent("Application Support", isDirectory: true), .applicationSupport),
            (library.appendingPathComponent("Application Support/Caches", isDirectory: true), .cache),
            (library.appendingPathComponent("Caches", isDirectory: true), .cache),
            (library.appendingPathComponent("Preferences", isDirectory: true), .preferences),
            (library.appendingPathComponent("Preferences/ByHost", isDirectory: true), .preferences),
            (library.appendingPathComponent("Saved Application State", isDirectory: true), .savedState),
            (library.appendingPathComponent("HTTPStorages", isDirectory: true), .httpStorage),
            (library.appendingPathComponent("WebKit", isDirectory: true), .webKit),
            (library.appendingPathComponent("Containers", isDirectory: true), .container),
            (library.appendingPathComponent("Group Containers", isDirectory: true), .groupContainer),
            (library.appendingPathComponent("Logs", isDirectory: true), .log),
            (library.appendingPathComponent("LaunchAgents", isDirectory: true), .launchAgent)
        ]
    }

    private func bundleIdentifierCandidate(from lastPathComponent: String) -> String? {
        let stripped = lastPathComponent
            .replacingOccurrences(of: ".binarycookies", with: "")
            .replacingOccurrences(of: ".savedState", with: "")
            .replacingOccurrences(of: ".plist", with: "")
        let parts = stripped.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        guard parts.allSatisfy({ $0.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil }) else { return nil }
        return parts.joined(separator: ".")
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
swift test --filter OrphanFileScannerTests
swift test
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCleanCore/Orphans/OrphanFileScanner.swift Tests/MyMacCleanCoreTests/OrphanFileScannerTests.swift
git commit -m "feat: find orphaned app files"
```

---

### Task 8: Add Orphan Files View Model and Navigation

**Files:**

- Create: `Sources/MyMacCleanAppSupport/OrphanFilesViewModel.swift`
- Modify: `Sources/MyMacCleanAppSupport/SidebarDestination.swift`
- Test: `Tests/MyMacCleanAppSupportTests/OrphanFilesViewModelTests.swift`
- Test: `Tests/MyMacCleanAppSupportTests/SidebarDestinationTests.swift`

- [ ] **Step 1: Write failing orphan view model test**

Create `Tests/MyMacCleanAppSupportTests/OrphanFilesViewModelTests.swift`:

```swift
import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class OrphanFilesViewModelTests: XCTestCase {
    func testLoadGroupsFindsOrphansFromInstalledAppsSnapshot() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanVM-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let orphan = home.appendingPathComponent("Library/Caches/com.example.deleted", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        let viewModel = OrphanFilesViewModel(homeDirectory: home, installedApps: [])

        await viewModel.loadGroups()

        XCTAssertEqual(viewModel.groups.map(\.inferredIdentifier), ["com.example.deleted"])
        XCTAssertEqual(viewModel.selectedCandidateIDs.count, 1)
    }
}
```

- [ ] **Step 2: Update sidebar tests for Orphan Files**

Modify `Tests/MyMacCleanAppSupportTests/SidebarDestinationTests.swift`:

```swift
XCTAssertEqual(SidebarDestination.orphanFiles.title, "Orphan Files")
XCTAssertEqual(SidebarDestination.orphanFiles.primaryActionTitle, "Scan Leftovers")
XCTAssertTrue(SidebarDestination.currentRelease.contains(.orphanFiles))
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
swift test --filter 'OrphanFilesViewModelTests|SidebarDestinationTests'
```

Expected: FAIL because `OrphanFilesViewModel` and `.orphanFiles` do not exist.

- [ ] **Step 4: Add `orphanFiles` destination**

Modify `Sources/MyMacCleanAppSupport/SidebarDestination.swift`:

```swift
case orphanFiles
```

Update current release:

```swift
public static let currentRelease: [SidebarDestination] = [
    .applications,
    .orphanFiles,
    .deleteHistory
]
```

Add switch cases:

```swift
case .orphanFiles: "Orphan Files"
case .orphanFiles:
    "Find leftovers from apps that are no longer installed."
case .orphanFiles: "folder.badge.questionmark"
case .orphanFiles: "Scan Leftovers"
```

- [ ] **Step 5: Implement `OrphanFilesViewModel`**

Create `Sources/MyMacCleanAppSupport/OrphanFilesViewModel.swift`:

```swift
import Foundation
import Observation
import MyMacCleanCore

@MainActor
@Observable
public final class OrphanFilesViewModel {
    private let homeDirectory: URL
    private let installedApps: [InstalledApp]
    private let executor: DeletionExecutor
    private let verifier: DeletionVerifier
    private let receiptStore: DeletionReceiptStore

    public var groups: [OrphanFileGroup] = []
    public var selectedCandidateIDs: Set<RelatedFileCandidate.ID> = []
    public var deletionReport: DeletionReportViewModel?
    public var errorMessage: String?
    public var isScanning = false

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        installedApps: [InstalledApp],
        executor: DeletionExecutor = DeletionExecutor(),
        verifier: DeletionVerifier = DeletionVerifier(),
        receiptStore: DeletionReceiptStore = DeletionReceiptStore(
            fileURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/MyMacClean/deletion-receipts.jsonl")
        )
    ) {
        self.homeDirectory = homeDirectory
        self.installedApps = installedApps
        self.executor = executor
        self.verifier = verifier
        self.receiptStore = receiptStore
    }

    public func loadGroups() async {
        isScanning = true
        defer { isScanning = false }
        do {
            groups = try await OrphanFileScanner(homeDirectory: homeDirectory, installedApps: installedApps).scan()
            selectedCandidateIDs = Set(groups.flatMap(\.candidates).filter(\.defaultSelected).map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
swift test --filter 'OrphanFilesViewModelTests|SidebarDestinationTests'
swift test
```

Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MyMacCleanAppSupport/OrphanFilesViewModel.swift Sources/MyMacCleanAppSupport/SidebarDestination.swift Tests/MyMacCleanAppSupportTests
git commit -m "feat: add orphan files navigation state"
```

---

### Task 9: Show Safety, Evidence, Reports, and Orphan Files in SwiftUI

**Files:**

- Modify: `Sources/MyMacCleanApp/Views/Components.swift`
- Modify: `Sources/MyMacCleanApp/Views/ContentView.swift`
- Test: manual UI verification

- [ ] **Step 1: Update candidate rows to show safety and evidence**

Modify `Sources/MyMacCleanApp/Views/Components.swift`.

Add:

```swift
struct SafetyBadge: View {
    let safety: CandidateSafetyLevel

    var body: some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(Capsule())
    }

    private var title: String {
        switch safety {
        case .safe: "Safe"
        case .review: "Review"
        case .risky: "Risky"
        }
    }

    private var background: Color {
        switch safety {
        case .safe: Color.green.opacity(0.16)
        case .review: Color.orange.opacity(0.18)
        case .risky: Color.red.opacity(0.18)
        }
    }
}
```

In `RelatedFileRow`, add evidence text below the path:

```swift
Text(candidate.evidence.first.map { "\($0.type.rawValue): \($0.matchedValue)" } ?? candidate.matchReason)
    .font(.system(size: 12, weight: .medium))
    .foregroundStyle(.secondary)
    .lineLimit(1)
```

Replace `ConfidenceBadge` in the row trailing controls with:

```swift
SafetyBadge(safety: candidate.safety)
    .frame(minWidth: 88, alignment: .trailing)
```

- [ ] **Step 2: Show deletion report after app deletion**

Modify the application `inspector` section in `Sources/MyMacCleanApp/Views/ContentView.swift`.

Above the candidate `ScrollView`, add:

```swift
if let report = viewModel.deletionReport {
    VStack(alignment: .leading, spacing: 8) {
        Text(report.statusTitle)
            .font(.headline.weight(.semibold))
        Text("\(report.deletedCount) deleted, \(report.remainingCount) remaining")
            .font(.callout)
            .foregroundStyle(.secondary)
        ForEach(report.remainingPaths, id: \.self) { path in
            Text(path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.045))
    .clipShape(RoundedRectangle(cornerRadius: 8))
}
```

- [ ] **Step 3: Add Orphan Files content and detail views**

Add state:

```swift
@State private var orphanFilesViewModel: OrphanFilesViewModel?
```

When rendering `.orphanFiles`, lazily create the view model from current apps:

```swift
private var currentOrphanViewModel: OrphanFilesViewModel {
    if let orphanFilesViewModel {
        return orphanFilesViewModel
    }
    let created = OrphanFilesViewModel(installedApps: viewModel.apps)
    orphanFilesViewModel = created
    return created
}
```

Add `orphanFilesContent`:

```swift
private var orphanFilesContent: some View {
    let orphanModel = currentOrphanViewModel
    return VStack(spacing: 0) {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Orphan Files")
                    .font(.title2.weight(.semibold))
                Text("Find leftovers from apps that are no longer installed.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Scan Leftovers") {
                Task { await orphanModel.loadGroups() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(orphanModel.isScanning)
        }
        .padding()

        List(orphanModel.groups) { group in
            VStack(alignment: .leading, spacing: 4) {
                Text(group.inferredIdentifier)
                    .font(.headline)
                Text("\(group.candidates.count) items")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

Add `orphanFilesDetail`:

```swift
private var orphanFilesDetail: some View {
    let orphanModel = currentOrphanViewModel
    return VStack(alignment: .leading, spacing: 16) {
        Text("Orphan Files")
            .font(.title2.weight(.semibold))
        Text("\(orphanModel.groups.count) groups")
            .foregroundStyle(.secondary)
        Divider()
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(orphanModel.groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.inferredIdentifier)
                            .font(.headline)
                        ForEach(group.candidates) { candidate in
                            RelatedFileRow(
                                candidate: candidate,
                                isSelected: orphanModel.selectedCandidateIDs.contains(candidate.id),
                                toggle: {
                                    if orphanModel.selectedCandidateIDs.contains(candidate.id) {
                                        orphanModel.selectedCandidateIDs.remove(candidate.id)
                                    } else {
                                        orphanModel.selectedCandidateIDs.insert(candidate.id)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
    .padding(22)
}
```

Route `.orphanFiles` in `contentColumn` and `detailColumn`.

- [ ] **Step 4: Run build and tests**

Run:

```bash
swift test
swift build
scripts/build-app-bundle.sh
```

Expected: all commands PASS and `dist/MyMacClean.app` exists.

- [ ] **Step 5: Manual UI verification**

Run:

```bash
open dist/MyMacClean.app
```

Verify:

- Applications rows show `Safe`, `Review`, or `Risky` badges after scanning.
- Scanned candidate rows show evidence text.
- Delete History opens a real receipt screen.
- Orphan Files opens a real screen and `Scan Leftovers` triggers a scan.
- Orphan Files and Delete History show working screens instead of generic unavailable screens.

- [ ] **Step 6: Commit**

```bash
git add Sources/MyMacCleanApp/Views/Components.swift Sources/MyMacCleanApp/Views/ContentView.swift
git commit -m "feat: show deletion trust UI"
```

---

### Task 10: End-to-End Fixture Verification

**Files:**

- No source files should be modified unless this task reveals a bug.

- [ ] **Step 1: Create disposable fixture app and leftovers**

Run:

```bash
mkdir -p "$HOME/Applications/MyMacClean Trust Test.app/Contents/MacOS"
/usr/libexec/PlistBuddy -c 'Clear dict' \
  -c 'Add :CFBundleName string MyMacClean Trust Test' \
  -c 'Add :CFBundleDisplayName string MyMacClean Trust Test' \
  -c 'Add :CFBundleIdentifier string com.local.MyMacCleanTrustTest' \
  -c 'Add :CFBundleExecutable string MyMacCleanTrustTest' \
  "$HOME/Applications/MyMacClean Trust Test.app/Contents/Info.plist"
printf '#!/bin/sh\nexit 0\n' > "$HOME/Applications/MyMacClean Trust Test.app/Contents/MacOS/MyMacCleanTrustTest"
chmod +x "$HOME/Applications/MyMacClean Trust Test.app/Contents/MacOS/MyMacCleanTrustTest"
mkdir -p "$HOME/Library/Application Support/MyMacClean Trust Test"
mkdir -p "$HOME/Library/Caches/com.local.MyMacCleanTrustTest"
```

Expected: fixture app and two leftover folders exist.

- [ ] **Step 2: Launch app and verify uninstall flow**

Run:

```bash
scripts/build-app-bundle.sh
open dist/MyMacClean.app
```

In the app:

- Select `MyMacClean Trust Test`.
- Click `Scan Selected`.
- Confirm candidates show safety and evidence.
- Click `Permanently Delete Selected Items`.
- Type `DELETE`.
- Confirm deletion.
- Confirm report shows `Deleted and verified`.
- Confirm `MyMacClean Trust Test` disappears from the app list.

- [ ] **Step 3: Verify filesystem after uninstall**

Run:

```bash
for p in \
  "$HOME/Applications/MyMacClean Trust Test.app" \
  "$HOME/Library/Application Support/MyMacClean Trust Test" \
  "$HOME/Library/Caches/com.local.MyMacCleanTrustTest"
do
  if [ -e "$p" ]; then echo "EXISTS $p"; else echo "MISSING $p"; fi
done
```

Expected:

```text
MISSING /Users/biglol/Applications/MyMacClean Trust Test.app
MISSING /Users/biglol/Library/Application Support/MyMacClean Trust Test
MISSING /Users/biglol/Library/Caches/com.local.MyMacCleanTrustTest
```

- [ ] **Step 4: Verify Delete History**

In the app:

- Click `Delete History`.
- Confirm a receipt for `MyMacClean Trust Test` appears.
- Confirm the receipt shows verified path count.

- [ ] **Step 5: Verify Orphan Files**

Create orphan-only leftovers:

```bash
mkdir -p "$HOME/Library/Caches/com.local.MyMacCleanOrphanOnly"
mkdir -p "$HOME/Library/Preferences"
printf 'orphan' > "$HOME/Library/Preferences/com.local.MyMacCleanOrphanOnly.plist"
```

In the app:

- Click `Orphan Files`.
- Click `Scan Leftovers`.
- Confirm `com.local.MyMacCleanOrphanOnly` appears.
- Do not delete it unless the user approves another destructive test.

- [ ] **Step 6: Clean up orphan-only fixture manually**

Run:

```bash
rm -rf "$HOME/Library/Caches/com.local.MyMacCleanOrphanOnly" \
       "$HOME/Library/Preferences/com.local.MyMacCleanOrphanOnly.plist"
```

Expected: command exits 0.

- [ ] **Step 7: Final verification**

Run:

```bash
swift test
scripts/build-app-bundle.sh
git status --short
```

Expected:

- `swift test`: all tests PASS.
- `scripts/build-app-bundle.sh`: exits 0 and prints `dist/MyMacClean.app`.
- `git status --short`: no uncommitted source changes.

---

## Spec Coverage Self-Review

Covered from the approved spec:

- Safety score and match-reason explanations: Tasks 1, 2, 9.
- Post-delete automatic rescan and verification report: Tasks 3, 5, 9, 10.
- Deletion receipts and logs: Tasks 4, 6, 10.
- Orphan Files Finder: Tasks 7, 8, 9, 10.

Deferred by design:

- App Reset: separate Milestone 2 plan.
- Search, filter, and sort: separate Milestone 2 plan.
- Startup Items manager: separate Milestone 3 plan.

Plan hygiene review:

- No task uses unfinished marker text or an unspecified implementation step.
- Every code-writing task includes concrete file paths and code blocks.

Type consistency:

- `MatchEvidence`, `SafetyScore`, `CandidateSafetyLevel`, `DeletionVerificationResult`, `DeletionReceipt`, and `OrphanFileGroup` are introduced before use by later tasks.
- `DeletionReportViewModel` is introduced before UI rendering.
- `OrphanFilesViewModel` is introduced before Orphan Files UI routing.
