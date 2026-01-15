import Foundation

// MARK: - Git Models

struct GitFileChange: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let status: FileStatus
    let additions: Int
    let deletions: Int

    enum FileStatus: String {
        case added = "A"
        case modified = "M"
        case deleted = "D"
        case renamed = "R"
        case untracked = "?"

        var icon: String {
            switch self {
            case .added:
                "plus.circle.fill"

            case .modified:
                "pencil.circle.fill"

            case .deleted:
                "minus.circle.fill"

            case .renamed:
                "arrow.right.circle.fill"

            case .untracked:
                "questionmark.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .added:
                "green"

            case .modified:
                "blue"

            case .deleted:
                "red"

            case .renamed:
                "orange"

            case .untracked:
                "gray"
            }
        }
    }
}

struct GitDiffLine: Identifiable {
    let id = UUID()
    let content: String
    let type: LineType
    let oldLineNumber: Int?
    let newLineNumber: Int?

    enum LineType {
        case context
        case addition
        case deletion
        case header
        case hunkHeader
    }
}

struct GitFileDiff: Identifiable {
    let id = UUID()
    let path: String
    let lines: [GitDiffLine]
}

// MARK: - Git Service

@MainActor
class GitService: ObservableObject {
    @Published var changedFiles: [GitFileChange] = []
    @Published var selectedFileDiff: GitFileDiff?

    private let workingDirectory: String

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    func refresh() {
        changedFiles = fetchChangedFiles()
    }

    private func fetchChangedFiles() -> [GitFileChange] {
        // Get staged and unstaged changes
        let statusOutput = runGitCommand(["status", "--porcelain"])
        let diffStatOutput = runGitCommand(["diff", "--numstat", "HEAD"])

        var files: [GitFileChange] = []
        var statsMap: [String: (Int, Int)] = [:]

        // Parse numstat for additions/deletions
        for line in diffStatOutput.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 3 {
                let additions = Int(parts[0]) ?? 0
                let deletions = Int(parts[1]) ?? 0
                let path = parts[2]
                statsMap[path] = (additions, deletions)
            }
        }

        // Parse status
        for line in statusOutput.components(separatedBy: "\n") where !line.isEmpty {
            guard line.count >= 3 else { continue }

            let statusChar = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
            let path = String(line.dropFirst(3))

            let status: GitFileChange.FileStatus = switch statusChar {
            case "A", "??":
                statusChar == "??" ? .untracked : .added

            case "M", "MM", " M":
                .modified

            case "D", " D":
                .deleted

            case "R":
                .renamed

            default:
                .modified
            }

            let stats = statsMap[path] ?? (0, 0)
            files.append(GitFileChange(
                path: path,
                status: status,
                additions: stats.0,
                deletions: stats.1
            ))
        }

        return files
    }

    func fetchDiff(for file: GitFileChange) {
        let diffOutput = runGitCommand(["diff", "HEAD", "--", file.path])
        selectedFileDiff = parseDiff(output: diffOutput, path: file.path)
    }

    private func parseDiff(output: String, path: String) -> GitFileDiff {
        var lines: [GitDiffLine] = []
        var oldLineNum = 0
        var newLineNum = 0

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git") || line.hasPrefix("index ") ||
                line.hasPrefix("---") || line.hasPrefix("+++") {
                lines.append(GitDiffLine(
                    content: line,
                    type: .header,
                    oldLineNumber: nil,
                    newLineNumber: nil
                ))
            } else if line.hasPrefix("@@") {
                // Parse hunk header: @@ -start,count +start,count @@
                lines.append(GitDiffLine(
                    content: line,
                    type: .hunkHeader,
                    oldLineNumber: nil,
                    newLineNumber: nil
                ))

                // Extract line numbers from hunk header using proper regex capture groups
                // Format: @@ -oldStart,oldCount +newStart,newCount @@
                let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
                if
                    let regex = try? NSRegularExpression(pattern: pattern),
                    let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    if
                        let oldRange = Range(match.range(at: 1), in: line),
                        let newRange = Range(match.range(at: 2), in: line) {
                        oldLineNum = Int(line[oldRange]) ?? 0
                        newLineNum = Int(line[newRange]) ?? 0
                    }
                }
            } else if line.hasPrefix("+") {
                lines.append(GitDiffLine(
                    content: String(line.dropFirst()),
                    type: .addition,
                    oldLineNumber: nil,
                    newLineNumber: newLineNum
                ))
                newLineNum += 1
            } else if line.hasPrefix("-") {
                lines.append(GitDiffLine(
                    content: String(line.dropFirst()),
                    type: .deletion,
                    oldLineNumber: oldLineNum,
                    newLineNumber: nil
                ))
                oldLineNum += 1
            } else if line.hasPrefix(" ") || line.isEmpty {
                lines.append(GitDiffLine(
                    content: line.isEmpty ? "" : String(line.dropFirst()),
                    type: .context,
                    oldLineNumber: oldLineNum,
                    newLineNumber: newLineNum
                ))
                oldLineNum += 1
                newLineNum += 1
            }
        }

        return GitFileDiff(path: path, lines: lines)
    }

    private func runGitCommand(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
