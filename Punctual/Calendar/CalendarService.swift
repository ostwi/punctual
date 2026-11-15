import Foundation

/// Stateless REST client for the Google Calendar API v3.
@MainActor
struct CalendarService {
    let auth: GoogleAuthController

    private nonisolated static let baseURL = URL(string: "https://www.googleapis.com/calendar/v3")!

    /// Every calendar the account can read, plus today's and tomorrow's timed
    /// meetings from the ones enabled in Settings, deduped and sorted by start.
    /// Fetching a day ahead keeps the menu bar useful after the last meeting and
    /// lets alerts for early-morning meetings arm before an overnight sleep.
    func fetchMeetings() async throws -> CalendarFetchResult {
        var token = try await auth.validAccessToken()
        do {
            return try await fetchAll(token: token)
        } catch CalendarAPIError.unauthorized {
            // Access token rejected despite local expiry check — refresh once and retry.
            token = try await auth.validAccessToken(forceRefresh: true)
            return try await fetchAll(token: token)
        }
    }

    private func fetchAll(token: String) async throws -> CalendarFetchResult {
        let calendars = try await fetchCalendarList(token: token)
        let overrides = AppSettings.calendarOverrides()
        let calendarIDs = calendars
            .filter { AppSettings.isCalendarEnabled(id: $0.id, selectedInGoogle: $0.selectedInGoogle, overrides: overrides) }
            .map(\.id)

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfDay)!

