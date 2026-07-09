import AppKit
import Foundation

/// What the scheduler needs from the alert UI; lets tests substitute a spy
/// for the real per-display NSPanel controller.
@MainActor
protocol AlertPresenting: AnyObject {
    func show()
    func close()
}

/// State machine for full-screen meeting alerts.
///
/// One wall-clock timer is always aimed at the earliest pending fire date;
/// `reconcile(meetings:)` recomputes everything and is called on every poll,
/// wake, settings change, snooze, and dismiss — so the timer can never go stale.
@MainActor
final class AlertScheduler {
    /// Includes the start date so a rescheduled event gets a fresh key
    /// (and therefore alerts again even if its old slot was dismissed).
    struct AlertKey: Hashable {
        let eventID: String
        let start: Date
    }

    private enum State {
        case pending
        case snoozed(until: Date)
        case showing
        case dismissed
    }

    /// If the Mac was asleep at fire time, still alert up to this long after
    /// the meeting started; beyond it, skip silently.
    private static let lateGracePeriod: TimeInterval = 180
    private static let snoozeInterval: TimeInterval = 60

    var onJoin: (Meeting) -> Void = { _ in }
    var leadTime: TimeInterval = AppSettings.alertLeadTime

    /// The meetings currently showing full-screen; observed by the alert views.
    let presentation = AlertPresentation()

    private let now: () -> Date
    private let injectedPresenter: AlertPresenting?
    private var states: [AlertKey: State] = [:]
    private var meetingsByKey: [AlertKey: Meeting] = [:]
    private var timer: DispatchSourceTimer?
    private lazy var windowController: AlertPresenting = injectedPresenter
        ?? AlertWindowController(
            presentation: presentation,
            onJoin: { [weak self] in self?.join($0) },
            onSnooze: { [weak self] in self?.snooze($0) },
            onDismiss: { [weak self] in self?.dismiss($0) }
        )

    /// `now` and `presenter` are injection points for tests; production uses
    /// the wall clock and the real window controller.
    init(now: @escaping () -> Date = Date.init, presenter: AlertPresenting? = nil) {
        self.now = now
        self.injectedPresenter = presenter
    }

    // MARK: - Reconciliation

    func reconcile(meetings: [Meeting]) {
        let currentKeys = Set(meetings.map { AlertKey(eventID: $0.id, start: $0.start) })

        // Prune cancelled/rescheduled events; close their cards if showing.
        for key in states.keys where !currentKeys.contains(key) {
            states.removeValue(forKey: key)
            meetingsByKey.removeValue(forKey: key)
        }

        for meeting in meetings {
            let key = AlertKey(eventID: meeting.id, start: meeting.start)
            meetingsByKey[key] = meeting
            if states[key] == nil {
                states[key] = .pending
            }
        }

        fireDueAlerts()
    }

    // MARK: - Timer

    private func fireDate(for key: AlertKey) -> Date? {
        switch states[key] {
        case .pending:
            return key.start.addingTimeInterval(-leadTime)
        case .snoozed(let until):
            return until
        case .showing, .dismissed, nil:
            return nil
        }
    }

    private func rearmTimer() {
        timer?.cancel()
        timer = nil

        let nextFire = states.keys.compactMap(fireDate(for:)).min()
        guard let nextFire else { return }

        let source = DispatchSource.makeTimerSource(queue: .main)
        // Wall deadline: an absolute moment, unaffected by the Mac sleeping.
        source.schedule(wallDeadline: .now() + max(nextFire.timeIntervalSince(now()), 0))
        source.setEventHandler { [weak self] in
            self?.fireDueAlerts()
        }
        source.resume()
        timer = source
    }

    private func fireDueAlerts() {
        let now = now()
        for (key, _) in states {
            guard let fireDate = fireDate(for: key), fireDate <= now else { continue }
            let lateLimit = key.start.addingTimeInterval(Self.lateGracePeriod)
            if now <= lateLimit {
                states[key] = .showing
            } else {
                states[key] = .dismissed  // long over; don't ambush with a stale alert
            }
        }
        updatePresentation()
        rearmTimer()
    }

    private func updatePresentation() {
        let showing = states
            .filter { if case .showing = $0.value { true } else { false } }
            .keys
            .compactMap { meetingsByKey[$0] }
            .sorted { $0.start < $1.start }

        presentation.meetings = showing
        if showing.isEmpty {
            windowController.close()
        } else {
            windowController.show()
        }
    }

    // MARK: - User actions

    func snooze(_ meeting: Meeting) {
        let key = AlertKey(eventID: meeting.id, start: meeting.start)
        states[key] = .snoozed(until: now().addingTimeInterval(Self.snoozeInterval))
        updatePresentation()
        rearmTimer()
    }

    func dismiss(_ meeting: Meeting) {
        let key = AlertKey(eventID: meeting.id, start: meeting.start)
        states[key] = .dismissed
        updatePresentation()
        rearmTimer()
    }

    func join(_ meeting: Meeting) {
        dismiss(meeting)
        onJoin(meeting)
    }

    func clearAll() {
        states.removeAll()
        meetingsByKey.removeAll()
        updatePresentation()
        rearmTimer()
    }

    #if DEBUG
    /// Shows the alert immediately with a fake meeting (Settings → debug section).
    func presentTestAlert() {
        let meeting = Meeting(
            id: "debug-test-\(UUID().uuidString)",
            iCalUID: "debug-test",
            calendarID: "debug",
            title: "Test Meeting Alert",
            start: Date().addingTimeInterval(120),
            end: Date().addingTimeInterval(1920),
            joinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            htmlLink: nil
        )
        let key = AlertKey(eventID: meeting.id, start: meeting.start)
        meetingsByKey[key] = meeting
        states[key] = .showing
        updatePresentation()
    }
    #endif
}
