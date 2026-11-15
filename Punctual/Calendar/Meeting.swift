import Foundation

/// A timed (non-all-day, non-declined) calendar event for today or tomorrow.
struct Meeting: Identifiable, Equatable, Hashable {
    let id: String          // event instance id, unique within a calendar
    let iCalUID: String     // identifies the event (or whole recurring series) across calendar copies;
                            // not unique per instance — dedupe pairs it with `occurrence`
    let calendarID: String
    let title: String
    let start: Date
    let end: Date
    let joinURL: URL?
    let htmlLink: URL?      // "open in Google Calendar" fallback
    /// A recurring instance's slot in its series (Google's `originalStartTime`), which
    /// stays put when the instance is rescheduled. Nil for one-off events.
    var originalStart: Date? = nil

    /// Which occurrence of the event this is: with iCalUID, identifies one instance
    /// across calendar copies even after it has been rescheduled.
    var occurrence: Date { originalStart ?? start }

    var isInProgress: Bool {
        let now = Date()
        return start <= now && now < end
    }

    var hasEnded: Bool { end <= Date() }
}
