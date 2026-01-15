import SwiftUI

// MARK: - Git Diff Colors (Tomorrow Night Theme)

enum GitDiffColors {
    // Tomorrow Night base colors
    static let background = Color(hex: 0x1D1F21)
    static let foreground = Color(hex: 0xC5C8C6)
    static let lineBackground = Color(hex: 0x282A2E)
    static let selection = Color(hex: 0x373B41)
    static let comment = Color(hex: 0x969896)

    // Diff specific colors
    static let additionBackground = Color(hex: 0x2A3D2A)  // Darker green background
    static let additionText = Color(hex: 0xB5BD68)        // Tomorrow Night green
    static let deletionBackground = Color(hex: 0x3D2A2A)  // Darker red background
    static let deletionText = Color(hex: 0xCC6666)        // Tomorrow Night red
    static let headerBackground = Color(hex: 0x282A2E)    // Line color
    static let hunkHeaderBackground = Color(hex: 0x373B41) // Selection color
    static let headerText = Color(hex: 0x8ABEB7)          // Tomorrow Night aqua
    static let lineNumberColor = Color(hex: 0x969896)     // Comment color
}

extension Color {
    init(hex: Int) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

// MARK: - Main Git Diff View

struct GitDiffView: View {
    @StateObject private var gitService: GitService
    @State private var selectedFile: GitFileChange?
    @State private var selectedIndex: Int = 0

    init(workingDirectory: String) {
        _gitService = StateObject(wrappedValue: GitService(workingDirectory: workingDirectory))
    }

    var body: some View {
        HSplitView {
            // File List
            FileListView(
                files: gitService.changedFiles,
                selectedFile: $selectedFile,
                selectedIndex: $selectedIndex
            )
            .frame(minWidth: 200, maxWidth: 300)

            // Diff View
            if let diff = gitService.selectedFileDiff {
                DiffContentView(diff: diff)
            } else {
                EmptyDiffView()
            }
        }
        .task {
            gitService.refresh()
        }
        .onChange(of: selectedFile) { _, newValue in
            if let file = newValue {
                gitService.fetchDiff(for: file)
            }
        }
        .onChange(of: gitService.changedFiles) { _, files in
            // Auto-select first file when loaded
            if selectedFile == nil && !files.isEmpty {
                selectedFile = files[0]
                selectedIndex = 0
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    gitService.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("更新")
            }
        }
    }
}

// MARK: - File List View

struct FileListView: View {
    let files: [GitFileChange]
    @Binding var selectedFile: GitFileChange?
    @Binding var selectedIndex: Int

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("変更ファイル")
                    .font(.headline)
                Spacer()
                Text("\(files.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding()
            .background(GitDiffColors.lineBackground)

            Divider()

            if files.isEmpty {
                Spacer()
                Text("変更なし")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            FileRowView(
                                file: file,
                                isSelected: selectedIndex == index
                            )
                            .accessibilityAddTraits(.isButton)
                            .onTapGesture {
                                selectedIndex = index
                                selectedFile = file
                            }
                        }
                    }
                }
            }
        }
        .background(GitDiffColors.background)
    }
}

// MARK: - File Row View

struct FileRowView: View {
    let file: GitFileChange
    let isSelected: Bool

