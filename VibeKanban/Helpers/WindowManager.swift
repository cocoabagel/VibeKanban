import AppKit
import SwiftUI

@MainActor
class WindowManager {
    static let shared = WindowManager()
    private var windows: [UUID: NSWindow] = [:]
    private var windowDelegates: [UUID: WindowDelegate] = [:]

    private init() {}

    func openGitDiffWindow(for item: KanbanItem) {
        // Check if window already exists
        if let existingWindow = windows[item.id] {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        // Create new window
        let contentView = GitDiffView(workingDirectory: item.workingDirectory)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Git Diff - \(item.title)"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false

        // Handle window close
        let itemId = item.id
        let delegate = WindowDelegate { [weak self] in
            self?.windows.removeValue(forKey: itemId)
            self?.windowDelegates.removeValue(forKey: itemId)
        }
        window.delegate = delegate
        windowDelegates[itemId] = delegate

        windows[item.id] = window
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Window Delegate

class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_: Notification) {
        onClose()
    }
}
