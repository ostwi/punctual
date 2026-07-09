import XCTest
@testable import Punctual

final class CalendarServiceDedupeTests: XCTestCase {
    private func meeting(
        id: String, iCalUID: String, calendarID: String = "primary", withLink: Bool
    ) -> Meeting {
        Meeting(
            id: id,
            iCalUID: iCalUID,
            calendarID: calendarID,
            title: "Standup",
            start: Date(timeIntervalSinceReferenceDate: 800_000_000),
            end: Date(timeIntervalSinceReferenceDate: 800_001_800),
            joinURL: withLink ? URL(string: "https://meet.google.com/abc-defg-hij") : nil,
            htmlLink: nil
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
}
