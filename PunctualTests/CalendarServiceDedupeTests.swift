import XCTest
@testable import Punctual

final class CalendarServiceDedupeTests: XCTestCase {
    private func meeting(
        id: String, iCalUID: String, calendarID: String = "primary", withLink: Bool,
        start: TimeInterval = 800_000_000, originalStart: TimeInterval? = nil
    ) -> Meeting {
        Meeting(
            id: id,
            iCalUID: iCalUID,
            calendarID: calendarID,
            title: "Standup",
            start: Date(timeIntervalSinceReferenceDate: start),
            end: Date(timeIntervalSinceReferenceDate: start + 1_800),
            joinURL: withLink ? URL(string: "https://meet.google.com/abc-defg-hij") : nil,
            htmlLink: nil,
            originalStart: originalStart.map { Date(timeIntervalSinceReferenceDate: $0) }
        )
    }

    func testKeepsCopyWithJoinLinkRegardlessOfOrder() {
        let bare = meeting(id: "a", iCalUID: "uid1", calendarID: "work", withLink: false)
        let linked = meeting(id: "b", iCalUID: "uid1", calendarID: "personal", withLink: true)

        for order in [[bare, linked], [linked, bare]] {
            let result = CalendarService.dedupe(order)
            XCTAssertEqual(result.count, 1)
            XCTAssertNotNil(result[0].joinURL)
        }
    }

    func testKeepsDistinctEvents() {
        let one = meeting(id: "a", iCalUID: "uid1", withLink: true)
        let two = meeting(id: "b", iCalUID: "uid2", withLink: false)
        XCTAssertEqual(CalendarService.dedupe([one, two]).count, 2)
    }

    func testDuplicatesWithoutLinksCollapseToOne() {
        let first = meeting(id: "a", iCalUID: "uid1", calendarID: "work", withLink: false)
        let second = meeting(id: "b", iCalUID: "uid1", calendarID: "personal", withLink: false)
        XCTAssertEqual(CalendarService.dedupe([first, second]).count, 1)
    }

    // Instances of one recurring series share an iCalUID but differ in start.

    private let day: TimeInterval = 86_400

    func testRecurringInstancesWithoutLinksAllSurvive() {
        let today = meeting(id: "a_1", iCalUID: "series", withLink: false)
        let tomorrow = meeting(id: "a_2", iCalUID: "series", withLink: false, start: 800_000_000 + day)

        let result = CalendarService.dedupe([today, tomorrow])

        XCTAssertEqual(Set(result.map(\.id)), ["a_1", "a_2"])
    }

    func testRecurringInstancesWithLinksAllSurvive() {
        let today = meeting(id: "a_1", iCalUID: "series", withLink: true)
        let tomorrow = meeting(id: "a_2", iCalUID: "series", withLink: true, start: 800_000_000 + day)

        XCTAssertEqual(CalendarService.dedupe([today, tomorrow]).count, 2)
    }

    func testSeriesRecurringTwiceInOneDayKeepsBothInstances() {
        let morning = meeting(id: "a_1", iCalUID: "series", withLink: true)
        let afternoon = meeting(id: "a_2", iCalUID: "series", withLink: true, start: 800_000_000 + 14_400)

        XCTAssertEqual(CalendarService.dedupe([morning, afternoon]).count, 2)
    }

