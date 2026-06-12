import AppKit
import Foundation

/// Triggers calendar refreshes: every 60 seconds and on wake from sleep.
@MainActor
final class RefreshCoordinator {
    var onRefresh: () async -> Void = {}
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            Task { @MainActor [weak self] in
                await self?.onRefresh()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.onRefresh()
            }
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }
}
