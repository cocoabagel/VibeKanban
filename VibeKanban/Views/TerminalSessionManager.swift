import Foundation

// MARK: - Terminal Session Manager

@MainActor
@Observable
class TerminalSessionManager {
    private var sessions: [UUID: TerminalSession] = [:]

    func getOrCreateSession(
        for itemId: UUID,
        workingDirectory: String,
        itemDescription: String,
        isFirstLaunch: Bool,
        skipPermissions: Bool = true,
        autoLaunchClaude: Bool = true,
        onClaudeLaunched: (() -> Void)? = nil,
        onStatusChange: ((TaskStatus) -> Void)? = nil
    ) -> TerminalSession {
        if let existing = sessions[itemId] {
            return existing
        }

        let session = TerminalSession(
            itemId: itemId,
            workingDirectory: workingDirectory,
            itemDescription: itemDescription,
            isFirstLaunch: isFirstLaunch,
            skipPermissions: skipPermissions,
            autoLaunchClaude: autoLaunchClaude
        )
        session.onClaudeLaunched = onClaudeLaunched
        session.onStatusChange = onStatusChange
        sessions[itemId] = session
        return session
    }

    func terminateSession(for itemId: UUID) {
        sessions[itemId]?.terminate()
        sessions.removeValue(forKey: itemId)
    }

    func getLatestResponse(for itemId: UUID) -> String {
        sessions[itemId]?.latestResponse ?? ""
    }
}
