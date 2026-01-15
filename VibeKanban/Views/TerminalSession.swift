import AppKit
import SwiftTerm

// MARK: - Terminal Session

@MainActor
class TerminalSession: ObservableObject {
    let terminal: LocalProcessTerminalView
    private var hasLaunchedClaudeInSession = false
    private let autoLaunchClaude: Bool
    private let workingDirectory: String
    private let itemId: UUID
    private let itemDescription: String
    private var isFirstLaunch: Bool
    private let skipPermissions: Bool
    var onClaudeLaunched: (() -> Void)?
    var onStatusChange: ((TaskStatus) -> Void)?

    // Status monitoring via file
    private let statusFilePath: String
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var currentStatus: TaskStatus = .idle

    // Latest response for display on card
    @Published var latestResponse: String = ""

    // Time-based idle detection
    private var statusCheckTimer: Timer?
    private var lastRunningTime = Date()

    init(
        itemId: UUID,
        workingDirectory: String,
        itemDescription: String,
        isFirstLaunch: Bool,
        skipPermissions: Bool = true,
        autoLaunchClaude: Bool = true
    ) {
        self.itemId = itemId
        self.autoLaunchClaude = autoLaunchClaude
        self.workingDirectory = workingDirectory
        self.itemDescription = itemDescription
        self.isFirstLaunch = isFirstLaunch
        self.skipPermissions = skipPermissions

        // Setup status file path
        let statusDir = "/tmp/vibekanban"
        statusFilePath = "\(statusDir)/\(itemId.uuidString).status"

        // Create status directory if needed
        try? FileManager.default.createDirectory(atPath: statusDir, withIntermediateDirectories: true)

        // Initialize status file with idle
        try? "idle".write(toFile: statusFilePath, atomically: true, encoding: .utf8)

        terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        setupTerminal()
        startShell()
        startFileMonitoring()
        startRunningDetection()
    }

    private func setupTerminal() {
        terminal.configureNativeColors()

        // Configure terminal appearance with Japanese-compatible font
        let fontSize: CGFloat = 14

        // Create font with Japanese fallback
        let baseFont = NSFontDescriptor(fontAttributes: [.name: "Menlo"])
        let japaneseFont = NSFontDescriptor(fontAttributes: [.name: "Hiragino Kaku Gothic ProN"])
        let cascadeDescriptor = baseFont.addingAttributes([
            .cascadeList: [japaneseFont]
        ])

        if let font = NSFont(descriptor: cascadeDescriptor, size: fontSize) {
            terminal.font = font
        } else {
            terminal.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }

        // Apply Tomorrow Night theme colors
        terminal.nativeForegroundColor = TerminalColors.foreground
        terminal.nativeBackgroundColor = TerminalColors.background

        // Set ANSI 16-color palette (Tomorrow Night theme)
        terminal.installColors(TerminalColors.ansiColors)
    }

