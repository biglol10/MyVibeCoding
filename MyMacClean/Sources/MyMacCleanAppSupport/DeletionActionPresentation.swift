import MyMacCleanCore

extension DeletionAction {
    var isStartupItemChange: Bool {
        switch self {
        case .startupItemDisable, .startupItemEnable:
            true
        case .uninstall, .appReset, .orphanCleanup, .largeFileCleanup, .developerCacheCleanup:
            false
        }
    }
}
