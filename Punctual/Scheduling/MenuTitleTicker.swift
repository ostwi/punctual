import Foundation

/// Drives menu bar title updates with an adaptive one-shot timer:
/// fires at each minute boundary of the remaining time while more than a
/// minute is left, then every second for the final countdown.
@MainActor
final class MenuTitleTicker {
    var onTick: () -> Void = {}
    private var timer: Timer?

    /// `nextChange` is the moment the displayed state flips next
    /// (next meeting's start, or the current meeting's end).
    func rearm(nextChange: Date?) {
        timer?.invalidate()

        let interval: TimeInterval
        if let nextChange {
            let remaining = nextChange.timeIntervalSinceNow
            if remaining <= 0 {
                interval = 1
            } else if remaining <= 60 {
                interval = 1
            } else {
                // Fire when the whole-minute count changes; small bias avoids
                // landing a hair before the boundary.
                let toBoundary = remaining.truncatingRemainder(dividingBy: 60)
                interval = toBoundary < 0.5 ? toBoundary + 60 : toBoundary + 0.1
            }
        } else {
            interval = 60
        }

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.onTick()
            }
        }
        // .common mode keeps the countdown ticking while the dropdown is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
