import SwiftUI
import SwiftData

struct RecordingDetailView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Bindable var recording: Recording
    
    // Core Services
    @State private var audioPlayer = AudioPlayer()
    @State private var waveformAnalyzer = WaveformAnalyzer()
    @State private var inferencePipeline = InferencePipeline()
    
    // UI State
    @State private var selectedTab = "Transcript"
    let tabs = ["Transcript", "Summary", "Mind Map"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Half: Player & Waveform
            VStack {
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
                VStack(alignment: .leading) {
                    if inferencePipeline.isProcessing {
                        ProgressHUD(step: inferencePipeline.currentStep, progress: inferencePipeline.progress)
                    } else if selectedTab == "Transcript" {
                        if let transcript = recording.rawTranscript, !transcript.isEmpty {
                            Text(transcript)
                                .font(.body)
                                .lineSpacing(6)
                                .padding()
                        } else {
                            ContentUnavailableView(
                                "No Transcript",
                                systemImage: "text.bubble",
                                description: Text("Tap Transcribe to convert this audio to text.")
                            )
                        }
                    } else {
                         ContentUnavailableView(
                            "Coming Soon",
                            systemImage: "wand.and.stars",
                            description: Text("The \(selectedTab) view will be implemented in Phase 3.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(recording.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if recording.rawTranscript == nil && !inferencePipeline.isProcessing {
                    Button("Transcribe") {
                        Task {
                            await inferencePipeline.process(recording: recording, modelContext: modelContext)
                        }
                    }
                    .fontWeight(.bold)
                    .foregroundColor(Theme.scribeRed)
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
