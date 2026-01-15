import Foundation

// MARK: - Keyboard Shortcut Notifications

extension Notification.Name {
    static let createNewTask = Notification.Name("VibeKanban.createNewTask")
    static let filterAllTasks = Notification.Name("VibeKanban.filterAllTasks")
    static let filterRunningTasks = Notification.Name("VibeKanban.filterRunningTasks")
    static let filterWaitingTasks = Notification.Name("VibeKanban.filterWaitingTasks")
    static let filterCompletionTasks = Notification.Name("VibeKanban.filterCompletionTasks")
    static let selectPreviousTask = Notification.Name("VibeKanban.selectPreviousTask")
    static let selectNextTask = Notification.Name("VibeKanban.selectNextTask")
    static let refreshTasks = Notification.Name("VibeKanban.refreshTasks")
}
