import SwiftUI

// MARK: - Multi Terminal View

struct MultiTerminalView: View {
    let items: [KanbanItem]
    let terminalManager: TerminalSessionManager
    let skipPermissions: Bool
    @Binding var isMultiTerminalMode: Bool

    private let minTerminalWidth: CGFloat = 400
    private let minTerminalHeight: CGFloat = 300

    var body: some View {
        GeometryReader { geometry in
            let columns = calculateColumns(for: geometry.size.width, itemCount: items.count)
            let rows = (items.count + columns - 1) / columns

            VStack(spacing: 0) {
                // Header
                multiTerminalHeader(columns: columns)
                Divider()

                // Terminal Grid
                if items.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: columns),
                            spacing: 1
                        ) {
                            ForEach(items) { item in
                                MultiTerminalCell(
                                    item: item,
                                    terminalManager: terminalManager,
                                    skipPermissions: skipPermissions
                                )
                                .frame(minHeight: calculateCellHeight(
                                    totalHeight: geometry.size.height - 50,
                                    rows: rows
                                ))
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func multiTerminalHeader(columns: Int) -> some View {
        HStack {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 16))
            Text("Multi Terminal")
                .font(.headline)
            Text("(\(items.count) sessions)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text("\(columns) columns")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                isMultiTerminalMode = false
            } label: {
                Image(systemName: "rectangle.arrowtriangle.2.inward")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .help("シングルターミナルモードに戻す")
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No tasks available")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Create a new task to see terminals here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func calculateColumns(for width: CGFloat, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 1 }

        let maxColumns = max(1, Int(width / minTerminalWidth))

        // Optimize layout based on item count
        switch itemCount {
        case 1:
            return 1

        case 2:
            return min(2, maxColumns)

        case 3, 4:
            return min(2, maxColumns)

        case 5, 6:
            return min(3, maxColumns)

        default:
            return min(3, maxColumns)
        }
    }

    private func calculateCellHeight(totalHeight: CGFloat, rows: Int) -> CGFloat {
        let height = (totalHeight - CGFloat(rows - 1)) / CGFloat(rows)
        return max(minTerminalHeight, height)
    }
}

// MARK: - Multi Terminal Cell

struct MultiTerminalCell: View {
    @Bindable var item: KanbanItem
    let terminalManager: TerminalSessionManager
    let skipPermissions: Bool

    @State private var session: TerminalSession?

    var body: some View {
        VStack(spacing: 0) {
            cellHeader
            Divider()
            terminalContent
        }
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(statusBorderColor, lineWidth: 2)
        )
        .onAppear {
            initializeSession()
        }
    }

    private var cellHeader: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer()

            Text(item.status.displayName)
                .font(.system(size: 10))
                .foregroundColor(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.workingDirectory)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Finderで開く")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder private var terminalContent: some View {
        if let session {
            TerminalNSViewRepresentable(terminalView: session.terminal)
                .background(Color(TerminalColors.background))
        } else {
            ProgressView("Starting...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(TerminalColors.background))
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .running:
            Color(hex: "#00CCCC")

        case .waiting:
            Color(hex: "#FF9933")

        case .idle:
            Color(hex: "#666666")

        case .completion:
            Color(hex: "#B366E6")
        }
    }

    private var statusBorderColor: Color {
        switch item.status {
        case .running:
            Color(hex: "#00CCCC").opacity(0.5)

        case .waiting:
            Color(hex: "#FF9933").opacity(0.5)

        case .idle:
            Color.clear

        case .completion:
            Color(hex: "#B366E6").opacity(0.3)
        }
    }

    private func initializeSession() {
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

                if newStatus != previousStatus {
                    if newStatus == .running {
                        item.startTimer()
                    } else if newStatus == .waiting || newStatus == .completion {
                        item.stopTimer()
                    }
                }

                if newStatus != previousStatus && (newStatus == .waiting || newStatus == .completion) {
                    let message = terminalManager?.getLatestResponse(for: item.id) ?? ""
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

// MARK: - Color Extension

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)

        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)

        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)

        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
