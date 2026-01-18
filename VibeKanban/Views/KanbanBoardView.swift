import SwiftUI

// MARK: - Helper Functions

private func shortenedPath(_ fullPath: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if fullPath.hasPrefix(home) {
        return "~" + fullPath.dropFirst(home.count)
    }
    return fullPath
}

// MARK: - Session Monitor Colors

enum SessionMonitorColors {
    static let background = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let cardBackground = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let sidebarBackground = Color(red: 0.1, green: 0.11, blue: 0.13)
    static let cyan = Color(red: 0.0, green: 0.8, blue: 0.8)
    static let orange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let gray = Color(red: 0.4, green: 0.4, blue: 0.45)
    static let purple = Color(red: 0.7, green: 0.4, blue: 0.9)
}

// MARK: - Session Monitor View (Main)

struct KanbanBoardView: View {
    let items: [KanbanItem]
    @Binding var selectedItem: KanbanItem?
    @Binding var baseWorkingDirectory: String
    @Binding var skipPermissions: Bool
    @Binding var selectedFilter: TaskStatus?
    @Binding var searchText: String
    let terminalManager: TerminalSessionManager
    let onCreateItem: () -> Void
    let onDeleteItem: (KanbanItem) -> Void
    let onDeleteCompletedItems: () -> Void
    let onMoveItem: (KanbanItem, TaskStatus) -> Void

    /// リポジトリに紐づくタスクのみをフィルタリング
    private var repositoryFilteredItems: [KanbanItem] {
        guard !baseWorkingDirectory.isEmpty else { return items }
        let worktreePrefix = "\(baseWorkingDirectory)-worktrees/"
        return items.filter { $0.workingDirectory.hasPrefix(worktreePrefix) }
    }

    private var filteredItems: [KanbanItem] {
        var result = repositoryFilteredItems
        if let filter = selectedFilter {
            result = result.filter { $0.status == filter }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { item in
                item.title.lowercased().contains(query) ||
                    item.itemDescription.lowercased().contains(query)
            }
        }
        return result
    }

    private var waitingCount: Int {
        repositoryFilteredItems.count { $0.status == .waiting }
    }

    private var completionCount: Int {
        repositoryFilteredItems.count { $0.status == .completion }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            SessionSidebar(
                items: repositoryFilteredItems,
                selectedFilter: $selectedFilter,
                searchText: $searchText,
                baseWorkingDirectory: $baseWorkingDirectory,
                skipPermissions: $skipPermissions,
                onCreateItem: onCreateItem,
                onDeleteCompletedItems: onDeleteCompletedItems
            )

            Divider()
                .background(Color.white.opacity(0.1))

            // Main Content
            SessionGridView(
                items: filteredItems,
                selectedItem: $selectedItem,
                waitingCount: waitingCount,
                completionCount: completionCount,
                terminalManager: terminalManager,
                onDeleteItem: onDeleteItem,
                onMoveItem: onMoveItem
            )
        }
        .background(SessionMonitorColors.background)
    }
}

// MARK: - Session Sidebar

struct SessionSidebar: View {
    let items: [KanbanItem]
    @Binding var selectedFilter: TaskStatus?
    @Binding var searchText: String
    @Binding var baseWorkingDirectory: String
    @Binding var skipPermissions: Bool
    let onCreateItem: () -> Void
    let onDeleteCompletedItems: () -> Void

    @State private var showingDeleteConfirmation = false

    private func countForStatus(_ status: TaskStatus) -> Int {
        items.count { $0.status == status }
    }

    private var completedCount: Int {
        countForStatus(.completion)
    }

