import SwiftUI

@main
struct ReminderApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(appState)
        } label: {
            MenuBarLabel(title: appState.menuTitle)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
