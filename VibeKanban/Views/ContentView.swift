import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext)
    private var modelContext

    @Query(sort: \KanbanItem.order)
    private var items: [KanbanItem]

    @AppStorage("baseWorkingDirectory")
    private var baseWorkingDirectory: String = ""

    @AppStorage("skipPermissions")
    private var skipPermissions: Bool = true

    @State private var selectedItem: KanbanItem?
    @State private var showingNewItemSheet = false
    @State private var terminalManager = TerminalSessionManager()
    @State private var selectedFilter: TaskStatus?
    @State private var searchText = ""
    @State private var isTerminalFullScreen = false
    @State private var isMultiTerminalMode = false

    var body: some View {
        Group {
            if isMultiTerminalMode {
                // Multi Terminal Mode: Full screen grid of all terminals
                MultiTerminalView(
                    items: currentRepositoryItems,
                    terminalManager: terminalManager,
                    skipPermissions: skipPermissions,
                    isMultiTerminalMode: $isMultiTerminalMode
                )
            } else {
                // Single Terminal Mode: HSplitView with Kanban + Terminal
                HSplitView {
                    // Left side: Kanban Board
                    if !isTerminalFullScreen {
                        KanbanBoardView(
                            items: items,
                            selectedItem: $selectedItem,
                            baseWorkingDirectory: $baseWorkingDirectory,
                            skipPermissions: $skipPermissions,
                            selectedFilter: $selectedFilter,
                            searchText: $searchText,
                            terminalManager: terminalManager,
                            onCreateItem: { showingNewItemSheet = true },
                            onDeleteItem: deleteItem,
                            onDeleteCompletedItems: deleteCompletedItems,
                            onMoveItem: moveItem,
                            onMultiTerminalMode: { isMultiTerminalMode = true }
                        )
                        .frame(minWidth: 500, idealWidth: 600)
                    }

                    // Right side: Terminal View (switches per kanban item)
                    if let item = selectedItem {
                        TerminalContainerView(
                            item: item,
                            terminalManager: terminalManager,
                            skipPermissions: skipPermissions,
                            isFullScreen: $isTerminalFullScreen
                        )
                        .id(item.id)
                        .frame(minWidth: 500)
                    } else {
                        EmptyTerminalView()
                            .frame(minWidth: 500)
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewItemSheet) {
            NewItemSheet(
                baseDirectory: baseWorkingDirectory,
                existingTasks: currentRepositoryItems
            ) { title, description, worktreePath in
                createItem(title: title, description: description, workingDirectory: worktreePath)
            }
        }
        .onAppear {
            NotificationManager.shared.requestAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationManager.taskSelectedNotification)) { notification in
            handleTaskSelectedNotification(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewTask)) { _ in
            showingNewItemSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectPreviousTask)) { _ in
            selectPreviousItem()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectNextTask)) { _ in
            selectNextItem()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterAllTasks)) { _ in
            selectedFilter = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterRunningTasks)) { _ in
            selectedFilter = .running
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterWaitingTasks)) { _ in
            selectedFilter = .waiting
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterCompletionTasks)) { _ in
            selectedFilter = .completion
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshTasks)) { _ in
            // Trigger UI refresh by toggling filter
            let current = selectedFilter
            selectedFilter = nil
            selectedFilter = current
        }
    }

    private func handleTaskSelectedNotification(_ notification: Notification) {
        guard let taskId = notification.userInfo?["taskId"] as? UUID else { return }

        // itemsから該当するタスクを検索して選択
        if let item = items.first(where: { $0.id == taskId }) {
            selectedItem = item

            // メインウィンドウを前面に持ってくる
            if let window = NSApplication.shared.windows.first(where: { $0.isMainWindow || $0.isKeyWindow }) {
                window.makeKeyAndOrderFront(nil)
            } else if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func createItem(title: String, description: String, workingDirectory: String) {
        let maxOrder = items.map(\.order).max() ?? -1
        let newItem = KanbanItem(
            title: title,
            itemDescription: description,
            order: maxOrder + 1,
            workingDirectory: workingDirectory
        )
        modelContext.insert(newItem)
        selectedItem = newItem
    }

    private func deleteItem(_ item: KanbanItem) {
        if selectedItem?.id == item.id {
            selectedItem = nil
        }
        terminalManager.terminateSession(for: item.id)

        // Remove git worktree
        let worktreePath = item.workingDirectory
        if !worktreePath.isEmpty && !baseWorkingDirectory.isEmpty {
            Task {
                await removeGitWorktree(at: baseWorkingDirectory, worktreePath: worktreePath)
            }
        }

        modelContext.delete(item)
    }

    private func deleteCompletedItems() {
        // 現在のリポジトリに紐づく完了タスクをフィルタ
        let worktreePrefix = "\(baseWorkingDirectory)-worktrees/"
        let completedItems = items.filter { item in
            item.status == .completion && item.workingDirectory.hasPrefix(worktreePrefix)
        }

        for item in completedItems {
            deleteItem(item)
        }
    }

    private func removeGitWorktree(at repoPath: String, worktreePath: String) async {
        // Get branch name from worktree path (last component)
        let branchName = URL(fileURLWithPath: worktreePath).lastPathComponent

        // Step 1: Remove worktree
        await runGitCommand(
            at: repoPath,
            arguments: ["worktree", "remove", "--force", worktreePath]
        )

        // Step 2: Prune worktrees
        await runGitCommand(
            at: repoPath,
            arguments: ["worktree", "prune"]
        )

        // Step 3: Delete branch
        await runGitCommand(
            at: repoPath,
            arguments: ["branch", "-D", branchName]
        )
    }

    private func runGitCommand(at repoPath: String, arguments: [String]) async {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

            process.terminationHandler = { _ in
                continuation.resume()
            }

            do {
                try process.run()
            } catch {
                continuation.resume()
            }
        }
    }

    private func moveItem(_ item: KanbanItem, to status: TaskStatus) {
        item.status = status
        item.updatedAt = Date()
    }

    private func selectPreviousItem() {
        let filteredItems = filteredItems
        guard !filteredItems.isEmpty else { return }

        if let current = selectedItem,
           let currentIndex = filteredItems.firstIndex(where: { $0.id == current.id }),
           currentIndex > 0 {
            selectedItem = filteredItems[currentIndex - 1]
        } else {
            selectedItem = filteredItems.last
        }
    }

    private func selectNextItem() {
        let filteredItems = filteredItems
        guard !filteredItems.isEmpty else { return }

        if let current = selectedItem,
           let currentIndex = filteredItems.firstIndex(where: { $0.id == current.id }),
           currentIndex < filteredItems.count - 1 {
            selectedItem = filteredItems[currentIndex + 1]
        } else {
            selectedItem = filteredItems.first
        }
    }

    private var filteredItems: [KanbanItem] {
        var result = items
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

    private var currentRepositoryItems: [KanbanItem] {
        guard !baseWorkingDirectory.isEmpty else { return [] }
        let worktreePrefix = "\(baseWorkingDirectory)-worktrees/"
        return items.filter { $0.workingDirectory.hasPrefix(worktreePrefix) }
    }
}

struct EmptyTerminalView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Select a task to view terminal")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Each task has its own terminal session with Claude Code")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct NewItemSheet: View {
    @Environment(\.dismiss)
    private var dismiss