        // One calendar failing (deleted, access revoked, a transient error) must
        // not fail the whole refresh: the other calendars and the Settings picker
        // keep working, and the user can switch the broken calendar off. Auth
        // errors and cancellation still propagate so the caller can react.
        let (meetings, failedCalendarIDs) = try await withThrowingTaskGroup(
            of: (calendarID: String, meetings: [Meeting]?).self
        ) { group in
            for calendarID in calendarIDs {
                group.addTask {
                    do {
                        let meetings = try await Self.fetchEvents(
                            calendarID: calendarID, token: token,
                            timeMin: startOfDay, timeMax: endOfTomorrow
                        )
                        return (calendarID, meetings)
                    } catch CalendarAPIError.unauthorized {
                        throw CalendarAPIError.unauthorized
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return (calendarID, nil)
                    }
                }
            }
            var merged: [Meeting] = []
            var failed: Set<String> = []
            for try await batch in group {
                if let meetings = batch.meetings {
                    merged.append(contentsOf: meetings)
                } else {
                    failed.insert(batch.calendarID)
                }
            }
            return (merged, failed)
        }
        return CalendarFetchResult(
            calendars: calendars,
            meetings: Self.dedupe(meetings).sorted { $0.start < $1.start },
            failedCalendarIDs: failedCalendarIDs
        )
    }

    /// The fetched meetings plus, for each calendar that failed this time, the
    /// meetings it had before, so a transient failure doesn't drop its alerts.
    nonisolated static func merge(
        fetched: [Meeting], previous: [Meeting], failedCalendarIDs: Set<String>
    ) -> [Meeting] {
        guard !failedCalendarIDs.isEmpty else { return fetched }
        let kept = previous.filter { failedCalendarIDs.contains($0.calendarID) }
        return dedupe(fetched + kept).sorted { $0.start < $1.start }
    }

    /// The same event invited to several of the user's calendars shares an iCalUID
    /// and a start time; keep the copy that has a join link. Every instance of a
    /// recurring series also shares the iCalUID, so the start time is part of the
    /// key — otherwise today's and tomorrow's instances collapse into one.
    nonisolated static func dedupe(_ meetings: [Meeting]) -> [Meeting] {
        struct Key: Hashable {
            let iCalUID: String
            let start: Date
        }
        var byKey: [Key: Meeting] = [:]
        for meeting in meetings {
            let key = Key(iCalUID: meeting.iCalUID, start: meeting.start)
            if let existing = byKey[key], !isPreferred(meeting, over: existing) { continue }
            byKey[key] = meeting
        }
        return Array(byKey.values)
    }

    /// The copy with a join link wins; otherwise the lowest (calendarID, id) does.
    /// Calendars are fetched concurrently, so input order varies between refreshes —
    /// the winner must not, because alert state is keyed on the surviving `Meeting.id`.
    private nonisolated static func isPreferred(_ candidate: Meeting, over existing: Meeting) -> Bool {
        let candidateHasLink = candidate.joinURL != nil
        if candidateHasLink != (existing.joinURL != nil) { return candidateHasLink }
        return (candidate.calendarID, candidate.id) < (existing.calendarID, existing.id)
    }

    /// All readable calendars, primary first, then alphabetical.
    private func fetchCalendarList(token: String) async throws -> [CalendarInfo] {
        var components = URLComponents(
            url: Self.baseURL.appending(path: "users/me/calendarList"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "minAccessRole", value: "reader"),
            URLQueryItem(name: "fields", value: "items(id,summary,selected,primary,backgroundColor)"),
        ]
        let response: GCalCalendarListResponse = try await Self.get(components.url!, token: token)
        return (response.items ?? [])
            .map {
                CalendarInfo(
                    id: $0.id,
                    name: $0.summary?.isEmpty == false ? $0.summary! : $0.id,
                    colorHex: $0.backgroundColor,
                    isPrimary: $0.primary == true,
                    selectedInGoogle: $0.selected != false
                )
            }
            .sorted {
                if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private nonisolated static func fetchEvents(
        calendarID: String, token: String, timeMin: Date, timeMax: Date
    ) async throws -> [Meeting] {
        let formatter = ISO8601DateFormatter()
        var components = URLComponents(
            url: baseURL.appending(path: "calendars/\(calendarID)/events"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "timeMin", value: formatter.string(from: timeMin)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: timeMax)),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(
                name: "fields",
                value: "items(id,iCalUID,status,summary,start,end,location,description,"
                    + "hangoutLink,htmlLink,conferenceData(entryPoints),attendees(self,responseStatus))"
            ),
        ]
        let response: GCalEventsResponse = try await get(components.url!, token: token)

        return (response.items ?? []).compactMap { event in
            guard event.status != "cancelled",
                  !event.isAllDay,
                  !event.isDeclinedByMe,
                  let start = event.start?.parsedDateTime,
                  let end = event.end?.parsedDateTime
            else { return nil }
            return Meeting(
                id: event.id,
                iCalUID: event.iCalUID ?? event.id,
                calendarID: calendarID,
                title: event.summary?.isEmpty == false ? event.summary! : "(No title)",
                start: start,
                end: end,
                joinURL: JoinLinkExtractor.joinURL(for: event),
                htmlLink: event.htmlLink.flatMap(URL.init(string:))
            )
        }
    }

    private nonisolated static func get<T: Decodable>(_ url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CalendarAPIError.badResponse }
        switch http.statusCode {
        case 200: return try JSONDecoder().decode(T.self, from: data)
        case 401: throw CalendarAPIError.unauthorized
        default:
            throw CalendarAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}

/// A calendar on the user's Google Calendar list, for the Settings picker.
struct CalendarInfo: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let colorHex: String?
    let isPrimary: Bool
    /// Whether it is ticked in Google Calendar's web UI; the default when the
    /// user hasn't chosen in Punctual.
    let selectedInGoogle: Bool
}

struct CalendarFetchResult: Sendable {
    let calendars: [CalendarInfo]
    let meetings: [Meeting]
    /// Enabled calendars whose events couldn't be fetched this time.
    var failedCalendarIDs: Set<String> = []
}

enum CalendarAPIError: LocalizedError {
    case unauthorized
    case badResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Google Calendar authorization expired."
        case .badResponse: "Unexpected response from Google Calendar."
        case .http(let code, _): "Google Calendar request failed (HTTP \(code))."
        }
    }
}
