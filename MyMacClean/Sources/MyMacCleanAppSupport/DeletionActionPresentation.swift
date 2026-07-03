import MyMacCleanCore

extension DeletionAction {
    var isStartupItemChange: Bool {
        switch self {
        case .startupItemDisable, .startupItemEnable:
            true
        case .uninstall, .orphanCleanup, .largeFileCleanup, .developerCacheCleanup:
            false
        }
    }
}
