import Foundation

enum AppSettings {
    static let alertLeadTimeMinutesKey = "alertLeadTimeMinutes"

    /// Minutes before the meeting start when the full-screen alert fires. Default: 1.
    static var alertLeadTimeMinutes: Int {
        UserDefaults.standard.object(forKey: alertLeadTimeMinutesKey) as? Int ?? 1
    }

    static var alertLeadTime: TimeInterval { TimeInterval(alertLeadTimeMinutes * 60) }
}
