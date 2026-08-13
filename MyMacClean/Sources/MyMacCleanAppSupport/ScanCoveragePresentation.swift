import Foundation
import MyMacCleanCore

public struct ScanCoveragePresentation: Equatable, Sendable {
    public let title = "Scan incomplete"
    public let summary: String
    public let detailLines: [String]
    public let showsFullDiskAccessAction: Bool

    public init(issues: [ScanIssue]) {
        let count = issues.count
        self.summary = count == 1
            ? "1 location could not be inspected."
            : "\(count) locations could not be inspected."
        self.detailLines = issues
            .map { "\($0.path) - \($0.message)" }
            .sorted()
        self.showsFullDiskAccessAction = issues.contains(where: \.permissionRelated)
    }

    public var copyText: String {
        ([title, summary, ""] + detailLines).joined(separator: "\n")
    }
}
