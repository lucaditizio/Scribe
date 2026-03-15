import SwiftUI
import SwiftData

struct RecordingDetailView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var recording: Recording
    
    // Core Services
    @State private var audioPlayer = AudioPlayer()
    @State private var waveformAnalyzer = WaveformAnalyzer()
    @State private var inferencePipeline = InferencePipeline()
    
    // UI State
    @State private var selectedTab = "Summary"
    let tabs = ["Summary", "Transcript", "Mind Map"]
    
    // Rename Speaker State
    @State private var showingRenameAlert = false
    @State private var showingDeleteAlert = false
    @State private var speakerToRename = ""
    @State private var newSpeakerName = ""
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
            // Top Half: Player & Waveform
            VStack {
                if let errorMsg = audioPlayer.errorLog {
                    Text(errorMsg)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                WaveformView(
                    samples: waveformAnalyzer.samples,
                    progress: waveformAnalyzer.samples.isEmpty ? 0 : CGFloat(audioPlayer.currentTime / audioPlayer.duration),
                    isAnalyzing: waveformAnalyzer.isAnalyzing
                )
                .frame(height: 100)
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Audio Controls
                HStack(spacing: 40) {
                    Button(action: { audioPlayer.skipBackward() }) {
                        Image(systemName: "gobackward.15")
                            .font(.title2)
                    }
                    
                    Button(action: { audioPlayer.togglePlayback() }) {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Theme.scribeRed)
                    }
                    
                    Button(action: { audioPlayer.skipForward() }) {
                        Image(systemName: "goforward.15")
                            .font(.title2)
                    }
                    
                    Button(action: { audioPlayer.cycleSpeed() }) {
                        Text("\(audioPlayer.currentSpeed, specifier: "%.1f")x")
                            .font(.callout.weight(.bold))
                            .frame(width: 44)
                            .padding(8)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .foregroundColor(.primary)
                .padding(.vertical, 20)
            }
            .scribeCardStyle(scheme: colorScheme)
            .padding()
            
            // Bottom Half: Pipeline Tabs
            Picker("View", selection: $selectedTab) {
                ForEach(tabs, id: \.self) { tab in
                    Text(tab).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 16)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if inferencePipeline.isProcessing {
                        if #available(iOS 18.0, *) {
                            AgentGeneratingView(progressText: $inferencePipeline.currentStep, progressValue: $inferencePipeline.progress)
                                .frame(height: 400)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            ProgressHUD(step: inferencePipeline.currentStep, progress: inferencePipeline.progress)
                        }
                    } else if selectedTab == "Transcript" {
                        if let transcript = recording.rawTranscript, !transcript.isEmpty {
                            TranscriptInteractiveView(
                                transcript: transcript,
                                onRenameSpeaker: { speaker in
                                    speakerToRename = speaker
                                    newSpeakerName = ""
                                    showingRenameAlert = true
                                }
                            )
                            .padding()
                        } else {
                            ContentUnavailableView("No Transcript", systemImage: "text.bubble", description: Text("Tap Transcribe to start."))
                        }
                    } else if selectedTab == "Summary" {
                        if let notesJSON = recording.meetingNotes, !notesJSON.isEmpty {
                            VStack(alignment: .leading, spacing: 24) {
                                
                                // --- Meeting Notes (structured topics) ---
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("📝 Meeting Notes")
                                        .font(.title3.weight(.bold))
                                    
                                    // Try to decode as [TopicSection]; fall back to plain text
                                    if let sections = try? JSONDecoder().decode(
                                            [TopicSection].self,
                                            from: Data(notesJSON.utf8)
                                    ), !sections.isEmpty {
                                        ForEach(sections, id: \.topic) { section in
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(section.topic)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(Theme.scribeRed)
                                                ForEach(section.bullets, id: \.self) { bullet in
                                                    HStack(alignment: .top, spacing: 8) {
                                                        Text("•")
                                                            .foregroundColor(.secondary)
                                                        Text(bullet)
                                                            .font(.body)
                                                            .lineSpacing(3)
                                                    }
                                                }
                                            }
                                        }
                                    } else {
                                        // Legacy plain-text fallback
                                        Text(notesJSON)
                                            .font(.body)
                                            .lineSpacing(4)
                                    }
                                }
                                
                                // --- Action Items ---
                                if let actions = recording.actionItems, !actions.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("✅ Action Items")
                                            .font(.title3.weight(.bold))
                                        
                                        // Parse "- item\n- item" Markdown into styled bullets
                                        let items = actions
                                            .components(separatedBy: "\n")
                                            .map { $0.trimmingCharacters(in: .whitespaces) }
                                            .filter { !$0.isEmpty }
                                            .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
                                        
                                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text("•")
                                                    .foregroundColor(.secondary)
                                                Text(item)
                                                    .font(.body)
                                                    .lineSpacing(3)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding()
                        } else {
                            ContentUnavailableView("No Summary", systemImage: "doc.text.magnifyingglass", description: Text("Generate a transcript to use Llama-3.2."))
                        }
                    } else if selectedTab == "Mind Map" {
                        if let mindMapData = recording.mindMapJSON,
                           let nodes = try? JSONDecoder().decode([MindMapNode].self, from: mindMapData) {
                            MindMapView(nodes: nodes)
                                .padding()
                        } else {
                            ContentUnavailableView("No Mind Map", systemImage: "network", description: Text("Generate a transcript to extract JSON tree nodes."))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        
        // Floating Transcribe Button Overlay
        if recording.rawTranscript == nil && !inferencePipeline.isProcessing {
            Button(action: {
                Task {
                    await inferencePipeline.process(recording: recording, modelContext: modelContext)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path")
                    Text("Generate Transcript")
                        .fontWeight(.bold)
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.vertical, 16)
                .padding(.horizontal, 32)
                .background(Theme.scribeRed)
                .clipShape(Capsule())
                .shadow(color: Theme.scribeRed.opacity(0.4), radius: 10, y: 5)
            }
            .padding(.bottom, 32)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(), value: recording.rawTranscript == nil)
        }
    }
        .navigationTitle(recording.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            audioPlayer.load(recording: recording)
            Task {
                await waveformAnalyzer.analyze(audioFilePath: recording.audioFilePath)
            }
        }
        .onDisappear {
            if audioPlayer.isPlaying {
                audioPlayer.togglePlayback()
            }
        }
        .alert("Rename Participant", isPresented: $showingRenameAlert) {
            TextField("New Name", text: $newSpeakerName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                if !newSpeakerName.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Globally replace the speaker name in the Transcript
                    let updatedTranscript = recording.rawTranscript?.replacingOccurrences(of: speakerToRename, with: newSpeakerName)
                    recording.rawTranscript = updatedTranscript
                    
                    // Globally replace the speaker name in the Action Items
                    if let actionItems = recording.actionItems {
                        recording.actionItems = actionItems.replacingOccurrences(of: speakerToRename, with: newSpeakerName)
                    }
                }
            }
        } message: {
            Text("Enter a real name for \(speakerToRename). This will update the transcript and action items.")
        }
        .alert("Delete Recording", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteRecording()
            }
        } message: {
            Text("Are you sure? This will delete the audio file and all generated notes.")
        }
    }
    
    private func deleteRecording() {
        if audioPlayer.isPlaying { audioPlayer.togglePlayback() }
        let docPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = docPath.appendingPathComponent(recording.audioFilePath)
        try? FileManager.default.removeItem(at: audioURL)
        modelContext.delete(recording)
        dismiss()
    }
}

