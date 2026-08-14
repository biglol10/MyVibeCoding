import Foundation

public enum FileEventPlanner {
    public static func plan(events: [FileEvent], scopeRoot: String) -> FileEventPlan {
        let root = URL(fileURLWithPath: scopeRoot).standardizedFileURL.path
        let latestEventID = events.map(\.eventID).max()
        let relevantEvents = events.filter { isSameOrDescendant($0.path, of: root) }

        let unsafeFlags: FileEventFlags = [
            .mustScanSubDirectories,
            .userDropped,
            .kernelDropped,
            .eventIDsWrapped,
            .rootChanged
        ]
        if relevantEvents.contains(where: { !$0.flags.intersection(unsafeFlags).isEmpty }) {
            return FileEventPlan(
                reconcileRoots: [root],
                latestEventID: latestEventID,
                requiresFullReconciliation: true
            )
        }

        var plan = FileEventPlan(latestEventID: latestEventID)
        for event in relevantEvents.sorted(by: eventOrder) {
            if event.flags.contains(.renamed) {
                plan.upsertPaths.remove(event.path)
                plan.deletePaths.remove(event.path)
                plan.reconcileRoots.insert(
                    URL(fileURLWithPath: event.path).deletingLastPathComponent().path
                )
            } else if event.flags.contains(.removed) {
                plan.upsertPaths.remove(event.path)
                plan.deletePaths.insert(event.path)
            } else {
                plan.deletePaths.remove(event.path)
                plan.upsertPaths.insert(event.path)
            }
        }
        return plan
    }

    private static func eventOrder(_ lhs: FileEvent, _ rhs: FileEvent) -> Bool {
        if lhs.eventID == rhs.eventID {
            return lhs.path < rhs.path
        }
        return lhs.eventID < rhs.eventID
    }

    private static func isSameOrDescendant(_ path: String, of root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}
