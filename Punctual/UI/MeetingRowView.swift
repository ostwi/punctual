import SwiftUI

struct MeetingRowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let meeting: Meeting
    let isNext: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(meeting.start.formatted(date: .omitted, time: .shortened))
                    .font(.callout.weight(isNext ? .semibold : .regular))
                    .monospacedDigit()
                Text(meeting.end.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .frame(width: 58, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.callout.weight(isNext ? .semibold : .regular))
                    .lineLimit(1)
                if meeting.isInProgress {
                    Text("Now")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                } else if isNext {
                    Text(meeting.start, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if meeting.joinURL != nil {
                Button("Join") {
                    appState.join(meeting)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(
            isNext ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .opacity(meeting.isInProgress ? 0.9 : 1)
    }
}
