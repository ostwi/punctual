import AppKit
import SwiftUI
import Observation

/// The set of meetings currently demanding attention; shared by the
/// scheduler (writer) and every alert panel's SwiftUI view (readers).
@MainActor
@Observable
final class AlertPresentation {
    var meetings: [Meeting] = []
}

/// Presents one full-screen AlertPanel per display so a meeting can't
/// start unseen on a secondary monitor.
@MainActor
final class AlertWindowController {
    private let presentation: AlertPresentation
    private let onJoin: (Meeting) -> Void
    private let onSnooze: (Meeting) -> Void
    private let onDismiss: (Meeting) -> Void

    private var panels: [AlertPanel] = []
    private var screenObserver: NSObjectProtocol?

    init(
        presentation: AlertPresentation,
        onJoin: @escaping (Meeting) -> Void,
        onSnooze: @escaping (Meeting) -> Void,
        onDismiss: @escaping (Meeting) -> Void
    ) {
        self.presentation = presentation
        self.onJoin = onJoin
        self.onSnooze = onSnooze
        self.onDismiss = onDismiss
    }

    var isVisible: Bool { !panels.isEmpty }

    func show() {
        guard panels.isEmpty else { return }
        buildPanels()
        NSSound(named: "Glass")?.play()
        NSApp.activate(ignoringOtherApps: true)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isVisible else { return }
                self.tearDownPanels()
                self.buildPanels()
            }
        }
    }

    func close() {
        guard !panels.isEmpty else { return }
        tearDownPanels()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func buildPanels() {
        for screen in NSScreen.screens {
            let panel = AlertPanel(screen: screen)
            let view = AlertView(
                presentation: presentation,
                onJoin: onJoin,
                onSnooze: onSnooze,
                onDismiss: onDismiss
            )
            panel.contentView = NSHostingView(rootView: view)
            panel.setFrame(screen.frame, display: true)
            panel.makeKeyAndOrderFront(nil)
            panels.append(panel)
        }
    }

    private func tearDownPanels() {
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
    }
}
