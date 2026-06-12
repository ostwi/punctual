import Foundation

/// Resolves the video-call URL for an event:
/// structured conferenceData first, then the legacy hangoutLink field,
/// then known URL patterns in the location and description text.
enum JoinLinkExtractor {
    static func joinURL(for event: GCalEvent) -> URL? {
        if let uri = event.conferenceData?.entryPoints?
            .first(where: { $0.entryPointType == "video" })?.uri,
           let url = URL(string: uri) {
            return url
        }
        if let hangout = event.hangoutLink, let url = URL(string: hangout) {
            return url
        }
        for text in [event.location, event.description].compactMap({ $0 }) {
            if let url = firstMeetingURL(in: text) { return url }
        }
        return nil
    }

    static func firstMeetingURL(in text: String) -> URL? {
        // Descriptions are HTML; Zoom links with query params arrive with &amp;.
        let unescaped = text.replacingOccurrences(of: "&amp;", with: "&")
        let patterns = [
            #"https://meet\.google\.com/[a-z0-9\-]+"#,
            #"https://[\w.\-]*zoom\.us/(j|my|w|s)/[^\s"'<>]+"#,
            #"https://teams\.microsoft\.com/(l/meetup-join|meet)/[^\s"'<>]+"#,
            #"https://teams\.live\.com/meet/[^\s"'<>]+"#,
        ]
        for pattern in patterns {
            if let range = unescaped.range(of: pattern, options: .regularExpression) {
                return URL(string: String(unescaped[range]))
            }
        }
        return nil
    }
}
