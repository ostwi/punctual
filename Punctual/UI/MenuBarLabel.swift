import SwiftUI

/// What lives in the menu bar: the Punctual ring mark plus the countdown text.
/// Status items strip most styling, so keep this to an image and plain text.
/// MenuBarIcon is a template asset, so the menu bar tints it for light/dark.
struct MenuBarLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon")
            Text(title)
        }
    }
}
