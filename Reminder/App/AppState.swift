import AppKit
import Foundation
import Observation

/// Single source of truth: auth status, today's meetings, the menu bar title.
/// Owns and wires all services.
@MainActor
@Observable
final class AppState {
    enum AuthState: Equatable {
        case signedOut
        case signedIn(email: String?)
    }

    var authState: AuthState = .signedOut
    var meetings: [Meeting] = []
    var menuTitle: String = "…"
    var lastUpdated: Date?
    var lastError: String?
    var isSigningIn = false

    let auth = GoogleAuthController()
    let alertScheduler = AlertScheduler()

    @ObservationIgnored private lazy var calendarService = CalendarService(auth: auth)
    @ObservationIgnored private let ticker = MenuTitleTicker()
    @ObservationIgnored private let refreshCoordinator = RefreshCoordinator()
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    init() {
        if let tokens = auth.storedTokens {
            authState = .signedIn(email: tokens.email)
        }

        alertScheduler.onJoin = { [weak self] meeting in self?.join(meeting) }
        ticker.onTick = { [weak self] in self?.tick() }
        refreshCoordinator.onRefresh = { [weak self] in await self?.refresh() }
        refreshCoordinator.start()

        // Lead time changed in Settings → re-aim pending alerts immediately.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let leadTime = AppSettings.alertLeadTime
                if self.alertScheduler.leadTime != leadTime {
                    self.alertScheduler.leadTime = leadTime
                    self.alertScheduler.reconcile(meetings: self.remainingMeetings)
                }
            }
        }

        tick()
        Task { await refresh() }
    }

    // MARK: - Derived

    /// Today's meetings that have not ended yet.
    var remainingMeetings: [Meeting] { meetings.filter { !$0.hasEnded } }

    var upcomingMeetings: [Meeting] { meetings.filter { $0.start > Date() } }

    var nextMeeting: Meeting? { upcomingMeetings.first }

    var currentMeeting: Meeting? { meetings.first { $0.isInProgress } }

    // MARK: - Data refresh

    func refresh() async {
        guard case .signedIn = authState else {
            tick()
            return
        }
        do {
            meetings = try await calendarService.fetchTodaysMeetings()
            lastUpdated = Date()
            lastError = nil
        } catch AuthError.signedOut {
            handleSignedOut()
            return
        } catch is CancellationError {
            return
        } catch {
            // Keep showing the last good data; surface the problem subtly.
            lastError = error.localizedDescription
        }
        alertScheduler.leadTime = AppSettings.alertLeadTime
        // Non-ended (not merely upcoming) meetings: an in-progress meeting whose
        // alert is showing must keep its key, or reconcile would prune it
        // and close the alert moments after the meeting starts.
        alertScheduler.reconcile(meetings: remainingMeetings)
        tick()
    }

    /// Recomputes the menu title and re-arms the ticker for the next change.
    private func tick() {
        menuTitle = computeMenuTitle()
        ticker.rearm(nextChange: nextMeeting?.start ?? currentMeeting?.end)
    }

    private func computeMenuTitle() -> String {
        guard case .signedIn = authState else { return "Sign in" }

        if let next = nextMeeting {
            return "\(truncated(next.title)) \(countdownPhrase(to: next.start))"
        }
        if let current = currentMeeting {
            return "\(truncated(current.title)) now"
        }
        return "No meetings"
    }

    private func countdownPhrase(to start: Date) -> String {
        let remaining = start.timeIntervalSinceNow
        if remaining < 60 {
            return String(format: "in 0:%02d", max(Int(remaining.rounded()), 0))
        }
        let totalMinutes = Int((remaining / 60).rounded(.up))
        if totalMinutes >= 60 {
            return "in \(totalMinutes / 60)h \(totalMinutes % 60)m"
        }
        return "in \(totalMinutes)m"
    }

    private func truncated(_ title: String, limit: Int = 24) -> String {
        title.count <= limit ? title : String(title.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Auth actions

    func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let tokens = try await auth.signIn()
            authState = .signedIn(email: tokens.email)
            lastError = nil
            await refresh()
        } catch AuthError.cancelled {
            // User closed the window; not an error worth surfacing.
        } catch {
            lastError = error.localizedDescription
            tick()
        }
    }

    func signOut() async {
        await auth.signOut()
        handleSignedOut()
    }

    private func handleSignedOut() {
        authState = .signedOut
        meetings = []
        lastUpdated = nil
        alertScheduler.clearAll()
        tick()
    }

    // MARK: - Joining

    func join(_ meeting: Meeting) {
        if let url = meeting.joinURL ?? meeting.htmlLink {
            NSWorkspace.shared.open(url)
        }
    }
}