// MARK: - Subviews

struct WaveformView: View {
    let samples: [Float]
    let progress: CGFloat
    let isAnalyzing: Bool
    
    var body: some View {
        GeometryReader { geometry in
            if isAnalyzing {
                HStack(spacing: 4) {
                    Spacer()
                    ProgressView("Analyzing audio...")
                        .controlSize(.small)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else if samples.isEmpty {
                // Fallback flat line if no audio found
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 2)
                    .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<samples.count, id: \.self) { index in
                        let sampleProgress = CGFloat(index) / CGFloat(samples.count)
                        let isPlayed = sampleProgress <= progress
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isPlayed ? Theme.scribeRed : Color.secondary.opacity(0.3))
                            // Multiply the sample float (0.0 - 1.0) by available height
                            .frame(height: max(geometry.size.height * CGFloat(samples[index]), 4))
                    }
                }
                // Center vertically
                .frame(maxHeight: .infinity)
            }
        }
    }
}

struct ProgressHUD: View {
    let step: String
    let progress: Double
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Theme.scribeRed)
            
            Text(step)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Scribe limits memory to 6GB by sequencing ML bounds.")
                .font(.footnote)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding()
    }
}

// Minimal recursive MindMap drawing using JSON Structure
struct MindMapView: View {
    let nodes: [MindMapNode]
    var depth: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(nodes, id: \.id) { node in
                HStack(alignment: .top) {
                    // Tree branch drawing
                    if depth > 0 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 2, height: 24)
                            .padding(.leading, 12)
                        
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 16, height: 2)
                            .offset(y: 11)
                    }
                    
                    VStack(alignment: .leading) {
                        Text(node.text)
                            .font(depth == 0 ? .headline : .subheadline)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(depth == 0 ? Theme.scribeRed.opacity(0.8) : Color.secondary.opacity(0.15))
                            .foregroundColor(depth == 0 ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        // Recurse down the tree
                        if let children = node.children, !children.isEmpty {
                            MindMapView(nodes: children, depth: depth + 1)
                                .padding(.leading, 8)
                        }
                    }
                }
            }
        }
    }
}
    