    func testCopiesOfRecurringInstancesAcrossCalendarsStillMerge() {
        let workToday = meeting(id: "a_1", iCalUID: "series", calendarID: "work", withLink: false)
        let personalToday = meeting(id: "b_1", iCalUID: "series", calendarID: "personal", withLink: true)
        let workTomorrow = meeting(id: "a_2", iCalUID: "series", calendarID: "work", withLink: false, start: 800_000_000 + day)

        let result = CalendarService.dedupe([workToday, personalToday, workTomorrow])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first { $0.start == workToday.start }?.calendarID, "personal")
    }

    // Calendars are fetched concurrently, so dedupe must pick the same copy for any input order.

    func testTieBetweenLinkedCopiesKeepsSameCopyRegardlessOfOrder() {
        let work = meeting(id: "a", iCalUID: "uid1", calendarID: "work", withLink: true)
        let personal = meeting(id: "b", iCalUID: "uid1", calendarID: "personal", withLink: true)

        XCTAssertEqual(CalendarService.dedupe([work, personal]).map(\.id), ["b"])
        XCTAssertEqual(CalendarService.dedupe([personal, work]).map(\.id), ["b"])
    }

    func testTieBetweenUnlinkedCopiesKeepsSameCopyRegardlessOfOrder() {
        let work = meeting(id: "a", iCalUID: "uid1", calendarID: "work", withLink: false)
        let personal = meeting(id: "b", iCalUID: "uid1", calendarID: "personal", withLink: false)

        XCTAssertEqual(CalendarService.dedupe([work, personal]).map(\.id), ["b"])
        XCTAssertEqual(CalendarService.dedupe([personal, work]).map(\.id), ["b"])
    }

    // A rescheduled instance keeps its original slot in the series (originalStartTime),
    // so copies still merge while the new time propagates between calendars.

    func testRescheduledInstanceMergesWhileCopiesDisagreeOnStart() {
        let slot: TimeInterval = 800_000_000
        let moved = meeting(id: "a_1", iCalUID: "series", calendarID: "work", withLink: true,
                            start: slot + 1_800, originalStart: slot)
        let lagging = meeting(id: "b_1", iCalUID: "series", calendarID: "subscribed", withLink: false,
                              start: slot, originalStart: slot)

        XCTAssertEqual(CalendarService.dedupe([moved, lagging]).map(\.id), ["a_1"])
    }

    func testInstanceMovedOntoAnotherInstancesTimeStaysSeparate() {
        let today = meeting(id: "a_1", iCalUID: "series", withLink: true,
                            start: 800_000_000, originalStart: 800_000_000)
        let tomorrowMovedToToday = meeting(id: "a_2", iCalUID: "series", withLink: true,
                                           start: 800_000_000, originalStart: 800_000_000 + day)

        XCTAssertEqual(CalendarService.dedupe([today, tomorrowMovedToToday]).count, 2)
    }

    // Mapping from the API response.

    private func event(_ json: String) throws -> GCalEvent {
        try JSONDecoder().decode(GCalEvent.self, from: Data(json.utf8))
    }

    func testMapsOriginalStartTimeOfRecurringInstance() throws {
        let event = try event("""
        {
            "id": "series_20260616T080000Z",
            "iCalUID": "series@google.com",
            "recurringEventId": "series",
            "summary": "Standup",
            "start": {"dateTime": "2026-06-16T10:30:00+02:00"},
            "end": {"dateTime": "2026-06-16T10:45:00+02:00"},
            "originalStartTime": {"dateTime": "2026-06-16T10:00:00+02:00"}
        }
        """)

        let meeting = try XCTUnwrap(CalendarService.meeting(from: event, calendarID: "primary"))

        XCTAssertEqual(meeting.originalStart, ISO8601DateFormatter().date(from: "2026-06-16T08:00:00Z"))
        XCTAssertEqual(meeting.occurrence, meeting.originalStart)
        XCTAssertNotEqual(meeting.occurrence, meeting.start)
    }

    func testOneOffEventUsesStartAsOccurrence() throws {
        let event = try event("""
        {
            "id": "oneoff",
            "iCalUID": "oneoff@google.com",
            "start": {"dateTime": "2026-06-16T10:00:00Z"},
            "end": {"dateTime": "2026-06-16T11:00:00Z"}
        }
        """)

        let meeting = try XCTUnwrap(CalendarService.meeting(from: event, calendarID: "primary"))

        XCTAssertNil(meeting.originalStart)
        XCTAssertEqual(meeting.occurrence, meeting.start)
    }
}
