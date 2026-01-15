import AppKit
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// 通知タップでタスクを選択するためのNotification名
    static let taskSelectedNotification = Notification.Name("NotificationManager.taskSelected")

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
        }
    }

    func sendStatusNotification(taskId: UUID, taskTitle: String, status: TaskStatus, message: String = "") {
        guard status == .waiting || status == .completion else { return }

        let content = UNMutableNotificationContent()

        switch status {
        case .waiting:
            content.title = "入力待ち: \(taskTitle)"
            content.body = message.isEmpty ? "\(taskTitle) が入力を待っています" : message
            content.sound = .default

        case .completion:
            content.title = "完了: \(taskTitle)"
            content.body = message.isEmpty ? "\(taskTitle) が完了しました" : message
            content.sound = .default

        default:
            return
        }

        // 通知IDにタスクIDを使用して、タップ時にタスクを特定できるようにする
        let request = UNNotificationRequest(
            identifier: taskId.uuidString,
            content: content,
            trigger: nil // 即時通知
        )

        UNUserNotificationCenter.current().add(request) { _ in
        }
    }

    // フォアグラウンドでも通知を表示
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // 通知タップ時のハンドリング
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let taskIdString = response.notification.request.identifier

        // タスクIDをUUIDとしてパースし、通知を送信
        if let taskId = UUID(uuidString: taskIdString) {
            Task { @MainActor in
                // アプリをフォアグラウンドに持ってくる
                NSApp.activate(ignoringOtherApps: true)

                // タスク選択通知を送信
                NotificationCenter.default.post(
                    name: Self.taskSelectedNotification,
                    object: nil,
                    userInfo: ["taskId": taskId]
                )
            }
        }

        completionHandler()
    }
}
