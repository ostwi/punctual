import XCTest
@testable import Punctual

final class JoinLinkExtractorTests: XCTestCase {
    /// Decodes a GCalEvent from JSON so tests exercise the same path as API responses.
    private func event(_ json: String) throws -> GCalEvent {
        try JSONDecoder().decode(GCalEvent.self, from: Data(json.utf8))
    }

    func testPrefersConferenceDataVideoEntryPoint() throws {
        let event = try event("""
        {
            "id": "e1",
            "hangoutLink": "https://meet.google.com/legacy-link",
            "conferenceData": {
                "entryPoints": [
                    {"entryPointType": "phone", "uri": "tel:+1-555-0100"},
                    {"entryPointType": "video", "uri": "https://meet.google.com/abc-defg-hij"}
                ]
            },
            "location": "https://zoom.us/j/999"
        }
        """)
        XCTAssertEqual(
            JoinLinkExtractor.joinURL(for: event)?.absoluteString,
            "https://meet.google.com/abc-defg-hij"
        )
    }

    func testFallsBackToHangoutLinkWhenConferenceDataHasNoVideo() throws {
        let event = try event("""
        {
            "id": "e2",
            "hangoutLink": "https://meet.google.com/xyz-legacy",
            "conferenceData": {
                "entryPoints": [{"entryPointType": "phone", "uri": "tel:+1-555-0100"}]
            }
        }
        """)
        XCTAssertEqual(
            JoinLinkExtractor.joinURL(for: event)?.absoluteString,
            "https://meet.google.com/xyz-legacy"
        )
    }

    func testExtractsZoomLinkFromLocation() throws {
        let event = try event("""
        {"id": "e3", "location": "Zoom: https://company.zoom.us/j/1234567890?pwd=abc123"}
        """)
        XCTAssertEqual(
            JoinLinkExtractor.joinURL(for: event)?.absoluteString,
            "https://company.zoom.us/j/1234567890?pwd=abc123"
        )
    }

    func testExtractsTeamsLinkFromHTMLDescription() throws {
        let event = try event("""
        {"id": "e4", "description": "<a href=\\"https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=x\\">Join</a>"}
        """)
        XCTAssertEqual(
            JoinLinkExtractor.joinURL(for: event)?.absoluteString,
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=x"
        )
    }

    func testUnescapesHTMLAmpersandsInZoomQuery() {
        let url = JoinLinkExtractor.firstMeetingURL(
            in: "Join: https://zoom.us/j/123?pwd=a&amp;uname=b"
        )
        XCTAssertEqual(url?.absoluteString, "https://zoom.us/j/123?pwd=a&uname=b")
    }

    func testExtractsTeamsLiveLink() {
        let url = JoinLinkExtractor.firstMeetingURL(in: "https://teams.live.com/meet/9312345678901")
        XCTAssertEqual(url?.absoluteString, "https://teams.live.com/meet/9312345678901")
    }

    func testExtractsGoogleMeetFromText() {
        let url = JoinLinkExtractor.firstMeetingURL(in: "Room A — https://meet.google.com/abc-defg-hij or dial in")
        XCTAssertEqual(url?.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testNoLinkYieldsNil() throws {
        let event = try event("""
        {"id": "e5", "summary": "1:1", "location": "Office 4.2", "description": "Bring notes https://example.com/agenda"}
        """)
        XCTAssertNil(JoinLinkExtractor.joinURL(for: event))
    }

    // MARK: - DTO parsing

    func testAllDayAndDeclinedDetection() throws {
        let allDay = try event("""
        {"id": "e6", "start": {"date": "2026-07-08"}, "end": {"date": "2026-07-09"}}
        """)
        XCTAssertTrue(allDay.isAllDay)

        let declined = try event("""
        {"id": "e7", "start": {"dateTime": "2026-07-08T10:00:00+02:00"},
         "attendees": [{"self": true, "responseStatus": "declined"}]}
        """)
        XCTAssertFalse(declined.isAllDay)
        XCTAssertTrue(declined.isDeclinedByMe)
        XCTAssertNotNil(declined.start?.parsedDateTime)
    }
}
