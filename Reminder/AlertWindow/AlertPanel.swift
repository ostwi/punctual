import AppKit

/// Borderless full-screen panel that floats above everything, including
/// other apps' full-screen Spaces.
final class AlertPanel: NSPanel {
    // Borderless windows refuse key status by default; we need it for the buttons.
    override var canBecomeKey: Bool { true }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .alertPanel
    }
}
