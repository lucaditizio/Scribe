import SwiftUI
import SwiftData

struct RecordingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @Environment(\.colorScheme) var colorScheme
    
    private let scanner: BluetoothDeviceScanner
    private let connectionManager: DeviceConnectionManager
    private let bleRecorder: BleAudioRecorder
    
    @State private var showingDeviceSettings = false
    @State private var currentDuration: TimeInterval = 0
    @State private var isRecording = false
    
    init() {
        let scanner = BluetoothDeviceScanner()
        let mgr = DeviceConnectionManager(scanner: scanner)
        let recorder = BleAudioRecorder()
        self.scanner = scanner
        self.connectionManager = mgr
        self.bleRecorder = recorder
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
                        DeviceSettingsView(bleRecorder: bleRecorder)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button("Done") {
                                        showingDeviceSettings = false
                                    }
                                    .foregroundStyle(Theme.scribeRed)
                                }
                            }
                    }
                }
                
                // Floating Record Context
                VStack {
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
                        bleRecorder: bleRecorder,
                        connectionManager: connectionManager,
                        currentDuration: $currentDuration,
                        isRecording: $isRecording
                    ) { duration, fileURL in
                        if let url = fileURL {
                            saveRecording(duration: duration, fileURL: url)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }
    
    private func saveRecording(duration: TimeInterval, fileURL: URL) {
        let filename = fileURL.lastPathComponent
        let id = filename.replacingOccurrences(of: ".m4a", with: "")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = formatter.string(from: Date())
        let title = "Recording \(timestamp)"
        
        let newRecording = Recording(
            id: id,
            title: title,
            duration: duration,
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
            try? FileManager.default.removeItem(at: fileURL)
            modelContext.delete(recording)
        }
        try? modelContext.save()
    }
}

#Preview {
    RecordingListView()
        .preferredColorScheme(.dark)
}
