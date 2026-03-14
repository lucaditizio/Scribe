import SwiftUI
import SwiftData

struct RecordingCardView: View {
    @Environment(\.colorScheme) var colorScheme
    let recording: Recording
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(recording.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(2)
                
                Spacer()
                
                Text(formatDuration(recording.duration))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
            
            HStack {
                Text(recording.categoryTag)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.scribeRed.opacity(0.15))
                    .foregroundColor(Theme.scribeRed)
                    .clipShape(Capsule())
                
                Spacer()
                
                Text(recording.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(recording.createdAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .scribeCardStyle(scheme: colorScheme)
        .padding(.horizontal)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }
}
