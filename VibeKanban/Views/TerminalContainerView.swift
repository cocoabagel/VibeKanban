import SwiftUI

// MARK: - Terminal Container View

struct TerminalContainerView: View {
    @Bindable var item: KanbanItem
    let terminalManager: TerminalSessionManager
    let skipPermissions: Bool

    @State private var session: TerminalSession?
    @State private var currentItemId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider()
            terminalContent
        }
        .onAppear {
            switchToItem()
        }
        .onChange(of: item.id) { _, _ in
            switchToItem()
        }
    }

    private var terminalHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                Text(item.workingDirectory)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                WindowManager.shared.openGitDiffWindow(for: item)
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .help("Git Diffを開く")

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.workingDirectory)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .help("Finderで開く")
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder private var terminalContent: some View {
        if let session {
            TerminalNSViewRepresentable(terminalView: session.terminal)
                .background(Color(TerminalColors.background))
                .id(currentItemId)
        } else {
            ProgressView("Starting terminal...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func switchToItem() {
        currentItemId = item.id
        let newSession = terminalManager.getOrCreateSession(
            for: item.id,
            workingDirectory: item.workingDirectory,
            itemDescription: item.itemDescription,
            isFirstLaunch: !item.hasLaunchedClaudeOnce,
            skipPermissions: skipPermissions,
            onClaudeLaunched: {
                item.hasLaunchedClaudeOnce = true
            },
            onStatusChange: { [weak terminalManager] newStatus in
                let previousStatus = item.status
                item.status = newStatus
                item.updatedAt = Date()

                // タイマー制御: running → タイマー開始, waiting/completion → タイマー停止
                if newStatus != previousStatus {
                    if newStatus == .running {
                        item.startTimer()
                    } else if newStatus == .waiting || newStatus == .completion {
                        item.stopTimer()
                    }
                }

                // WAITINGまたはCOMPLETIONに変わったときに通知とレスポンス保存
                if newStatus != previousStatus && (newStatus == .waiting || newStatus == .completion) {
                    let message = terminalManager?.getLatestResponse(for: item.id) ?? ""
                    // Save to item for persistence
                    item.latestResponse = message
                    NotificationManager.shared.sendStatusNotification(
                        taskId: item.id,
                        taskTitle: item.title,
                        status: newStatus,
                        message: message
                    )
                }
            }
        )
        session = newSession
    }
}
