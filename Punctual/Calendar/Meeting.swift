import Foundation

/// A timed (non-all-day, non-declined) calendar event for today or tomorrow.
struct Meeting: Identifiable, Equatable, Hashable {
    let id: String          // event instance id, unique within a calendar
    let iCalUID: String     // stable across calendar copies; used for dedupe
    let calendarID: String
    let title: String
    let start: Date
    let end: Date
    let joinURL: URL?
    let htmlLink: URL?      // "open in Google Calendar" fallback

    var isInProgress: Bool {
        let now = Date()
        return start <= now && now < end
    }

    var hasEnded: Bool { end <= Date() }
}
