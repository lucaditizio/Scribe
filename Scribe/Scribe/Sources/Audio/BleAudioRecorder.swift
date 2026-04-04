import Foundation
import AVFoundation
import Observation
import SwiftData

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
    private var modelContext: ModelContext?

    private let sampleRate: Double = 16000
    private let channels: UInt32 = 1
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
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
        guard state == .idle else {
            print("[BleAudioRecorder] Cannot start recording: already recording or stopped")
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
    
    func stopRecording() -> URL? {
        guard state == .recording else {
            print("[BleAudioRecorder] Cannot stop recording: not currently recording")
            return nil
        }

        state = .stopped
        stopDurationTimer()
        removeAudioDataObserver()

        let duration = currentDuration
        print("[BleAudioRecorder] Recording stopped, encoding \(audioBuffer.count) samples...")

        let samples = audioBuffer
        let url = encodeAndSaveAudio(samples: samples)

        if let fileURL = url {
            createRecordingEntry(fileURL: fileURL, duration: duration)
        }

        audioBuffer.removeAll()
        recordingStartTime = nil
        currentDuration = 0

        return url
    }

    private func createRecordingEntry(fileURL: URL, duration: TimeInterval) {
        guard let context = modelContext else {
            print("[BleAudioRecorder] No ModelContext available, skipping SwiftData entry creation")
            return
        }

        let relativePath = fileURL.lastPathComponent
        let recording = Recording(
            title: "Recording \(formatDate(Date()))",
            duration: duration,
            audioFilePath: relativePath
        )

        context.insert(recording)

        do {
            try context.save()
            print("[BleAudioRecorder] SwiftData entry created for recording: \(recording.id)")
        } catch {
            print("[BleAudioRecorder] Failed to save SwiftData entry: \(error)")
        }
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
            print("[BleAudioRecorder] No audio data to encode")
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
        
        let pcmData = convertFloatToPCM16(samples)
        
        guard encodePCMToM4A(pcmData: pcmData, outputURL: outputURL) else {
            print("[BleAudioRecorder] Failed to encode audio to M4A")
            return nil
        }
        
        print("[BleAudioRecorder] Audio saved to: \(outputURL.path)")
        return outputURL
    }
    
    private func generateRecordingFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "Recording_\(timestamp).m4a"
    }
    
    private func convertFloatToPCM16(_ samples: [Float]) -> Data {
        var pcmData = Data()
        pcmData.reserveCapacity(samples.count * 2)
        
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * Float(Int16.max))
            let littleEndian = intSample.littleEndian
            withUnsafeBytes(of: littleEndian) { bytes in
                pcmData.append(contentsOf: bytes)
            }
        }
        
        return pcmData
    }
    
    private func encodePCMToM4A(pcmData: Data, outputURL: URL) -> Bool {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        guard let assetWriter = try? AVAssetWriter(url: outputURL, fileType: .m4a) else {
            print("[BleAudioRecorder] Failed to create AVAssetWriter")
            return false
        }
        
        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]
        
        guard let formatDesc = createPCMFormatDescription() else {
            print("[BleAudioRecorder] Failed to create format description")
            return false
        }
        
        let assetWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings, sourceFormatHint: formatDesc)
        assetWriterInput.expectsMediaDataInRealTime = false
        
        guard assetWriter.canAdd(assetWriterInput) else {
            print("[BleAudioRecorder] Cannot add input to asset writer")
            return false
        }
        
        assetWriter.add(assetWriterInput)
        
        guard assetWriter.startWriting() else {
            print("[BleAudioRecorder] Failed to start writing: \(assetWriter.error?.localizedDescription ?? "unknown error")")
            return false
        }
        
        assetWriter.startSession(atSourceTime: .zero)
        
        guard let sampleBuffer = createSampleBuffer(pcmData: pcmData, formatDesc: formatDesc) else {
            print("[BleAudioRecorder] Failed to create sample buffer")
            return false
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var writeSuccess = false
        
        assetWriterInput.requestMediaDataWhenReady(on: audioQueue) {
            while assetWriterInput.isReadyForMoreMediaData {
                if assetWriterInput.append(sampleBuffer) {
                    writeSuccess = true
                } else {
                    print("[BleAudioRecorder] Failed to append sample buffer")
                    writeSuccess = false
                }
                assetWriterInput.markAsFinished()
                semaphore.signal()
                break
            }
        }
        
        semaphore.wait()
        
        assetWriter.finishWriting {
            if let error = assetWriter.error {
                print("[BleAudioRecorder] Asset writer finished with error: \(error)")
            }
        }
        
        let timeout = DispatchTime.now() + .seconds(30)
        _ = semaphore.wait(timeout: timeout)
        
        return writeSuccess && assetWriter.status == .completed
    }
    
    private func createPCMFormatDescription() -> CMFormatDescription? {
        var audioStreamBasicDesc = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &audioStreamBasicDesc,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        
        guard status == noErr else {
            print("[BleAudioRecorder] Failed to create format description: \(status)")
            return nil
        }
        
        return formatDescription
    }
    
    private func createSampleBuffer(pcmData: Data, formatDesc: CMFormatDescription) -> CMSampleBuffer? {
        let numSamples = pcmData.count / 2
        
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: pcmData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: pcmData.count,
            flags: kCMBlockBufferAlwaysCopyDataFlag,
            blockBufferOut: &blockBuffer
        )
        
        guard blockStatus == noErr, let blockBuff = blockBuffer else {
            print("[BleAudioRecorder] Failed to create block buffer: \(blockStatus)")
            return nil
        }
        
        let copyStatus = pcmData.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuff,
                offsetIntoDestination: 0,
                dataLength: pcmData.count
            )
        }
        
        guard copyStatus == noErr else {
            print("[BleAudioRecorder] Failed to copy data to block buffer: \(copyStatus)")
            return nil
        }
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuff,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: numSamples,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        guard sampleStatus == noErr, let buffer = sampleBuffer else {
            print("[BleAudioRecorder] Failed to create sample buffer: \(sampleStatus)")
            return nil
        }
        
        return buffer
    }
}

extension Notification.Name {
    static let connectionStateDidChange = Notification.Name("com.scribe.connectionStateDidChange")
}