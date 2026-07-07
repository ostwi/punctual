import SwiftUI

/// What lives in the menu bar: a calendar glyph plus the countdown text.
/// Status items strip most styling, so keep this to an image and plain text.
struct MenuBarLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar.badge.clock")
            Text(title)
        }
    }
}