    private func startShell() {
        // Get the user's default shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // Start the shell process
        terminal.startProcess(
            executable: shell,
            args: ["--login"],
            environment: buildEnvironment(),
            execName: nil
        )

        // Change to working directory and optionally launch claude
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            self.sendCommand("cd \"\(self.workingDirectory)\" && clear")

            if self.autoLaunchClaude && !self.hasLaunchedClaudeInSession {
                try? await Task.sleep(for: .milliseconds(300))
                self.launchClaude()
            }
        }
    }

    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        // Japanese locale support
        env["LANG"] = "ja_JP.UTF-8"
        env["LC_ALL"] = "ja_JP.UTF-8"
        env["LC_CTYPE"] = "ja_JP.UTF-8"
        // Pass status file path for Claude Code hooks
        env["VIBEKANBAN_STATUS_FILE"] = statusFilePath

        return env.map { "\($0.key)=\($0.value)" }
    }

    func launchClaude() {
        guard !hasLaunchedClaudeInSession else { return }
        hasLaunchedClaudeInSession = true

        let permissionsFlag = skipPermissions ? " --dangerously-skip-permissions" : ""

        if isFirstLaunch {
            // First launch: start new session with description as argument
            if !itemDescription.isEmpty {
                let escapedDescription = itemDescription
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                sendCommand("claude\(permissionsFlag) \"\(escapedDescription)\"")
            } else {
                sendCommand("claude\(permissionsFlag)")
            }
            isFirstLaunch = false
            onClaudeLaunched?()
        } else {
            // Subsequent launches: use --continue to restore session
            sendCommand("claude --continue\(permissionsFlag)")
        }
    }

    func sendCommand(_ command: String) {
        terminal.send(txt: command + "\r")
    }

    func terminate() {
        stopFileMonitoring()
        stopRunningDetection()
        // Clean up status file
        try? FileManager.default.removeItem(atPath: statusFilePath)
        sendCommand("exit")
    }

    // MARK: - File-based Status Monitoring

    private func startFileMonitoring() {
        // Open file descriptor for monitoring
        fileDescriptor = open(statusFilePath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }

        // Create dispatch source to monitor file changes
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.readStatusFile()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        source.resume()
        fileMonitor = source
    }

    private func stopFileMonitoring() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    private func readStatusFile() {
        guard let content = try? String(contentsOfFile: statusFilePath, encoding: .utf8) else {
            return
        }

        let statusString = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let fileStatus: TaskStatus
        switch statusString {
        case "running":
            fileStatus = .running
            lastRunningTime = Date()

        case "waiting":
            fileStatus = .waiting

        case "completion":
            fileStatus = .completion

        default:
            fileStatus = .idle
        }

        if fileStatus != currentStatus {
            currentStatus = fileStatus

            // Capture terminal output when status changes to waiting or completion
            if fileStatus == .waiting || fileStatus == .completion {
                captureLatestResponse()
            }

            onStatusChange?(fileStatus)
        }
    }

    // MARK: - Idle Detection

    private func startRunningDetection() {
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForIdle()
            }
        }
    }

    private func stopRunningDetection() {
        statusCheckTimer?.invalidate()
        statusCheckTimer = nil
    }

    private func checkForIdle() {
        // Read status file for hook updates
        readStatusFile()

        // If status is "running" but no update for 5+ seconds, switch to idle
        // This handles the case where Claude is thinking/typing (not using tools)
        if currentStatus == .running {
            let timeSinceLastRunning = Date().timeIntervalSince(lastRunningTime)
            if timeSinceLastRunning > 5.0 {
                currentStatus = .idle
                onStatusChange?(.idle)
                try? "idle".write(toFile: statusFilePath, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Public Status Control

    func setStatus(_ status: TaskStatus) {
        currentStatus = status
        onStatusChange?(status)
        try? status.rawValue.lowercased().write(toFile: statusFilePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Terminal Output Capture

    private func captureLatestResponse() {
        let terminalObj = terminal.getTerminal()

        // Get the full buffer content including scrollback
        let bufferData = terminalObj.getBufferAsData()
        guard let bufferString = String(data: bufferData, encoding: .utf8) else { return }

        // Split into lines and take the last 100 lines
        let allLines = bufferString.components(separatedBy: .newlines)
        let recentLines = Array(allLines.suffix(100))

        var lines: [String] = []
        for line in recentLines {
            let cleanedLine = stripControlCharacters(line)
            lines.append(cleanedLine)
        }

        // Find the last response block start (marked with ⏺ or similar bullet)
        var responseStartIndex: Int?
        for (index, line) in lines.enumerated().reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Claude's response blocks start with bullet points
            if trimmed.hasPrefix("⏺") || trimmed.hasPrefix("●") || trimmed.hasPrefix("◆") {
                responseStartIndex = index
                break
            }
        }

        // Find the question line (e.g., "Do you want to..." or lines ending with "?")
        var questionIndex: Int?
        for (index, line) in lines.enumerated().reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Do you want") ||
                trimmed.hasPrefix("Would you like") ||
                trimmed.hasPrefix("Are you sure") ||
                (trimmed.hasSuffix("?") && trimmed.count > 10) {
                questionIndex = index
                break
            }
        }

        if let qIndex = questionIndex {
            // Get question line and the next line (option 1)
            var result: [String] = []
            let questionLine = lines[qIndex].trimmingCharacters(in: .whitespaces)
            if !questionLine.isEmpty {
                result.append(questionLine)
            }
            // Add the first option line if available
            if qIndex + 1 < lines.count {
                let nextLine = lines[qIndex + 1].trimmingCharacters(in: .whitespaces)
                if !nextLine.isEmpty && (nextLine.hasPrefix("1.") || nextLine.hasPrefix(">") || nextLine.hasPrefix("Yes") || nextLine.hasPrefix("No")) {
                    result.append(nextLine)
                }
            }
            latestResponse = result.joined(separator: "\n")
        } else if let startIndex = responseStartIndex {
            // Get first 2 meaningful lines from the response block
            var result: [String] = []
            for i in startIndex ..< lines.count {
                let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                // Remove bullet point prefix for cleaner display
                var cleanLine = trimmed
                if cleanLine.hasPrefix("⏺") || cleanLine.hasPrefix("●") || cleanLine.hasPrefix("◆") {
                    cleanLine = String(cleanLine.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                if isMeaningfulLine(cleanLine) && !cleanLine.isEmpty {
                    result.append(cleanLine)
                    if result.count >= 2 {
                        break
                    }
                }
            }
            latestResponse = result.joined(separator: "\n")
        } else {
            // Fallback: filter and take last 2 meaningful lines
            let meaningfulLines = lines.filter { line in
                isMeaningfulLine(line)
            }
            let lastLines = meaningfulLines.suffix(2)
            latestResponse = lastLines.joined(separator: "\n")
        }
    }

    private func isMeaningfulLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Skip empty lines
        if trimmed.isEmpty { return false }

        // Skip shell prompts
        if trimmed.hasPrefix("$") || trimmed.hasPrefix("%") { return false }

        // Skip claude command lines
        if trimmed.contains("claude") && trimmed.contains("--") { return false }

        // Skip help text
        if trimmed.hasPrefix("Esc to") { return false }

        // Skip Claude Code status indicators
        if trimmed.contains("ctrl+c to interrupt") { return false }
        if trimmed.contains("tokens") && trimmed.contains("thinking") { return false }
        if trimmed.hasPrefix("- Booping") || trimmed.hasPrefix("+ Booping") { return false }
        if trimmed.hasPrefix("- Determining") || trimmed.hasPrefix("+ Determining") { return false }
        if trimmed.hasPrefix("- Processing") || trimmed.hasPrefix("+ Processing") { return false }
        if trimmed.hasPrefix("* Cooked") || trimmed.hasPrefix("* Brewed") || trimmed.hasPrefix("* Churned") { return false }

        // Skip bypass/accept prompts
        if trimmed.contains("bypass permissions") { return false }
        if trimmed.contains("accept edits") { return false }

        // Skip lines that are mostly box-drawing or special characters
        let alphanumericCount = trimmed.unicodeScalars.count { scalar in
            CharacterSet.alphanumerics.contains(scalar) ||
                scalar.value >= 0x3040 && scalar.value <= 0x9FFF // Japanese characters
        }

        // Require at least 30% meaningful characters
        if !trimmed.isEmpty && Double(alphanumericCount) / Double(trimmed.count) < 0.3 {
            return false
        }

        return true
    }

    private func stripControlCharacters(_ string: String) -> String {
        // Remove ANSI escape sequences
        var result = string.replacingOccurrences(
            of: "\\x1B\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
        // Remove other escape sequences
        result = result.replacingOccurrences(
            of: "\\x1B[\\(\\)][AB012]",
            with: "",
            options: .regularExpression
        )
        // Remove control characters (except newline and tab)
        result = result.unicodeScalars
            .filter { scalar in
                scalar.value >= 32 || scalar == "\n" || scalar == "\t"
            }
            .map { String($0) }
            .joined()

        return result.trimmingCharacters(in: .whitespaces)
    }
}
