import Foundation
import Observation
import AVFoundation

#if canImport(UIKit)
import UIKit
#endif

enum RecordingSource: String, CaseIterable, Identifiable {
    case internalMic = "Internal Mic"
    case bluetooth = "Bluetooth"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .bluetooth:
            return "antenna.radiowaves.left.and.right"
        case .internalMic:
            return "mic"
        }
    }
}

struct RecordingOutput {
    let url: URL
    let duration: TimeInterval
    let source: RecordingSource
}

@Observable
@MainActor
class UnifiedRecorder: NSObject {
    
    var isRecording: Bool = false
    var currentDuration: TimeInterval = 0
    var currentSource: RecordingSource = .internalMic
    
    private let internalRecorder = AudioRecorder()
    private let connectionManager = DeviceConnectionManager.shared
    private var audioStreamReceiver: AudioStreamReceiver?
    
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var bleAudioBuffer: [Float] = []
    
    override init() {
        self.audioStreamReceiver = AudioStreamReceiver(connectionManager: .shared)
        super.init()
        
        updateSourceBasedOnConnection()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectionStateChanged),
            name: .connectionStateDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func connectionStateChanged() {
        updateSourceBasedOnConnection()
    }
    
    func updateSourceBasedOnConnection() {
        guard !isRecording else { return }
        
        let newSource: RecordingSource
        switch connectionManager.connectionState {
        case .connected, .initialized, .bound:
            newSource = .bluetooth
        default:
            newSource = .internalMic
        }
        
        if currentSource != newSource {
            currentSource = newSource
            print("[UnifiedRecorder] Switched source to: \(newSource)")
        }
    }
    
    var isBluetoothConnected: Bool {
        switch connectionManager.connectionState {
        case .connected, .initialized, .bound:
            return true
        default:
            return false
        }
    }
    
    var isAvailable: Bool {
        return !isRecording
    }
    
    func startRecording() {
        guard !isRecording else {
            print("[UnifiedRecorder] Already recording, ignoring start request")
            return
        }
        
        updateSourceBasedOnConnection()
        
        isRecording = true
        recordingStartTime = Date()
        currentDuration = 0
        bleAudioBuffer.removeAll()
        
        startDurationTimer()
        
        switch currentSource {
        case .bluetooth:
            print("[UnifiedRecorder] Starting BLE recording...")
            startBLERecording()
        case .internalMic:
            print("[UnifiedRecorder] Starting internal mic recording...")
            startInternalMicRecording()
        }
        
        triggerHapticFeedback()
    }
    
    func stopRecording(completion: @escaping (RecordingOutput?) -> Void) {
        guard isRecording else {
            print("[UnifiedRecorder] Not recording, cannot stop")
            completion(nil)
            return
        }
        
        stopDurationTimer()
        
        switch currentSource {
        case .bluetooth:
            stopBLERecording(completion: completion)
        case .internalMic:
            stopInternalMicRecording(completion: completion)
        }
        
        triggerHapticFeedback()
    }
    
    private func startBLERecording() {
        guard let receiver = audioStreamReceiver else {
            print("[UnifiedRecorder] AudioStreamReceiver not available")
            isRecording = false
            return
        }
        
        do {
            try receiver.startStreaming()
            print("[UnifiedRecorder] BLE streaming started")
        } catch {
            print("[UnifiedRecorder] Failed to start BLE streaming: \(error)")
            isRecording = false
        }
    }
    
    private func stopBLERecording(completion: @escaping (RecordingOutput?) -> Void) {
        guard let receiver = audioStreamReceiver else {
            isRecording = false
            completion(nil)
            return
        }
        
        receiver.stopStreaming()
        
        let frames = receiver.flush()
        var allSamples: [Float] = []
        
        for frame in frames {
            let samples = frame.data.withUnsafeBytes { buffer in
                guard let floatBuffer = buffer.bindMemory(to: Float.self).baseAddress else { return [Float]() }
                return Array(UnsafeBufferPointer(start: floatBuffer, count: buffer.count / MemoryLayout<Float>.size))
            }
            allSamples.append(contentsOf: samples)
        }
        
        isRecording = false
        
        guard !allSamples.isEmpty else {
            print("[UnifiedRecorder] No BLE audio data recorded")
            completion(nil)
            return
        }
        
        let url = saveBLEAudio(samples: allSamples)
        
        if let url = url {
            let output = RecordingOutput(
                url: url,
                duration: currentDuration,
                source: .bluetooth
            )
            completion(output)
        } else {
            completion(nil)
        }
    }
    
    private func startInternalMicRecording() {
        let sessionID = UUID().uuidString
        internalRecorder.currentRecordingSessionID = sessionID
        _ = internalRecorder.toggleRecording()
    }
    
    private func stopInternalMicRecording(completion: @escaping (RecordingOutput?) -> Void) {
        let sessionID = internalRecorder.currentRecordingSessionID
        _ = internalRecorder.toggleRecording()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            
            self.isRecording = false
            
            guard let sessionID = sessionID else {
                completion(nil)
                return
            }
            
            let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = documentPath.appendingPathComponent("\(sessionID).m4a")
            
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("[UnifiedRecorder] Internal mic recording file not found: \(url.path)")
                completion(nil)
                return
            }
            
            let output = RecordingOutput(
                url: url,
                duration: self.currentDuration,
                source: .internalMic
            )
            completion(output)
        }
    }
    
    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
    
    private func saveBLEAudio(samples: [Float]) -> URL? {
        guard !samples.isEmpty else { return nil }
        
        let sessionID = UUID().uuidString
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = documentPath.appendingPathComponent("\(sessionID).caf")
        
        do {
            let cafData = createCAFFile(samples: samples, sampleRate: 16000)
            try cafData.write(to: outputURL)
            print("[UnifiedRecorder] BLE audio saved: \(outputURL.lastPathComponent) (\(samples.count) samples)")
            return outputURL
        } catch {
            print("[UnifiedRecorder] Failed to save CAF: \(error)")
            return nil
        }
    }
    
    private func createCAFFile(samples: [Float], sampleRate: Double) -> Data {
        let bytesPerSample = MemoryLayout<Float>.stride
        let dataSize = UInt64(samples.count * bytesPerSample)
        
        var cafData = Data()
        
        // File header
        cafData.append("caff".data(using: .ascii)!)
        cafData.append(UInt16(1).bigEndianData)
        cafData.append(UInt16(0).bigEndianData)
        
        // Audio Description chunk
        cafData.append("desc".data(using: .ascii)!)
        cafData.append(UInt64(32).bigEndianData)
        
        // AudioDescription (32 bytes, big-endian)
        var rate = sampleRate
        withUnsafeBytes(of: &rate) { cafData.append(contentsOf: $0.reversed()) }
        cafData.append(UInt32(1819304813).bigEndianData)
        cafData.append(UInt32(1).bigEndianData)
        cafData.append(UInt32(bytesPerSample).bigEndianData)
        cafData.append(UInt32(1).bigEndianData)
        cafData.append(UInt32(1).bigEndianData)
        cafData.append(UInt32(32).bigEndianData)
        
        // Audio Data chunk
        cafData.append("data".data(using: .ascii)!)
        cafData.append(UInt64(dataSize + 4).bigEndianData)
        cafData.append(UInt32(0).bigEndianData)
        
        // Audio samples
        cafData.append(Data(bytes: samples, count: Int(dataSize)))
        
        return cafData
    }
    
    private func triggerHapticFeedback() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}

extension FixedWidthInteger {
    var bigEndianData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
