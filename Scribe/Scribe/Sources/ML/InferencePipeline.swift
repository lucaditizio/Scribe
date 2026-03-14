import Foundation
import SwiftData
import Speech
import FluidAudio

/// Transcription service using FluidAudio to automatically manage CoreML Parakeet bounds
class TranscriptionService {
    func transcribe(fileName: String, progressCallback: @escaping (String, Double) -> Void) async throws -> String {
        await MainActor.run { progressCallback("Downloading/Loading Parakeet...", 0.1) }
        
        // FluidAudio natively handles CoreML downloading and caching
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let asrManager = AsrManager(config: .default)
        try await asrManager.initialize(models: models)
        
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentPath.appendingPathComponent(fileName)
        
        await MainActor.run { progressCallback("Extracting Audio & Transcribing...", 0.3) }
        
        // Let the SDK natively handle the audio URL formatting
        let result = try await asrManager.transcribe(fileURL, source: .system)
        
        asrManager.cleanup()
        return result.text
    }
}

/// Diarization service using Apple's Native Offline SFSpeechRecognizer
class DiarizationService {
    func diarize(fileName: String, progressCallback: @escaping (String, Double) -> Void) async throws -> [(speaker: String, text: String)] {
        await MainActor.run { progressCallback("Requesting Speech Recognition Authorization...", 0.6) }
        
        // Wrap Apple's callback API in a modern async continuation
        let authStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard authStatus == .authorized else {
            throw NSError(domain: "DiarizationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized."])
        }
        
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentPath.appendingPathComponent(fileName)
        
        await MainActor.run { progressCallback("Native Speaker Clustering...", 0.7) }
        
        // Apple Native initialization
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            throw NSError(domain: "DiarizationService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Recognizer unavailable."])
        }
        recognizer.supportsOnDeviceRecognition = true
        
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result = result, result.isFinal else { return }
                
                var segments: [(speaker: String, text: String)] = []
                #if os(iOS)
                // SFSpeechRecognitionResult natively groups by speaker if voiceAnalytics/metadata is available in some contexts,
                // However, for strict diarization mapping we usually align timestamps. 
                // For Phase 2b, we will just return the block since Apple's native offline mapping is limited.
                segments.append((speaker: "Speaker 1", text: result.bestTranscription.formattedString))
                #else
                segments.append((speaker: "Speaker 1", text: result.bestTranscription.formattedString))
                #endif
                
                continuation.resume(returning: segments)
            }
        }
    }
}

@Observable
class InferencePipeline {
    var isProcessing = false
    var currentStep = ""
    var progress: Double = 0.0
    
    // Strict Sequential Execution
    func process(recording: Recording, modelContext: ModelContext) async {
        await MainActor.run {
            self.isProcessing = true
            self.progress = 0.1
            self.currentStep = "Loading ASR Model..."
        }
        
        // --- STEP 1: TRANSCRIBE ---
        let rawText: String
        do {
            var transcriber: TranscriptionService? = TranscriptionService()
            rawText = try await transcriber!.transcribe(fileName: recording.audioFilePath) { step, prog in
                Task { @MainActor in
                    self.currentStep = step
                    self.progress = prog
                }
            }
            transcriber = nil
        } catch {
            print("Transcription Failed: \(error)")
            await finalizeProcessing()
            return
        }
        
        // --- STEP 2: DIARIZE ---
        let speakerSegments: [(speaker: String, text: String)]
        do {
            var diarizer: DiarizationService? = DiarizationService()
            speakerSegments = try await diarizer!.diarize(fileName: recording.audioFilePath) { step, prog in
                Task { @MainActor in
                    self.currentStep = step
                    self.progress = prog
                }
            }
            diarizer = nil
        } catch {
            print("Diarization Failed: \(error)")
            // Fallback: If SFSpeechRecognizer fails, just use the FluidAudio raw text
            speakerSegments = [(speaker: "Speaker", text: rawText)]
        }
        
        // --- STEP 3: MERGE ---
        await MainActor.run {
            self.progress = 0.9
            self.currentStep = "Formatting Notecard..."
        }
        
        // Merge the speaker segments (or default to raw ASR text if Diarization didn't provide granularity)
        let finalTranscript: String
        if speakerSegments.count > 0 {
            finalTranscript = "[\(speakerSegments[0].speaker) - 00:00]\n" + rawText
        } else {
            finalTranscript = rawText
        }
        
        await MainActor.run {
            recording.rawTranscript = finalTranscript
            self.progress = 1.0
            self.currentStep = "Saving Note..."
        }
        
        // Save to SwiftData
        do {
            try modelContext.save()
        } catch {
            print("Failed to save transcript: \(error)")
        }
        
        // Wait a beat to let user see "100%"
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        await finalizeProcessing()
    }
    
    @MainActor
    private func finalizeProcessing() {
        self.isProcessing = false
        self.currentStep = ""
        self.progress = 0.0
    }
}
