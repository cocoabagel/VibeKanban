import Foundation
import SwiftData

// swiftlint:disable sorted_enum_cases
enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case running = "Running"
    case waiting = "Waiting"
    case idle = "Idle"
    case completion = "Completion"
    // swiftlint:enable sorted_enum_cases

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .running:
            "RUNNING"

        case .waiting:
            "WAITING"

        case .idle:
            "IDLE"

        case .completion:
            "COMPLETION"
        }
    }

    var icon: String {
        switch self {
        case .running:
            "arrow.trianglehead.2.clockwise.rotate.90"

        case .waiting:
            "clock.fill"

        case .idle:
            "moon.fill"

        case .completion:
            "flag.fill"
        }
    }
}

@Model
final class KanbanItem {
    @Attribute(.unique)
    var id: UUID
    var title: String
    var itemDescription: String
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var order: Int
    var workingDirectory: String
    var hasLaunchedClaudeOnce: Bool

    // Timer properties
    var accumulatedTime: TimeInterval // 累計作業時間（秒）
    var timerStartedAt: Date? // タイマー開始時刻（running時のみ設定）

    // Latest response from Claude (for display on card)
    var latestResponse: String = ""

    @Transient var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }

    /// 現在の累計作業時間を取得（running中の場合は現在までの時間を含む）
    @Transient var currentElapsedTime: TimeInterval {
        if let startedAt = timerStartedAt {
            return accumulatedTime + Date().timeIntervalSince(startedAt)
        }
        return accumulatedTime
    }

    /// タイマーを開始（running状態になった時に呼ぶ）
    func startTimer() {
        if timerStartedAt == nil {
            timerStartedAt = Date()
        }
    }

    /// タイマーを停止（waiting/completion状態になった時に呼ぶ）
    func stopTimer() {
        if let startedAt = timerStartedAt {
            accumulatedTime += Date().timeIntervalSince(startedAt)
            timerStartedAt = nil
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        itemDescription: String = "",
        status: TaskStatus = .idle,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        order: Int = 0,
        workingDirectory: String = "",
        hasLaunchedClaudeOnce: Bool = false,
        accumulatedTime: TimeInterval = 0,
        timerStartedAt: Date? = nil,
        latestResponse: String = ""
    ) {
        self.id = id
        self.title = title
        self.itemDescription = itemDescription
        statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.order = order
        self.workingDirectory = workingDirectory.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : workingDirectory
        self.hasLaunchedClaudeOnce = hasLaunchedClaudeOnce
        self.accumulatedTime = accumulatedTime
        self.timerStartedAt = timerStartedAt
        self.latestResponse = latestResponse
    }
}