    private var statusColor: Color {
        switch file.status {
        case .added:
            GitDiffColors.additionText

        case .modified:
            Color(hex: 0x81A2BE)  // Tomorrow Night blue

        case .deleted:
            GitDiffColors.deletionText

        case .renamed:
            Color(hex: 0xDE935F)  // Tomorrow Night orange

        case .untracked:
            GitDiffColors.comment
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.status.icon)
                .foregroundColor(statusColor)
                .font(.system(size: 12))

            Text(file.path)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if file.additions > 0 {
                Text("+\(file.additions)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(GitDiffColors.additionText)
            }
            if file.deletions > 0 {
                Text("-\(file.deletions)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(GitDiffColors.deletionText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? statusColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Diff Content View

struct DiffContentView: View {
    let diff: GitFileDiff

    var body: some View {
        VStack(spacing: 0) {
            // File Header
            HStack {
                Image(systemName: "doc.text")
                Text(diff.path)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()

                // Copy all button
                Button {
                    copyDiffToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Diffをコピー")
            }
            .padding()
            .background(GitDiffColors.headerBackground)

            Divider()

            // Diff Lines with selectable text
            SelectableDiffTextView(lines: diff.lines)
        }
        .background(GitDiffColors.background)
    }

    private func copyDiffToClipboard() {
        let text = diff.lines.map { line in
            let prefix = switch line.type {
            case .addition:
                "+"

            case .deletion:
                "-"

            case .context:
                " "

            case .header, .hunkHeader:
                ""
            }
            return prefix + line.content
        }
        .joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Selectable Diff Text View (NSViewRepresentable)

struct SelectableDiffTextView: NSViewRepresentable {
    let lines: [GitDiffLine]

    func makeNSView(context _: Context) -> NSView {
        let containerView = DiffContainerView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(red: 0x1D / 255.0, green: 0x1F / 255.0, blue: 0x21 / 255.0, alpha: 1.0).cgColor
        return containerView
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        guard let containerView = nsView as? DiffContainerView else { return }
        containerView.updateContent(lines: lines)
    }
}

// MARK: - Diff Container View (Custom NSView with line numbers and content)

@MainActor
class DiffContainerView: NSView {
    private var lineNumbersScrollView: NSScrollView?
    private var lineNumbersView: NSTextView?
    private var contentScrollView: NSScrollView?
    private var contentTextView: NSTextView?
    nonisolated(unsafe) private var scrollObserver: NSObjectProtocol?
    private var isSyncing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        let inset = NSSize(width: 4, height: 8)

        // Tomorrow Night colors
        let lineNumBgColor = NSColor(red: 0x16 / 255.0, green: 0x18 / 255.0, blue: 0x1A / 255.0, alpha: 1.0)
        let mainBgColor = NSColor(red: 0x1D / 255.0, green: 0x1F / 255.0, blue: 0x21 / 255.0, alpha: 1.0)

        // Line numbers scroll view
        let numScrollView = NSScrollView(frame: .zero)
        numScrollView.hasVerticalScroller = false
        numScrollView.hasHorizontalScroller = false
        numScrollView.backgroundColor = lineNumBgColor
        numScrollView.drawsBackground = true
        numScrollView.translatesAutoresizingMaskIntoConstraints = false

        let numTextView = NSTextView(frame: .zero)
        numTextView.isEditable = false
        numTextView.isSelectable = false
        numTextView.backgroundColor = lineNumBgColor
        numTextView.textContainerInset = inset
        numTextView.isRichText = true
        numTextView.drawsBackground = true
        numTextView.isVerticallyResizable = true
        numTextView.textContainer?.widthTracksTextView = true

        numScrollView.documentView = numTextView

        // Content scroll view with text view
        let contScrollView = NSScrollView(frame: .zero)
        contScrollView.hasVerticalScroller = true
        contScrollView.hasHorizontalScroller = true
        contScrollView.autohidesScrollers = false
        contScrollView.backgroundColor = mainBgColor
        contScrollView.drawsBackground = true
        contScrollView.translatesAutoresizingMaskIntoConstraints = false

        let contTextView = NSTextView(frame: .zero)
        contTextView.isEditable = false
        contTextView.isSelectable = true
        contTextView.backgroundColor = mainBgColor
        contTextView.textContainerInset = inset
        contTextView.isRichText = true
        contTextView.drawsBackground = true
        contTextView.allowsUndo = false
        contTextView.isAutomaticQuoteSubstitutionEnabled = false
        contTextView.isAutomaticDashSubstitutionEnabled = false
        contTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        contTextView.textColor = NSColor(red: 0xC5 / 255.0, green: 0xC8 / 255.0, blue: 0xC6 / 255.0, alpha: 1.0)
        contTextView.isHorizontallyResizable = true
        contTextView.isVerticallyResizable = true
        contTextView.textContainer?.widthTracksTextView = false
        contTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        contTextView.minSize = NSSize(width: 0, height: 0)
        contTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        contScrollView.documentView = contTextView

        addSubview(numScrollView)
        addSubview(contScrollView)

        NSLayoutConstraint.activate([
            numScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            numScrollView.topAnchor.constraint(equalTo: topAnchor),
            numScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            numScrollView.widthAnchor.constraint(equalToConstant: 100),

            contScrollView.leadingAnchor.constraint(equalTo: numScrollView.trailingAnchor),
            contScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contScrollView.topAnchor.constraint(equalTo: topAnchor),
            contScrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Sync scrolling from content to line numbers
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contScrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncLineNumbersScroll()
            }
        }
        contScrollView.contentView.postsBoundsChangedNotifications = true

        // Assign to properties
        lineNumbersScrollView = numScrollView
        lineNumbersView = numTextView
        contentScrollView = contScrollView
        contentTextView = contTextView
    }

    deinit {
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func syncLineNumbersScroll() {
        guard
            !isSyncing,
            let contScrollView = contentScrollView,
            let numScrollView = lineNumbersScrollView
        else { return }
        isSyncing = true
        let yOffset = contScrollView.contentView.bounds.origin.y
        numScrollView.contentView.scroll(to: NSPoint(x: 0, y: yOffset))
        isSyncing = false
    }

    func updateContent(lines: [GitDiffLine]) {
        let (lineNumbersAttr, contentAttr) = buildAttributedStrings(lines: lines)
        lineNumbersView?.textStorage?.setAttributedString(lineNumbersAttr)
        contentTextView?.textStorage?.setAttributedString(contentAttr)
    }

    private func buildAttributedStrings(lines: [GitDiffLine]) -> (NSAttributedString, NSAttributedString) {
        let lineNumbersString = NSMutableAttributedString()
        let contentString = NSMutableAttributedString()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.minimumLineHeight = 16
        paragraphStyle.maximumLineHeight = 16

        // Use same font for both to ensure line heights match
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        // Tomorrow Night colors
        let lineNumColor = NSColor(red: 0x96 / 255.0, green: 0x98 / 255.0, blue: 0x96 / 255.0, alpha: 1.0)
        let deletionColor = NSColor(red: 0xCC / 255.0, green: 0x66 / 255.0, blue: 0x66 / 255.0, alpha: 1.0)
        let additionColor = NSColor(red: 0xB5 / 255.0, green: 0xBD / 255.0, blue: 0x68 / 255.0, alpha: 1.0)

        for line in lines {
            // Line numbers (for non-header lines)
            if line.type == .header || line.type == .hunkHeader {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: lineNumColor,
                    .paragraphStyle: paragraphStyle
                ]
                lineNumbersString.append(NSAttributedString(string: "\n", attributes: attrs))
            } else {
                // Format: [left 5 chars] [right 5 chars] + newline
                // Left column: old line number (with - for deletion, space for context)
                // Right column: new line number (with + for addition, space for context)
                switch line.type {
                case .deletion:
                    // Deletion: "-oldNum" in left column, empty right column
                    let oldNum = line.oldLineNumber.map { String(format: "%4d", $0) } ?? "    "
                    let leftAttrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: deletionColor,
                        .paragraphStyle: paragraphStyle
                    ]
                    let rightAttrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: lineNumColor,
                        .paragraphStyle: paragraphStyle
                    ]
                    lineNumbersString.append(NSAttributedString(string: "-\(oldNum)", attributes: leftAttrs))
                    lineNumbersString.append(NSAttributedString(string: "      \n", attributes: rightAttrs))

                case .addition:
                    // Addition: empty left column, "+newNum" in right column
                    let newNum = line.newLineNumber.map { String(format: "%4d", $0) } ?? "    "
                    let leftAttrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: lineNumColor,
                        .paragraphStyle: paragraphStyle
                    ]
                    let rightAttrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: additionColor,
                        .paragraphStyle: paragraphStyle
                    ]
                    lineNumbersString.append(NSAttributedString(string: "      ", attributes: leftAttrs))
                    lineNumbersString.append(NSAttributedString(string: "+\(newNum)\n", attributes: rightAttrs))

                default:
                    // Context: both line numbers with space prefix
                    let oldNum = line.oldLineNumber.map { String(format: "%4d", $0) } ?? "    "
                    let newNum = line.newLineNumber.map { String(format: "%4d", $0) } ?? "    "
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: lineNumColor,
                        .paragraphStyle: paragraphStyle
                    ]
                    lineNumbersString.append(NSAttributedString(string: " \(oldNum)  \(newNum)\n", attributes: attrs))
                }
            }

            // Content - Tomorrow Night theme colors
            let prefix: String
            let textColor: NSColor
            let backgroundColor: NSColor

            switch line.type {
            case .addition:
                prefix = "+ "
                textColor = NSColor(red: 0xB5 / 255.0, green: 0xBD / 255.0, blue: 0x68 / 255.0, alpha: 1.0)
                backgroundColor = NSColor(red: 0x2A / 255.0, green: 0x3D / 255.0, blue: 0x2A / 255.0, alpha: 1.0)

            case .deletion:
                prefix = "- "
                textColor = NSColor(red: 0xCC / 255.0, green: 0x66 / 255.0, blue: 0x66 / 255.0, alpha: 1.0)
                backgroundColor = NSColor(red: 0x3D / 255.0, green: 0x2A / 255.0, blue: 0x2A / 255.0, alpha: 1.0)

            case .context:
                prefix = "  "
                textColor = NSColor(red: 0xC5 / 255.0, green: 0xC8 / 255.0, blue: 0xC6 / 255.0, alpha: 0.8)
                backgroundColor = NSColor.clear

            case .header:
                prefix = ""
                textColor = NSColor(red: 0x8A / 255.0, green: 0xBE / 255.0, blue: 0xB7 / 255.0, alpha: 1.0)
                backgroundColor = NSColor(red: 0x28 / 255.0, green: 0x2A / 255.0, blue: 0x2E / 255.0, alpha: 1.0)

            case .hunkHeader:
                prefix = ""
                textColor = NSColor(red: 0x8A / 255.0, green: 0xBE / 255.0, blue: 0xB7 / 255.0, alpha: 1.0)
                backgroundColor = NSColor(red: 0x37 / 255.0, green: 0x3B / 255.0, blue: 0x41 / 255.0, alpha: 1.0)
            }

            let contentText = "\(prefix)\(line.content)\n"
            let contentAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .backgroundColor: backgroundColor,
                .paragraphStyle: paragraphStyle
            ]

            contentString.append(NSAttributedString(string: contentText, attributes: contentAttrs))
        }

        return (lineNumbersString, contentString)
    }
}

// MARK: - Empty Diff View

struct EmptyDiffView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(GitDiffColors.comment)
            Text("ファイルを選択してください")
                .foregroundColor(GitDiffColors.comment)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GitDiffColors.background)
    }
}

#Preview {
    GitDiffView(workingDirectory: "/tmp")
        .frame(width: 800, height: 600)
}