    private func colorForStatus(_ status: TaskStatus) -> Color {
        switch status {
        case .running:
            SessionMonitorColors.cyan

        case .waiting:
            SessionMonitorColors.orange

        case .idle:
            SessionMonitorColors.gray

        case .completion:
            SessionMonitorColors.purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleSection
            WorkingDirectorySelector(path: $baseWorkingDirectory)
            searchField
            statsSection
            settingsSection
            Spacer()
            deleteCompletedButton
            newSessionButton
        }
        .padding(20)
        .frame(width: 220)
        .background(SessionMonitorColors.sidebarBackground)
        .alert("完了タスクを削除", isPresented: $showingDeleteConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                onDeleteCompletedItems()
            }
        } message: {
            Text("\(completedCount)件の完了タスクを削除しますか？\nこの操作は取り消せません。")
        }
    }

    private var deleteCompletedButton: some View {
        Button {
            showingDeleteConfirmation = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Clear Completed")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(SessionMonitorColors.purple.opacity(0.2))
            .foregroundColor(SessionMonitorColors.purple)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(completedCount == 0)
        .opacity(completedCount == 0 ? 0.5 : 1.0)
    }

    private var titleSection: some View {
        Text("VibeKanban")
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(SessionMonitorColors.gray)
            TextField("Search tasks...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(SessionMonitorColors.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(SessionMonitorColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statsSection: some View {
        VStack(spacing: 8) {
            FilterableStatRow(
                value: items.count,
                label: "ALL SESSIONS",
                color: .white,
                isSelected: selectedFilter == nil
            ) {
                selectedFilter = nil
            }

            ForEach(TaskStatus.allCases.filter { $0 != .idle }) { status in
                FilterableStatRow(
                    value: countForStatus(status),
                    label: status.displayName,
                    color: colorForStatus(status),
                    isSelected: selectedFilter == status
                ) {
                    selectedFilter = status == selectedFilter ? nil : status
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $skipPermissions) {
                Text("Skip Permissions")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
            }
            .toggleStyle(.checkbox)
            .tint(SessionMonitorColors.cyan)

            Text("--dangerously-skip-permissions")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(SessionMonitorColors.gray)
        }
    }

    private var newSessionButton: some View {
        Button(action: onCreateItem) {
            HStack {
                Image(systemName: "plus")
                Text("New Session")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(SessionMonitorColors.cyan.opacity(0.2))
            .foregroundColor(SessionMonitorColors.cyan)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(baseWorkingDirectory.isEmpty)
        .opacity(baseWorkingDirectory.isEmpty ? 0.5 : 1.0)
    }
}

// MARK: - Filterable Stat Row

struct FilterableStatRow: View {
    let value: Int
    let label: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Spacer()
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? color : SessionMonitorColors.gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? color.opacity(0.15) : SessionMonitorColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? color : Color.clear, lineWidth: 1)
        )
        .onTapGesture {
            onTap()
        }
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Working Directory Selector

struct WorkingDirectorySelector: View {
    @Binding var path: String

    var body: some View {
        HStack(spacing: 8) {
            if path.isEmpty {
                Image(systemName: "folder.badge.plus")
                    .foregroundColor(SessionMonitorColors.orange)
                Text("Set Repository")
                    .foregroundColor(SessionMonitorColors.orange)
            } else {
                Image(systemName: "folder.fill")
                    .foregroundColor(SessionMonitorColors.cyan)
                Text(shortenedPath(path))
                    .lineLimit(1)
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SessionMonitorColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(path.isEmpty ? SessionMonitorColors.orange.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onTapGesture {
            selectDirectory()
        }
        .accessibilityAddTraits(.isButton)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select Git Repository"
        if !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }

        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

// MARK: - Session Grid View

struct SessionGridView: View {
    let items: [KanbanItem]
    @Binding var selectedItem: KanbanItem?
    let waitingCount: Int
    let completionCount: Int
    let terminalManager: TerminalSessionManager
    let onDeleteItem: (KanbanItem) -> Void
    let onMoveItem: (KanbanItem, TaskStatus) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Status Banners
            if completionCount > 0 {
                CompletionBanner(count: completionCount)
            }
            if waitingCount > 0 {
                WaitingBanner(count: waitingCount)
            }

            // Session Cards Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items.sorted { $0.updatedAt > $1.updatedAt }) { item in
                        SessionCardView(
                            item: item,
                            isSelected: selectedItem?.id == item.id,
                            latestResponse: item.latestResponse,
                            onSelect: { selectedItem = item },
                            onDelete: { onDeleteItem(item) },
                            onMove: { newStatus in onMoveItem(item, newStatus) }
                        )
                        .frame(maxWidth: 400)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 280, maxWidth: 350)
        .background(SessionMonitorColors.background)
    }
}

// MARK: - Completion Banner

struct CompletionBanner: View {
    let count: Int

    var body: some View {
        HStack {
            Spacer()
            Circle()
                .fill(SessionMonitorColors.purple)
                .frame(width: 8, height: 8)
            Text("\(count)件のセッションが完了しました")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(SessionMonitorColors.purple)
            Spacer()
        }
        .padding(.vertical, 12)
        .background(SessionMonitorColors.cardBackground)
    }
}

// MARK: - Waiting Banner

struct WaitingBanner: View {
    let count: Int

    var body: some View {
        HStack {
            Spacer()
            Circle()
                .fill(SessionMonitorColors.orange)
                .frame(width: 8, height: 8)
            Text("\(count)件のセッションが入力を待っています")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(SessionMonitorColors.orange)
            Spacer()
        }
        .padding(.vertical, 12)
        .background(SessionMonitorColors.cardBackground)
    }
}

// MARK: - Session Card View

struct SessionCardView: View {
    let item: KanbanItem
    let isSelected: Bool
    let latestResponse: String
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onMove: (TaskStatus) -> Void

    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var shouldShowResponse: Bool {
        (item.status == .waiting || item.status == .completion) && !latestResponse.isEmpty
    }

    /// currentTimeへの参照を含めることで、タイマー更新時にビューが再描画される
    private var elapsedTimeForDisplay: TimeInterval {
        _ = currentTime
        return item.currentElapsedTime
    }

    private var statusColor: Color {
        switch item.status {
        case .running:
            SessionMonitorColors.cyan

        case .waiting:
            SessionMonitorColors.orange

        case .idle:
            SessionMonitorColors.gray

        case .completion:
            SessionMonitorColors.purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title Row
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.white.opacity(0.6))
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                StatusBadge(status: item.status)
            }

            // Path
            Text(shortenedPath(item.workingDirectory))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)

            // Latest Response (only for waiting/completion)
            if shouldShowResponse {
                Text(latestResponse)
                    .font(.system(size: 11))
                    .foregroundColor(statusColor.opacity(0.9))
                    .lineLimit(2)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(statusColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Timer and Last Updated
            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(item.timerStartedAt != nil ? statusColor : .white.opacity(0.4))
                Text(formatElapsedTime(elapsedTimeForDisplay))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(item.timerStartedAt != nil ? statusColor : .white.opacity(0.4))
                Spacer()
                Text(relativeTimeString(from: item.updatedAt))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SessionMonitorColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ? statusColor : (item.status == .waiting ? SessionMonitorColors.orange.opacity(0.5) : Color.clear),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .overlay(
            // Left accent bar for waiting status
            HStack {
                if item.status == .waiting {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SessionMonitorColors.orange)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
                Spacer()
            }
            .padding(.leading, 4)
        )
        .onTapGesture {
            onSelect()
        }
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            contextMenuContent
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func relativeTimeString(from date: Date) -> String {
        let now = currentTime
        let interval = now.timeIntervalSince(date)

        if interval < 5 {
            return "たった今"
        } else if interval < 60 {
            return "\(Int(interval))秒前"
        } else if interval < 3_600 {
            let minutes = Int(interval / 60)
            return "\(minutes)分前"
        } else if interval < 86_400 {
            let hours = Int(interval / 3_600)
            return "\(hours)時間前"
        } else {
            let days = Int(interval / 86_400)
            return "\(days)日前"
        }
    }

    @ViewBuilder private var contextMenuContent: some View {
        ForEach(TaskStatus.allCases) { status in
            if status != item.status {
                Button {
                    onMove(status)
                } label: {
                    Label("Set \(status.displayName)", systemImage: status.icon)
                }
            }
        }
        Divider()
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: TaskStatus

    private var backgroundColor: Color {
        switch status {
        case .running:
            SessionMonitorColors.cyan.opacity(0.2)

        case .waiting:
            SessionMonitorColors.orange.opacity(0.2)

        case .idle:
            SessionMonitorColors.gray.opacity(0.2)

        case .completion:
            SessionMonitorColors.purple.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .running:
            SessionMonitorColors.cyan

        case .waiting:
            SessionMonitorColors.orange

        case .idle:
            SessionMonitorColors.gray

        case .completion:
            SessionMonitorColors.purple
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if status == .running {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 9))
            }
            Text(status.displayName)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
