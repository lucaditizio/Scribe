import SwiftUI
import SwiftData

struct RecordingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @Environment(\.colorScheme) var colorScheme
    
    private let unifiedRecorder: UnifiedRecorder
    
    @State private var showingDeviceSettings = false
    @State private var currentDuration: TimeInterval = 0
    @State private var isRecording = false
    
    init() {
        self.unifiedRecorder = UnifiedRecorder()
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Main Content
                List {
                    DashboardHeaderView()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(recordings) { recording in
                            NavigationLink(destination: RecordingDetailView(recording: recording)) {
                                RecordingCardView(recording: recording)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteRecordings)
                    }
                    
                    // Padding for the floating record button
                    Color.clear.frame(height: 100)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(PlainListStyle())
                .scrollContentBackground(.hidden)
                .navigationTitle("Scribe")
                .background(colorScheme == .dark ? Color.black : Color.gray.opacity(0.1))
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingDeviceSettings = true
                        } label: {
                            Image(systemName: "mic.badge.plus")
                                .foregroundStyle(Theme.scribeRed)
                        }
                        .accessibilityLabel("External Microphone")
                    }
                }
                .sheet(isPresented: $showingDeviceSettings) {
                    NavigationStack {
                        DeviceSettingsView()
                    }
                }
                
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: DeviceConnectionManager.shared.connectionState == .connected || DeviceConnectionManager.shared.connectionState == .initialized || DeviceConnectionManager.shared.connectionState == .bound ? "antenna.radiowaves.left.and.right" : "mic")
                            .font(.caption)
                        Text(DeviceConnectionManager.shared.connectionState == .connected || DeviceConnectionManager.shared.connectionState == .initialized || DeviceConnectionManager.shared.connectionState == .bound ? "External Mic" : "Internal Mic")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(Capsule())
                    
                    if isRecording {
                        Text(formatDuration(currentDuration))
                            .font(.system(.title, design: .monospaced).weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Theme.scribeRed.opacity(0.8))
                            .clipShape(Capsule())
                            .shadow(color: Theme.scribeRed.opacity(0.3), radius: 5, y: 3)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    RecordButtonView(
                        unifiedRecorder: unifiedRecorder,
                        currentDuration: $currentDuration,
                        isRecording: $isRecording
                    ) { result in
                        if let result = result {
                            saveRecording(result: result)
                        } else {
                            print("[RecordingListView] Recording failed")
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }
    
    private func saveRecording(result: RecordingOutput) {
        let filename = result.url.lastPathComponent
        // Handle both .m4a and .caf extensions for ID extraction
        let id = filename.replacingOccurrences(of: ".m4a", with: "")
            .replacingOccurrences(of: ".caf", with: "")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = formatter.string(from: Date())
        let title = "Recording \(timestamp)"

        let newRecording = Recording(
            id: id,
            title: title,
            duration: result.duration,
            audioFilePath: filename,
            categoryTag: "#NOTE"
        )
        modelContext.insert(newRecording)
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
    
    private func deleteRecordings(offsets: IndexSet) {
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        for index in offsets {
            let recording = recordings[index]
            let fileURL = documentPath.appendingPathComponent(recording.audioFilePath)
            
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    print("[RecordingListView] Deleted file: \(fileURL.path)")
                }
            } catch {
                print("[RecordingListView] Failed to delete file: \(error)")
            }
            
            modelContext.delete(recording)
        }
        do {
            try modelContext.save()
        } catch {
            print("[RecordingListView] Failed to save context after deletion: \(error)")
        }
    }
}

#Preview {
    RecordingListView()
        .preferredColorScheme(.dark)
}
