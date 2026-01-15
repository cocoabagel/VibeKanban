import SwiftTerm
import SwiftUI
import UniformTypeIdentifiers

// MARK: - NSView Representable for SwiftTerm

struct TerminalNSViewRepresentable: NSViewRepresentable {
    let terminalView: LocalProcessTerminalView

    func makeNSView(context _: Context) -> TerminalDropTargetView {
        let containerView = TerminalDropTargetView(terminalView: terminalView)
        return containerView
    }

    func updateNSView(_: TerminalDropTargetView, context _: Context) {
        // Updates handled by the terminal itself
    }
}

// MARK: - Drop Target Container View

class TerminalDropTargetView: NSView {
    private let terminalView: LocalProcessTerminalView
    private var isDragging = false

    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        setupView()
        registerForDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func registerForDraggedTypes() {
        registerForDraggedTypes([
            .fileURL,
            .png,
            .tiff,
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        ])
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let dominated = isValidDrop(sender)
        if dominated {
            isDragging = true
            needsDisplay = true
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isValidDrop(sender) ? .copy : []
    }

    override func draggingExited(_: NSDraggingInfo?) {
        isDragging = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragging = false
        needsDisplay = true

        let pasteboard = sender.draggingPasteboard

        // Handle file URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL] {
            let imagePaths = urls
                .filter { isImageFile($0) }
                .map { escapePathForShell($0.path) }

            if !imagePaths.isEmpty {
                let pathString = imagePaths.joined(separator: " ")
                terminalView.send(txt: pathString)
                return true
            }
        }

        return false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw drop highlight
        if isDragging {
            NSColor.systemBlue.withAlphaComponent(0.2).setFill()
            dirtyRect.fill()

            NSColor.systemBlue.withAlphaComponent(0.6).setStroke()
            let borderRect = bounds.insetBy(dx: 2, dy: 2)
            let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 8, yRadius: 8)
            borderPath.lineWidth = 3
            borderPath.stroke()
        }
    }

    // MARK: - Helpers

    private func isValidDrop(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL] {
            return urls.contains { isImageFile($0) }
        }

        return false
    }

    private func isImageFile(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "heif"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    private func escapePathForShell(_ path: String) -> String {
        // Escape special characters for shell
        let specialChars = CharacterSet(charactersIn: " '\"\\$`!&()[]{}|;<>?*#~")
        if path.unicodeScalars.contains(where: { specialChars.contains($0) }) {
            // Use single quotes and escape any single quotes in the path
            let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        }
        return path
    }
}
