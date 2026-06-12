import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(AppSettings.alertLeadTimeMinutesKey) private var leadTimeMinutes = 1
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Account") {
                accountRow
            }

            Section("Meeting Alert") {
                Picker("Show full-screen alert", selection: $leadTimeMinutes) {
                    Text("When the meeting starts").tag(0)
                    Text("1 minute before").tag(1)
                    Text("2 minutes before").tag(2)
                    Text("5 minutes before").tag(5)
                }
                .pickerStyle(.menu)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if !LaunchAtLogin.set(newValue) {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            }

            #if DEBUG
            Section("Debug") {
                Button("Trigger test alert") {
                    appState.alertScheduler.presentTestAlert()
                }
            }
            #endif
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    @ViewBuilder
    private var accountRow: some View {
        switch appState.authState {
        case .signedIn(let email):
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Calendar")
                    if let email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Sign Out") {
                    Task { await appState.signOut() }
                }
            }
        case .signedOut:
            HStack {
                Text("Not signed in")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Sign in with Google") {
                    Task { await appState.signIn() }
                }
                .disabled(appState.isSigningIn || !OAuthConfig.isConfigured)
            }
        }
    }
}
