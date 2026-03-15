import Foundation
import SwiftData
import AVFoundation
import FluidAudio

// MARK: - Transcription

class TranscriptionService {
    private var asrManager: AsrManager?

    func prepare(progressCallback: @escaping (String, Double) -> Void) async throws {
        await MainActor.run { progressCallback("Downloading/Loading Parakeet...", 0.1) }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        self.asrManager = manager
    }

    func transcribe(samples: [Float]) async throws -> String {
        guard let manager = asrManager else { throw NSError(domain: "ASR", code: 0, userInfo: nil) }
        // For segments that are completely silent or too short, Parakeet might fail. Catch safely.
        guard samples.count > 8000 else { return "" } // > 0.5 sec required
        
        let result = try await manager.transcribe(samples)
        return result.text
    }

    func cleanup() {
        asrManager?.cleanup()
        asrManager = nil
    }
}

// MARK: - Diarization

class DiarizationService {
    struct SpeakerSegment {
        let speakerId: String   // e.g. "Speaker 1"
        let start: Double       // seconds
        let end: Double         // seconds
    }

    func diarize(fileURL: URL, progressCallback: @escaping (String, Double) -> Void) async throws -> [SpeakerSegment] {
        await MainActor.run { progressCallback("Loading Diarization Models...", 0.45) }

        // Lower clustering threshold massively to force separation on mono-mic recordings
        var config = OfflineDiarizerConfig(clusteringThreshold: 0.35)
        // Bound speakers to give the algorithm realistic meeting expectations
        config = config.withSpeakers(min: 1, max: 8)
        
        let manager = OfflineDiarizerManager(config: config)
        try await manager.prepareModels()

        await MainActor.run { progressCallback("Identifying Speakers...", 0.55) }
        let result = try await manager.process(fileURL)

        return result.segments.map { segment in
            let rawNumStr = segment.speakerId.replacingOccurrences(of: "SPEAKER_", with: "")
            let cleanNum = (Int(rawNumStr) ?? 0) + 1
            return SpeakerSegment(
                speakerId: "Speaker \(cleanNum)",
                start: Double(segment.startTimeSeconds),
                end: Double(segment.endTimeSeconds)
            )
        }
    }
}

// MARK: - Transcript Assembler

private func formatTimestamp(seconds: Double) -> String {
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return String(format: "%02d:%02d", m, s)
}

// MARK: - Audio Duration Helper

private func audioDuration(fileURL: URL) async -> Double {
    let asset = AVURLAsset(url: fileURL)
    // .duration is deprecated in iOS 16 — use async load(.duration)
    if let duration = try? await asset.load(.duration) {
        return duration.seconds
    }
    return 0
}

// MARK: - Inference Pipeline

@Observable
class InferencePipeline {
    var isProcessing = false
    var currentStep = ""
    var progress: Double = 0.0

    func process(recording: Recording, modelContext: ModelContext) async {
        await MainActor.run {
            self.isProcessing = true
            self.progress = 0.05
            self.currentStep = "Loading ASR Model..."
        }

        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentPath.appendingPathComponent(recording.audioFilePath)

        // --- STEP 1: DIARIZE FIRST ---
        var speakerSegments: [DiarizationService.SpeakerSegment] = []
        let duration = await audioDuration(fileURL: fileURL)
        do {
            var diarizer: DiarizationService? = DiarizationService()
            speakerSegments = try await diarizer!.diarize(fileURL: fileURL) { step, prog in
                Task { @MainActor in self.currentStep = step; self.progress = prog }
            }
            diarizer = nil
            print("[InferencePipeline] ✅ Diarization: \(speakerSegments.count) segments")
        } catch {
            print("[InferencePipeline] ⚠️ Diarization failed — using single speaker: \(error)")
            speakerSegments = [DiarizationService.SpeakerSegment(speakerId: "Speaker 1", start: 0, end: duration)]
        }

        // --- STEP 2: LOAD RAW AUDIO ---
        await MainActor.run { self.currentStep = "Loading audio buffer..."; self.progress = 0.60 }
        let allSamples: [Float]
        do {
            allSamples = try await AudioConverter.convertToFloat32(audioURL: fileURL)
        } catch {
            print("[InferencePipeline] ❌ Audio load failed: \(error)")
            await finalizeProcessing(); return
        }

        // --- STEP 3: SEGMENTED TRANSCRIPTION ---
        var finalTranscriptBlocks: [String] = []
        do {
            let transcriber = TranscriptionService()
            try await transcriber.prepare { step, prog in
                Task { @MainActor in self.currentStep = step; self.progress = 0.6 + prog * 0.1 }
            }

            let sampleRate: Double = 16000.0
            for (i, segment) in speakerSegments.enumerated() {
                await MainActor.run { 
                    self.currentStep = "Transcribing \(segment.speakerId)... (\(i+1)/\(speakerSegments.count))"
                    self.progress = 0.70 + (Double(i) / Double(speakerSegments.count)) * 0.15
                }
                
                // Calculate exact array indices for this time block
                let startIndex = Int(max(0, segment.start * sampleRate))
                let endIndex   = Int(min(Double(allSamples.count), segment.end * sampleRate))
                
                guard startIndex < endIndex else { continue }
                let slice = Array(allSamples[startIndex..<endIndex])
                
                let text = try await transcriber.transcribe(samples: slice)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finalTranscriptBlocks.append("[\(segment.speakerId) - \(formatTimestamp(seconds: segment.start))]\n\(text)")
                }
            }
            transcriber.cleanup()
        } catch {
            print("[InferencePipeline] ❌ Transcription failed: \(error)")
            await finalizeProcessing(); return
        }

        let finalTranscript = finalTranscriptBlocks.joined(separator: "\n\n")

        await MainActor.run {
            // If the transcript is empty (due to silence, 0 duration audio, or failure),
            // we MUST explicitly use nil so the UI still allows transcription attempts
            // instead of silently vanishing the button.
            recording.rawTranscript = finalTranscript.isEmpty ? nil : finalTranscript
            self.progress = 0.88
            self.currentStep = "Booting Intelligence Agent..."
        }

        // --- STEP 4: LLM SUMMARY ---
        do {
            var llm: LLMService? = LLMService()
            let agentOutput = try await llm!.generateSummary(transcript: finalTranscript) { step, prog in
                Task { @MainActor in self.currentStep = step; self.progress = prog }
            }
            llm = nil

            await MainActor.run {
                if !agentOutput.title.isEmpty { recording.title = agentOutput.title }

                if let notesData = try? JSONEncoder().encode(agentOutput.meetingNotes) {
                    recording.meetingNotes = String(data: notesData, encoding: .utf8)
                }
                recording.actionItems = agentOutput.actionItems.isEmpty ? nil : agentOutput.actionItems

                if let jsonData = try? JSONEncoder().encode(agentOutput.mindMapNodes) {
                    recording.mindMapJSON = jsonData
                }
            }
        } catch {
            print("[InferencePipeline] ❌ LLM Agent Failed: \(error)")
            await MainActor.run { self.currentStep = "⚠️ LLM Error: \(error.localizedDescription)" }
        }

        await MainActor.run { self.progress = 1.0; self.currentStep = "Saving Intelligence..." }

        do { try modelContext.save() } catch { print("SwiftData save failed: \(error)") }
        try? await Task.sleep(nanoseconds: 500_000_000)
        await finalizeProcessing()
    }

    @MainActor
    private func finalizeProcessing() {
        isProcessing = false; currentStep = ""; progress = 0.0
    }
}
