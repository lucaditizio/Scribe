import Foundation
import AVFoundation
import Observation

enum RecordingState: Equatable {
    case idle
    case recording
    case stopped
}

@Observable
@MainActor
class BleAudioRecorder: NSObject {
    var state: RecordingState = .idle
    var currentDuration: TimeInterval = 0

    private var audioDataObserver: NSObjectProtocol?
    private var connectionObserver: NSObjectProtocol?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private let audioQueue = DispatchQueue(label: "com.scribe.bleAudioRecorder", qos: .userInitiated)
    private var decoder: OpusAudioDecoder?
    private var audioBuffer: [Float] = []

    private let sampleRate: Double = 16000
    private let channels: UInt32 = 1

    override init() {
        super.init()
        setupDecoder()
        setupConnectionObserver()
    }
    
    deinit {
        Task { @MainActor in
            _ = stopRecording()
            removeObservers()
        }
    }
    
    private func setupDecoder() {
        do {
            decoder = try OpusAudioDecoder(sampleRate: Int(sampleRate), channels: Int(channels))
        } catch {
            print("[BleAudioRecorder] Failed to initialize Opus decoder: \(error)")
        }
    }
    
    private func setupConnectionObserver() {
        connectionObserver = NotificationCenter.default.addObserver(
            forName: .connectionStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleConnectionStateChange(notification)
            }
        }
    }
    
    func startRecording() {
        guard state == .idle || state == .stopped else {
            print("[BleAudioRecorder] Cannot start recording: already recording")
            return
        }
        
        audioBuffer.removeAll()
        state = .recording
        recordingStartTime = Date()
        currentDuration = 0
        
        startDurationTimer()
        
        audioDataObserver = NotificationCenter.default.addObserver(
            forName: .audioCharacteristicDidUpdate,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioDataNotification(notification)
            }
        }
        
        print("[BleAudioRecorder] Recording started")
    }
    
    func stopRecording() -> (url: URL?, duration: TimeInterval) {
        guard state == .recording else {
            print("[BleAudioRecorder] Cannot stop recording: not currently recording")
            return (nil, 0)
        }

        state = .stopped
        stopDurationTimer()
        removeAudioDataObserver()

        let duration = currentDuration
        print("[BleAudioRecorder] Recording stopped, encoding \(audioBuffer.count) samples...")

        let samples = audioBuffer
        let url = encodeAndSaveAudio(samples: samples)

        audioBuffer.removeAll()
        recordingStartTime = nil
        currentDuration = 0

        return (url, duration)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func handleAudioDataNotification(_ notification: Notification) {
        guard state == .recording else { return }
        
        guard let data = notification.userInfo?["data"] as? Data else {
            return
        }
        
        guard let decoder = decoder else { return }
        
        do {
            let pcmSamples = try decoder.decode(data)
            audioBuffer.append(contentsOf: pcmSamples)
        } catch {
            print("[BleAudioRecorder] Failed to decode audio data: \(error)")
        }
    }
    
    nonisolated func handleAudioData(_ data: [Float]) {
        Task { @MainActor [weak self] in
            guard let self = self, self.state == .recording else { return }
            self.audioBuffer.append(contentsOf: data)
        }
    }
    
    private func startDurationTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopDurationTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    private func removeAudioDataObserver() {
        if let observer = audioDataObserver {
            NotificationCenter.default.removeObserver(observer)
            audioDataObserver = nil
        }
    }
    
    private func removeObservers() {
        removeAudioDataObserver()
        if let observer = connectionObserver {
            NotificationCenter.default.removeObserver(observer)
            connectionObserver = nil
        }
    }
    
    private func handleConnectionStateChange(_ notification: Notification) {
        guard state == .recording else { return }

        guard let userInfo = notification.userInfo,
              let connectionState = userInfo["state"] as? ConnectionState else {
            return
        }

        if connectionState == .disconnected {
            print("[BleAudioRecorder] Device disconnected while recording, stopping and saving...")
            _ = stopRecording()
        }
    }
    
    private func encodeAndSaveAudio(samples: [Float]) -> URL? {
        guard !samples.isEmpty else {
            print("[BleAudioRecorder] No audio data to save")
            return nil
        }
        
        do {
            try RecordingsStorage.ensureRecordingsDirectoryExists()
        } catch {
            print("[BleAudioRecorder] Failed to create recordings directory: \(error)")
            return nil
        }
        
        let filename = generateRecordingFilename()
        let outputURL = RecordingsStorage.recordingsDirectory().appendingPathComponent(filename)
        
        do {
            let cafData = createCAFFile(samples: samples, sampleRate: 16000)
            try cafData.write(to: outputURL)
            print("[BleAudioRecorder] Audio saved to: \(outputURL.path) (\(samples.count) samples, 16kHz Float32 CAF)")
            return outputURL
        } catch {
            print("[BleAudioRecorder] Failed to write CAF data: \(error)")
            return nil
        }
    }
    
    private func createCAFFile(samples: [Float], sampleRate: Double) -> Data {
        let bytesPerSample = MemoryLayout<Float>.stride
        let dataSize = UInt64(samples.count * bytesPerSample)
        
        var cafData = Data()
        
        cafData.append("caff".data(using: .ascii)!)
        cafData.append(UInt16(1).bigEndianBytes)
        cafData.append(UInt16(0).bigEndianBytes)
        
        cafData.append("desc".data(using: .ascii)!)
        let descSize: UInt64 = 40
        cafData.append(descSize.bigEndianBytes)
        
        cafData.append(UInt32(1819304813).bigEndianBytes)
        cafData.append(UInt32(41).bigEndianBytes)
        cafData.append(sampleRate.bitPattern.bigEndianBytes)
        cafData.append(UInt32(1).bigEndianBytes)
        cafData.append(UInt32(bytesPerSample).bigEndianBytes)
        cafData.append(UInt32(bytesPerSample).bigEndianBytes)
        cafData.append(UInt32(1).bigEndianBytes)
        cafData.append(UInt32(32).bigEndianBytes)
        
        cafData.append("data".data(using: .ascii)!)
        let dataChunkSize: UInt64 = dataSize + 4
        cafData.append(dataChunkSize.bigEndianBytes)
        cafData.append(UInt32(0).bigEndianBytes)
        
        let sampleData = Data(bytes: samples, count: Int(dataSize))
        cafData.append(sampleData)
        
        return cafData
    }
    
    private func generateRecordingFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "Recording_\(timestamp).caf"
    }
}

extension FixedWidthInteger {
    var littleEndianBytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
    
    var bigEndianBytes: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}

extension Notification.Name {
    static let connectionStateDidChange = Notification.Name("com.scribe.connectionStateDidChange")
}