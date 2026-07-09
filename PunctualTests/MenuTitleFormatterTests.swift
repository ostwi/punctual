import XCTest
@testable import Punctual

final class MenuTitleFormatterTests: XCTestCase {
    // A fixed "now" at 10:00 local time so date arithmetic never crosses midnight.
    private let calendar = Calendar.current
    private var now: Date {
        calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
    }

    private func meeting(title: String = "Standup", start: Date) -> Meeting {
        Meeting(
            id: "m1", iCalUID: "uid1", calendarID: "primary",
            title: title, start: start, end: start.addingTimeInterval(1800),
            joinURL: nil, htmlLink: nil
        )
    }

    func testCountdownInMinutes() {
        let next = meeting(start: now.addingTimeInterval(12 * 60))
        XCTAssertEqual(
            MenuTitleFormatter.title(next: next, current: nil, now: now, calendar: calendar),
            "Standup in 12m"
        )
    }

    func testCountdownInHoursAndMinutes() {
        let next = meeting(start: now.addingTimeInterval(65 * 60))
        XCTAssertEqual(
            MenuTitleFormatter.title(next: next, current: nil, now: now, calendar: calendar),
            "Standup in 1h 5m"
        )
    }

    func testCountdownInSecondsUnderAMinute() {
        let next = meeting(start: now.addingTimeInterval(45))
        XCTAssertEqual(
            MenuTitleFormatter.title(next: next, current: nil, now: now, calendar: calendar),
            "Standup in 0:45"
        )
    }

    func testMeetingInProgress() {
        let current = meeting(start: now.addingTimeInterval(-600))
        XCTAssertEqual(
            MenuTitleFormatter.title(next: nil, current: current, now: now, calendar: calendar),
            "Standup now"
        )
    }

    func testTomorrowsMeetingShowsStartTimeNotCountdown() {
        let start = calendar.date(byAdding: .day, value: 1, to: now)!
        let next = meeting(title: "Kickoff", start: start)
        let time = start.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(
            MenuTitleFormatter.title(next: next, current: nil, now: now, calendar: calendar),
            "Kickoff tomorrow \(time)"
        )
    }

    func testInProgressMeetingBeatsTomorrowsMeeting() {
        let current = meeting(title: "Retro", start: now.addingTimeInterval(-600))
        let next = meeting(title: "Kickoff", start: calendar.date(byAdding: .day, value: 1, to: now)!)
        XCTAssertEqual(
            MenuTitleFormatter.title(next: next, current: current, now: now, calendar: calendar),
            "Retro now"
        )
    }

    func testNoMeetings() {
        XCTAssertEqual(
            MenuTitleFormatter.title(next: nil, current: nil, now: now, calendar: calendar),
            "No meetings"
        )
    }

    func testLongTitleIsTruncatedWithEllipsis() {
        let next = meeting(
            title: "Quarterly planning marathon with the whole team",
            start: now.addingTimeInterval(600)
        )
        let title = MenuTitleFormatter.title(next: next, current: nil, now: now, calendar: calendar)
        XCTAssertEqual(title, "Quarterly planning mara… in 10m")
    }
}
