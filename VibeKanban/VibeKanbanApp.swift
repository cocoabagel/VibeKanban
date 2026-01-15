import AppKit
import SwiftData
import SwiftUI

// MARK: - Menu Bar View

struct MenuBarView: View {
    @Query private var items: [KanbanItem]
    @Environment(\.openWindow) private var openWindow

    private var runningCount: Int {
        items.count { $0.status == .running }
    }

    private var waitingCount: Int {
        items.count { $0.status == .waiting }
    }

    private var completionCount: Int {
        items.count { $0.status == .completion }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VibeKanban")
                .font(.headline)
                .padding(.bottom, 4)

            Divider()

            HStack(spacing: 16) {
                StatusCountView(
                    icon: TaskStatus.running.icon,
                    label: "Running",
                    count: runningCount,
                    color: .cyan
                )
                StatusCountView(
                    icon: TaskStatus.waiting.icon,
                    label: "Waiting",
                    count: waitingCount,
                    color: .orange
                )
                StatusCountView(
                    icon: TaskStatus.completion.icon,
                    label: "Done",
                    count: completionCount,
                    color: .purple
                )
            }
            .padding(.vertical, 4)

            Divider()

            Button("Open VibeKanban") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(minWidth: 200)
    }
}

struct StatusCountView: View {
    let icon: String
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title2)
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct MenuBarLabel: View {
    @Query private var items: [KanbanItem]

    private var runningCount: Int {
        items.count { $0.status == .running }
    }

    private var waitingCount: Int {
        items.count { $0.status == .waiting }
    }

    private var completionCount: Int {
        items.count { $0.status == .completion }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.grid.2x2")
            Text("R:\(runningCount) W:\(waitingCount) C:\(completionCount)")
                .font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    /// 既存のウィンドウがある場合は新しいウィンドウを開かない
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            // 既存のウィンドウがある場合は、最初のウィンドウを前面に
            sender.windows.first?.makeKeyAndOrderFront(nil)
            return false
        }
        return true
    }

    /// アプリが起動完了した時に NotificationManager を初期化
    func applicationDidFinishLaunching(_: Notification) {
        // NotificationManager のシングルトンをアクセスして delegate を設定
        Task { @MainActor in
            _ = NotificationManager.shared
        }
    }
}

@main
struct VibeKanbanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            KanbanItem.self
        ])

        // Use explicit store URL
        let storeURL = URL.applicationSupportDirectory
            .appending(component: "VibeKanban")
            .appending(component: "vibekanban.store")

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If schema migration fails, delete old database and retry

            // Delete the store files
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("store-shm"))
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("store-wal"))

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_400, height: 900)
        .commands {
            VibeKanbanCommands()
        }

        MenuBarExtra {
            MenuBarView()
                .modelContainer(sharedModelContainer)
        } label: {
            MenuBarLabel()
                .modelContainer(sharedModelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Custom Menu Commands

struct VibeKanbanCommands: Commands {
    var body: some Commands {
        // Task Menu
        CommandMenu("Task") {
            Button("New Task") {
                NotificationCenter.default.post(name: .createNewTask, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("Select Previous") {
                NotificationCenter.default.post(name: .selectPreviousTask, object: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Select Next") {
                NotificationCenter.default.post(name: .selectNextTask, object: nil)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
        }

        // Filter Menu
        CommandMenu("Filter") {
            Button("All Sessions") {
                NotificationCenter.default.post(name: .filterAllTasks, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button("Running") {
                NotificationCenter.default.post(name: .filterRunningTasks, object: nil)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Waiting") {
                NotificationCenter.default.post(name: .filterWaitingTasks, object: nil)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Completion") {
                NotificationCenter.default.post(name: .filterCompletionTasks, object: nil)
            }
            .keyboardShortcut("3", modifiers: .command)
        }

        // View Menu (replace default)
        CommandGroup(replacing: .toolbar) {
            Button("Refresh") {
                NotificationCenter.default.post(name: .refreshTasks, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
