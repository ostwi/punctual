import XCTest
@testable import Punctual

/// When some calendars fail to load, the refresh keeps their previous meetings.
final class CalendarFetchMergeTests: XCTestCase {
    private func meeting(id: String, calendarID: String, start: TimeInterval = 800_000_000) -> Meeting {
        Meeting(
            id: id,
            iCalUID: id,
            calendarID: calendarID,
            title: "Meeting \(id)",
            start: Date(timeIntervalSinceReferenceDate: start),
            end: Date(timeIntervalSinceReferenceDate: start + 1_800),
            joinURL: nil,
            htmlLink: nil
        )
    }

    func testWithoutFailuresUsesFetchedMeetingsOnly() {
        let fresh = meeting(id: "new", calendarID: "work")
        let stale = meeting(id: "old", calendarID: "work")

        let result = CalendarService.merge(fetched: [fresh], previous: [stale], failedCalendarIDs: [])

        XCTAssertEqual(result.map(\.id), ["new"])
    }

    func testKeepsPreviousMeetingsOfFailedCalendarOnly() {
        let fetchedWork = meeting(id: "w2", calendarID: "work", start: 800_003_600)
        let previousWork = meeting(id: "w1", calendarID: "work")
        let previousTeam = meeting(id: "t1", calendarID: "team")

        let result = CalendarService.merge(
            fetched: [fetchedWork], previous: [previousWork, previousTeam], failedCalendarIDs: ["team"]
        )

        XCTAssertEqual(result.map(\.id), ["t1", "w2"])
    }

    func testKeptMeetingDedupesAgainstCopyOnAnotherCalendar() {
        let fetchedCopy = Meeting(
            id: "w1", iCalUID: "shared", calendarID: "work", title: "Sync",
            start: Date(timeIntervalSinceReferenceDate: 800_000_000),
            end: Date(timeIntervalSinceReferenceDate: 800_001_800),
            joinURL: nil, htmlLink: nil
        )
        let keptCopy = Meeting(
            id: "t1", iCalUID: "shared", calendarID: "team", title: "Sync",
            start: Date(timeIntervalSinceReferenceDate: 800_000_000),
            end: Date(timeIntervalSinceReferenceDate: 800_001_800),
            joinURL: nil, htmlLink: nil
        )

        let result = CalendarService.merge(fetched: [fetchedCopy], previous: [keptCopy], failedCalendarIDs: ["team"])

        XCTAssertEqual(result.count, 1)
    }
}
