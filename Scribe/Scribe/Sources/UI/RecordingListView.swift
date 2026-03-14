import SwiftUI
import SwiftData

struct RecordingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @Environment(\.colorScheme) var colorScheme
    
    // Audio Engine State
    @State private var audioRecorder = AudioRecorder()
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Main Content
                ScrollView {
                    VStack(spacing: 16) {
                        DashboardHeaderView()
                            .padding(.bottom, 8)
                        
                        // Recordings List
                        if recordings.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "mic.slash")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("No recordings yet.")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 40)
                        } else {
                            ForEach(recordings) { recording in
                                NavigationLink(destination: RecordingDetailView(recording: recording)) {
                                    RecordingCardView(recording: recording)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        // Padding for the floating record button
                        Spacer().frame(height: 100)
                    }
                }
                .navigationTitle("Scribe")
                .background(colorScheme == .dark ? Color.black : Color.gray.opacity(0.1))
                
                // Floating Record Context
                VStack {
                    if audioRecorder.isRecording {
                        Text(formatDuration(audioRecorder.currentTime))
                            .font(.system(.title, design: .monospaced).weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Theme.scribeRed.opacity(0.8))
                            .clipShape(Capsule())
                            .shadow(color: Theme.scribeRed.opacity(0.3), radius: 5, y: 3)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    RecordButtonView(audioRecorder: audioRecorder) { duration, sessionID in
                        saveRecording(duration: duration, sessionID: sessionID)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }
    
    private func saveRecording(duration: TimeInterval, sessionID: String) {
        let newRecording = Recording(
            id: sessionID,
            title: "New Recording",
            duration: duration,
            audioFilePath: "\(sessionID).m4a",
            categoryTag: "#NOTE"
        )
        modelContext.insert(newRecording)
        // Auto-save happens periodically in SwiftData, but we can force it if needed
        do {
            try modelContext.save()
        } catch {
            print("Error saving recording: \(error)")
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }
}

#Preview {
    RecordingListView()
        .preferredColorScheme(.dark)
}