// Interactive Transcript View to isolate Speaker Tags
struct TranscriptInteractiveView: View {
    let transcript: String
    let onRenameSpeaker: (String) -> Void
        
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                // Split Transcript by lines to find Speaker tags [Speaker N - MM:SS]
                let segments = parseTranscript(transcript)
                
                ForEach(segments, id: \.id) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(segment.speaker)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(Theme.scribeRed)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.scribeRed.opacity(0.1))
                                .clipShape(Capsule())
                                .onTapGesture {
                                    onRenameSpeaker(segment.speaker)
                                }
                            
                            Text(segment.timestamp)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                        
                        Text(segment.text)
                            .font(.body)
                            .lineSpacing(6)
                            .padding(.leading, 4)
                    }
                }
            }
        }
        
        // Very simple parser for the [Speaker N - MM:SS] formatting
        struct TranscriptSegment: Identifiable {
            let id = UUID()
            let speaker: String
            let timestamp: String
            let text: String
        }
        
        private func parseTranscript(_ text: String) -> [TranscriptSegment] {
            var segments: [TranscriptSegment] = []
            let lines = text.components(separatedBy: "\n")
            
            var currentSpeaker = "Unknown"
            var currentTimestamp = "00:00"
            var currentBlockText = ""
            
            // Regex to match [Speaker 1 - 00:15]
            let regex = try? NSRegularExpression(pattern: "\\[(.*?) - (.*?)\\]")
            
            for line in lines {
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                if let match = regex?.firstMatch(in: line, range: nsRange) {
                    // If we already built a block, save it before starting the new one
                    if !currentBlockText.isEmpty {
                        segments.append(TranscriptSegment(speaker: currentSpeaker, timestamp: currentTimestamp, text: currentBlockText.trimmingCharacters(in: .whitespacesAndNewlines)))
                        currentBlockText = ""
                    }
                    
                    // Extract new Speaker and Timestamp
                    if let speakerRange = Range(match.range(at: 1), in: line),
                       let timeRange = Range(match.range(at: 2), in: line) {
                        currentSpeaker = String(line[speakerRange])
                        currentTimestamp = String(line[timeRange])
                    }
                } else {
                    currentBlockText += line + " "
                }
            }
            
            // Append the final block
            if !currentBlockText.isEmpty {
                segments.append(TranscriptSegment(speaker: currentSpeaker, timestamp: currentTimestamp, text: currentBlockText.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            
            return segments
        }
    }
