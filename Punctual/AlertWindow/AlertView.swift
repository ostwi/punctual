import SwiftUI

/// Full-screen "meeting is starting" overlay: dimmed backdrop with one
/// card per due meeting.
struct AlertView: View {
    let presentation: AlertPresentation
    let onJoin: (Meeting) -> Void
    let onSnooze: (Meeting) -> Void
    let onDismiss: (Meeting) -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ForEach(presentation.meetings) { meeting in
                    AlertCard(
                        meeting: meeting,
                        isPrimary: meeting.id == presentation.meetings.first?.id,
                        onJoin: { onJoin(meeting) },
                        onSnooze: { onSnooze(meeting) },
                        onDismiss: { onDismiss(meeting) }
                    )
                }
            }
            .padding(40)
        }
    }
}

private struct AlertCard: View {
    let meeting: Meeting
    let isPrimary: Bool
    let onJoin: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "video.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
                .padding(.top, 6)

            VStack(spacing: 6) {
                Text(meeting.title)
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Text(timeRange)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(countdown(at: context.date))
                    .font(.title2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(countdownColor(at: context.date))
                    .contentTransition(.numericText())
            }

            HStack(spacing: 12) {
                Button(action: onSnooze) {
                    Label("Snooze 1 min", systemImage: "zzz")
                        .frame(minWidth: 110)
                }
                .controlSize(.large)

                if meeting.joinURL != nil {
                    Button(action: onJoin) {
                        Label("Join", systemImage: "video.fill")
                            .frame(minWidth: 130)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .if(isPrimary) { $0.keyboardShortcut(.defaultAction) }
                } else if let link = meeting.htmlLink {
                    Button {
                        NSWorkspace.shared.open(link)
                        onDismiss()
                    } label: {
                        Label("Open in Calendar", systemImage: "calendar")
                            .frame(minWidth: 130)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }
            }

            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .if(isPrimary) { $0.keyboardShortcut(.cancelAction) }
                .padding(.bottom, 4)
        }
        .padding(36)
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.1))
        )
        .shadow(color: .black.opacity(0.4), radius: 40, y: 16)
    }

    private var timeRange: String {
        "\(meeting.start.formatted(date: .omitted, time: .shortened)) – \(meeting.end.formatted(date: .omitted, time: .shortened))"
    }

    private func countdown(at now: Date) -> String {
        let seconds = Int(meeting.start.timeIntervalSince(now).rounded())
        if seconds > 0 {
            let minutes = seconds / 60
            let rest = seconds % 60
            return String(format: "Starting in %d:%02d", minutes, rest)
        } else if seconds > -60 {
            return "Starting now"
        } else {
            let minutes = -seconds / 60
            return "Started \(minutes)m ago"
        }
    }

    private func countdownColor(at now: Date) -> Color {
        meeting.start <= now ? .red : .secondary
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
