import Foundation

/// Pure formatting for the menu bar title, separated from AppState so it can
/// be tested with a fixed clock.
enum MenuTitleFormatter {
    /// `next` is the earliest meeting that hasn't started; `current` one in progress.
    static func title(
        next: Meeting?,
        current: Meeting?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        if let next, calendar.isDate(next.start, inSameDayAs: now) {
            return "\(truncated(next.title)) \(countdownPhrase(to: next.start, now: now))"
        }
        if let current {
            return "\(truncated(current.title)) now"
        }
        if let next {
            let time = next.start.formatted(date: .omitted, time: .shortened)
            return "\(truncated(next.title)) tomorrow \(time)"
        }
        return "No meetings"
    }

    static func countdownPhrase(to start: Date, now: Date = Date()) -> String {
        let remaining = start.timeIntervalSince(now)
        if remaining < 60 {
            return String(format: "in 0:%02d", max(Int(remaining.rounded()), 0))
        }
        let totalMinutes = Int((remaining / 60).rounded(.up))
        if totalMinutes >= 60 {
            return "in \(totalMinutes / 60)h \(totalMinutes % 60)m"
        }
        return "in \(totalMinutes)m"
    }

    static func truncated(_ title: String, limit: Int = 24) -> String {
        title.count <= limit ? title : String(title.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