    let baseDirectory: String
    let existingTasks: [KanbanItem]

    @State private var title = ""
    @State private var description = ""
    @State private var worktreeName = ""
    @State private var selectedParentTask: KanbanItem?
    @State private var isCreatingWorktree = false
    @State private var errorMessage: String?

    let onCreate: (String, String, String) -> Void

    private var parentTaskOptions: [KanbanItem] {
        existingTasks.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("New Task")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.headline)
                TextField("Task title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.headline)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $description)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                    if description.isEmpty {
                        Text("Claude Codeへの依頼内容を入力...")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.top, 1)
                            .padding(.leading, 6)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Parent Task (Optional)")
                    .font(.headline)
                Picker("", selection: $selectedParentTask) {
                    Text("None (create from main branch)").tag(nil as KanbanItem?)
                    ForEach(parentTaskOptions) { task in
                        Text(task.title).tag(task as KanbanItem?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                if let parent = selectedParentTask {
                    Text("Branch from: \(getBranchName(from: parent.workingDirectory))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Worktree Name")
                    .font(.headline)
                TextField("branch-name", text: $worktreeName)
                    .textFieldStyle(.roundedBorder)
                Text("Creates: \(worktreePath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    createWorktreeAndItem()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty || worktreeName.isEmpty || isCreatingWorktree)
            }
        }
        .padding(24)
        .frame(width: 550)
        .onChange(of: title) { oldValue, newValue in
            if worktreeName.isEmpty || worktreeName == sanitizeBranchName(oldValue) {
                worktreeName = sanitizeBranchName(newValue)
            }
        }
    }

    private func getBranchName(from worktreePath: String) -> String {
        URL(fileURLWithPath: worktreePath).lastPathComponent
    }

    private var worktreePath: String {
        let baseURL = URL(fileURLWithPath: baseDirectory)
        let parentDir = baseURL.deletingLastPathComponent().path
        let repoName = baseURL.lastPathComponent
        return "\(parentDir)/\(repoName)-worktrees/\(worktreeName)"
    }

    private func sanitizeBranchName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
    }

    private func createWorktreeAndItem() {
        isCreatingWorktree = true
        errorMessage = nil

        Task {
            do {
                let worktreeDir = worktreePath
                let baseBranch = selectedParentTask.map { getBranchName(from: $0.workingDirectory) }
                try await createGitWorktree(at: baseDirectory, name: worktreeName, path: worktreeDir, baseBranch: baseBranch)

                // Setup Claude Code hooks for the worktree
                ClaudeHooksManager.setupHooksForProject(at: worktreeDir)

                await MainActor.run {
                    onCreate(title, description, worktreeDir)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreatingWorktree = false
                }
            }
        }
    }

    private func createGitWorktree(at repoPath: String, name: String, path: String, baseBranch: String? = nil) async throws {
        // Create parent directory if needed
        let pathURL = URL(fileURLWithPath: path)
        let parentDir = pathURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Run git worktree add synchronously to avoid pipe issues
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")

        // If baseBranch is provided, create from that branch
        // git worktree add -b <new-branch> <path> <base-branch>
        if let baseBranch {
            process.arguments = ["worktree", "add", "-b", name, path, baseBranch]
        } else {
            process.arguments = ["worktree", "add", "-b", name, path]
        }
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        // Capture stderr but don't block on progress output
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        // Check if worktree was created successfully by verifying directory exists
        let worktreeExists = FileManager.default.fileExists(atPath: path)

        if !worktreeExists {
            // Only read error if worktree wasn't created
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Failed to create worktree"
            throw WorktreeError.gitError(errorString)
        }
    }
}

enum WorktreeError: LocalizedError {
    case gitError(String)

    var errorDescription: String? {
        switch self {
        case let .gitError(message):
            "Git error: \(message)"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: KanbanItem.self, inMemory: true)
}
