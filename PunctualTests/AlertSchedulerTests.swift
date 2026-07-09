import XCTest
@testable import Punctual

@MainActor
final class AlertSchedulerTests: XCTestCase {
    /// Mirrors AlertWindowController's contract: show/close are idempotent
    /// while visible/hidden, so the counts track actual transitions.
    private final class SpyPresenter: AlertPresenting {
        private(set) var isVisible = false
        var showCount = 0
        var closeCount = 0

        func show() {
            guard !isVisible else { return }
            isVisible = true
            showCount += 1
        }

        func close() {
            guard isVisible else { return }
            isVisible = false
            closeCount += 1
        }
    }

    private var currentDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var presenter: SpyPresenter!
    private var scheduler: AlertScheduler!

    override func setUp() {
        super.setUp()
        currentDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        presenter = SpyPresenter()
        scheduler = AlertScheduler(now: { [unowned self] in currentDate }, presenter: presenter)
        scheduler.leadTime = 60
    }

    private func advance(_ seconds: TimeInterval) {
        currentDate = currentDate.addingTimeInterval(seconds)
    }

    private func meeting(
        id: String = "m1", startIn: TimeInterval, duration: TimeInterval = 1800
    ) -> Meeting {
        Meeting(
            id: id,
            iCalUID: "uid-\(id)",
            calendarID: "primary",
            title: "Meeting \(id)",
            start: currentDate.addingTimeInterval(startIn),
            end: currentDate.addingTimeInterval(startIn + duration),
            joinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            htmlLink: nil
        )
    }

    private var showing: [Meeting] { scheduler.presentation.meetings }

    // MARK: - Firing

    func testDoesNotFireBeforeLeadTime() {
        scheduler.reconcile(meetings: [meeting(startIn: 300)])
        XCTAssertTrue(showing.isEmpty)
        XCTAssertEqual(presenter.showCount, 0)
    }

    func testFiresAtLeadTime() {
        let m = meeting(startIn: 300)
        scheduler.reconcile(meetings: [m])
        advance(240)  // exactly start - leadTime
        scheduler.reconcile(meetings: [m])
        XCTAssertEqual(showing, [m])
        XCTAssertEqual(presenter.showCount, 1)
    }

    /// A failed refresh re-reconciles with the cached meeting list; alerts must
    /// still fire from that stale data (e.g. wake shortly before a meeting).
    func testFiresFromCachedDataWhenRefreshKeepsFailing() {
        let cached = [meeting(startIn: 300)]
        scheduler.reconcile(meetings: cached)
        advance(290)
        scheduler.reconcile(meetings: cached)
        XCTAssertEqual(showing, cached)
    }

    // MARK: - Late grace period

    func testFiresWithinLateGracePeriod() {
        let m = meeting(startIn: 300)
        scheduler.reconcile(meetings: [m])
        advance(300 + 100)  // 100 s after start; grace is 180 s
        scheduler.reconcile(meetings: [m])
        XCTAssertEqual(showing, [m])
    }

    func testSkipsSilentlyBeyondLateGracePeriod() {
        let m = meeting(startIn: 300)
        scheduler.reconcile(meetings: [m])
        advance(300 + 181)
        scheduler.reconcile(meetings: [m])
        XCTAssertTrue(showing.isEmpty)
        XCTAssertEqual(presenter.showCount, 0)
    }

    // MARK: - Snooze / dismiss

    func testSnoozeHidesThenRepresentsAfterInterval() {
        let m = meeting(startIn: 60)
        scheduler.reconcile(meetings: [m])
        advance(1)
        scheduler.reconcile(meetings: [m])
        XCTAssertEqual(showing, [m])

        scheduler.snooze(m)
        XCTAssertTrue(showing.isEmpty)
        XCTAssertEqual(presenter.closeCount, 1)

        advance(59)
        scheduler.reconcile(meetings: [m])
        XCTAssertTrue(showing.isEmpty, "snooze must last the full 60 s")

        advance(1)
        scheduler.reconcile(meetings: [m])
        XCTAssertEqual(showing, [m])
    }

    func testDismissIsPermanentForThatSlot() {
        let m = meeting(startIn: 60)
        scheduler.reconcile(meetings: [m])
        advance(5)
        scheduler.reconcile(meetings: [m])
        scheduler.dismiss(m)

        advance(30)
        scheduler.reconcile(meetings: [m])
        XCTAssertTrue(showing.isEmpty)
        XCTAssertEqual(presenter.showCount, 1)
    }

    func testRescheduledMeetingAlertsAgainAfterDismissal() {
        let original = meeting(startIn: 60)
        scheduler.reconcile(meetings: [original])
        advance(5)
        scheduler.reconcile(meetings: [original])
        scheduler.dismiss(original)

        // Same event id, new start: a fresh alert slot.
        let rescheduled = meeting(startIn: 600)
        scheduler.reconcile(meetings: [rescheduled])
        advance(545)  // 55 s before new start, within 60 s lead
        scheduler.reconcile(meetings: [rescheduled])
        XCTAssertEqual(showing, [rescheduled])
    }

    // MARK: - Reconcile pruning

    func testCancelledMeetingClosesItsAlert() {
        let m = meeting(startIn: 60)
        scheduler.reconcile(meetings: [m])
        advance(5)
        scheduler.reconcile(meetings: [m])
        XCTAssertEqual(showing, [m])

        scheduler.reconcile(meetings: [])
        XCTAssertTrue(showing.isEmpty)
        XCTAssertEqual(presenter.closeCount, 1)
    }

    // MARK: - Actions

    func testJoinDismissesAndInvokesCallback() {
        var joined: Meeting?
        scheduler.onJoin = { joined = $0 }

        let m = meeting(startIn: 60)
        scheduler.reconcile(meetings: [m])
        advance(5)
        scheduler.reconcile(meetings: [m])

        scheduler.join(m)
        XCTAssertEqual(joined, m)
        XCTAssertTrue(showing.isEmpty)
    }

    func testClearAllClosesEverything() {
        let m = meeting(startIn: 60)
        scheduler.reconcile(meetings: [m])
        advance(5)
        scheduler.reconcile(meetings: [m])

        scheduler.clearAll()
        XCTAssertTrue(showing.isEmpty)
    }
}
