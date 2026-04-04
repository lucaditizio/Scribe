import Foundation
import CoreBluetooth
import AVFoundation
import Opus

// MARK: - Supporting types

public enum AudioStreamState: Equatable {
    case idle
    case streaming
    case paused
    case error(String)
}

public struct AudioFrame: Sendable {
    public let data: Data
    public let timestamp: Date
    public let sampleRate: Int

    public init(data: Data, timestamp: Date = Date(), sampleRate: Int = 16000) {
        self.data = data
        self.timestamp = timestamp
        self.sampleRate = sampleRate
    }
}

public enum AudioStreamError: Error, LocalizedError {
    case notConnected
    case characteristicNotFound
    case decodeFailed
    case bufferOverflow
    case opusDecodingError

    public var errorDescription: String? {
        switch self {
        case .notConnected:          return "Not connected to audio device"
        case .characteristicNotFound: return "Audio characteristic not found"
        case .decodeFailed:          return "Failed to decode audio data"
        case .bufferOverflow:        return "Audio buffer overflow"
        case .opusDecodingError:     return "Opus decoding error"
        }
    }
}

// MARK: - AudioStreamReceiver
//
// Listens for incoming BLE audio notifications from the DVR microphone.
// Raw Opus-encoded packets arrive via NotificationCenter from DeviceConnectionManager
// and are decoded to Float32 PCM frames ready for the VAD → noise-suppression pipeline.

@Observable
public class AudioStreamReceiver {

    private var connectionManager: DeviceConnectionManager?
    private let audioQueue = DispatchQueue(label: "com.scribe.audioStream", qos: .userInitiated)
    private let audioBuffer: CircularAudioBuffer
    private var notificationObserver: NSObjectProtocol?
    private var decoder: OpusAudioDecoder?

    public var state: AudioStreamState = .idle
    public var isStreaming: Bool { state == .streaming }
    public var lastFrameTimestamp: Date?
    public var lastDecodedSamples: [Float] = []

    private let maxBufferFrames = 200

    public init(connectionManager: DeviceConnectionManager? = nil) {
        self.connectionManager = connectionManager
        self.audioBuffer = CircularAudioBuffer(maxFrames: maxBufferFrames)
        do {
            self.decoder = try OpusAudioDecoder(sampleRate: 16000, channels: 1)
        } catch {
            print("[AudioStreamReceiver] Failed to initialize Opus decoder: \(error)")
            self.state = .error("Failed to initialize Opus decoder")
        }
    }

    deinit {
        stopListeningForNotifications()
    }

    // MARK: - Public API

    public func startStreaming() throws {
        guard let mgr = connectionManager else {
            state = .error(AudioStreamError.notConnected.localizedDescription)
            return
        }
        guard mgr.connectionState == .connected else {
            state = .error(AudioStreamError.notConnected.localizedDescription)
            return
        }
        guard mgr.audioNotificationCharacteristic != nil else {
            state = .error(AudioStreamError.characteristicNotFound.localizedDescription)
            return
        }
        mgr.subscribeToAudioNotifications()
        startListeningForNotifications()
        state = .streaming
        print("[AudioStreamReceiver] Streaming started")
    }

    public func stopStreaming() {
        connectionManager?.unsubscribeFromAudioNotifications()
        stopListeningForNotifications()
        state = .paused
        print("[AudioStreamReceiver] Streaming stopped")
    }

    public func resumeStreaming() throws {
        if state == .paused { try startStreaming() }
    }

    /// Dequeue up to `count` buffered frames for downstream processing (VAD, noise suppression).
    public func dequeueFrames(_ count: Int = 10) -> [AudioFrame] {
        audioBuffer.dequeue(count)
    }

    /// Return all buffered frames and clear the buffer.
    public func flush() -> [AudioFrame] {
        audioBuffer.flush()
    }

    public func clearBuffer() {
        audioBuffer.clear()
    }

    // MARK: - Private

    private func startListeningForNotifications() {
        stopListeningForNotifications()
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .audioCharacteristicDidUpdate,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let data = notification.userInfo?["data"] as? Data else { return }
            self?.handleIncomingAudioData(data)
        }
    }

    private func stopListeningForNotifications() {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
    }

    private func handleIncomingAudioData(_ data: Data) {
        audioQueue.async { [weak self] in
            guard let self, self.state == .streaming else { return }
            guard let decoder = self.decoder else {
                print("[AudioStreamReceiver] Decoder not available, skipping packet")
                return
            }

            do {
                let pcmSamples = try decoder.decode(data)
                self.lastDecodedSamples = pcmSamples

                let pcmData = pcmSamples.withUnsafeBufferPointer { buffer in
                    Data(buffer: buffer)
                }

                let frame = AudioFrame(data: pcmData, timestamp: Date(), sampleRate: 16000)
                self.audioBuffer.enqueue(frame)
                self.lastFrameTimestamp = frame.timestamp

                print("[AudioStreamReceiver] Processed packet: \(data.count) bytes -> \(pcmSamples.count) PCM samples")
            } catch {
                print("[AudioStreamReceiver] Failed to decode audio packet (\(data.count) bytes): \(error)")
            }
        }
    }
}

// MARK: - CircularAudioBuffer
//
// Thread-safe ring buffer for AudioFrames. Uses a serial DispatchQueue as a lock.

public final class CircularAudioBuffer {
    private var buffer: [AudioFrame] = []
    private let maxFrames: Int
    private let queue = DispatchQueue(label: "com.scribe.audioBuffer")

    public init(maxFrames: Int) {
        self.maxFrames = maxFrames
    }

    public func enqueue(_ frame: AudioFrame) {
        queue.sync {
            buffer.append(frame)
            if buffer.count > maxFrames {
                buffer.removeFirst()
            }
        }
    }

    /// Removes and returns the first `count` frames.
    public func dequeue(_ count: Int) -> [AudioFrame] {
        queue.sync {
            let n = min(count, buffer.count)
            let frames = Array(buffer.prefix(n))
            buffer.removeFirst(n)
            return frames
        }
    }

    /// Returns all frames and clears the buffer.
    public func flush() -> [AudioFrame] {
        queue.sync {
            let all = buffer
            buffer.removeAll()
            return all
        }
    }

    public func clear() {
        queue.sync { buffer.removeAll() }
    }

    public var count: Int {
        queue.sync { buffer.count }
    }
}

// MARK: - OpusAudioDecoder
//
// Decodes Opus-encoded packets received from the DVR microphone over BLE into
// raw Int16 PCM samples, then converts to Float32 in [-1, 1] for CoreML models.
// Uses SwiftOpus package (https://github.com/alta/swift-opus.git).

public final class OpusAudioDecoder {
    private let sampleRate: Int
    private let channels: Int
    private let decoder: Opus.Decoder
    private let audioFormat: AVAudioFormat

    public var frameSizePerPacket: Int { sampleRate / 50 }
    public var expectedSamplesPerPacket: Int { frameSizePerPacket * channels }

    public init(sampleRate: Int = 16000, channels: Int = 1) throws {
        self.sampleRate = sampleRate
        self.channels = channels

        guard let format = AVAudioFormat(
            opusPCMFormat: .float32,
            sampleRate: sampleRate == 16000 ? .opus16khz : .opus48khz,
            channels: AVAudioChannelCount(channels)
        ) else {
            throw AudioStreamError.opusDecodingError
        }
        self.audioFormat = format
        self.decoder = try Opus.Decoder(format: format)
        print("[OpusAudioDecoder] Initialized with sampleRate=\(sampleRate), channels=\(channels)")
    }

    private func stripOpusHeader(_ data: Data) -> Data {
        guard data.count >= 4 else { return data }

        let headerPattern1: [UInt8] = [0xFF, 0xF3, 0x48, 0xC4]
        let headerPattern2: [UInt8] = [0xFF, 0xF3]
        let bytes = [UInt8](data)

        if data.count >= 4,
           bytes[0] == headerPattern1[0],
           bytes[1] == headerPattern1[1],
           bytes[2] == headerPattern1[2],
           bytes[3] == headerPattern1[3] {
            return data.subdata(in: 4..<data.count)
        }

        if bytes[0] == headerPattern2[0],
           bytes[1] == headerPattern2[1] {
            let headerLength = min(4, data.count)
            return data.subdata(in: headerLength..<data.count)
        }

        return data
    }

    public func decode(_ data: Data) throws -> [Float] {
        guard !data.isEmpty else {
            print("[OpusAudioDecoder] Error: Empty data received")
            throw AudioStreamError.opusDecodingError
        }

        let opusData = stripOpusHeader(data)

        guard opusData.count > 0 else {
            print("[OpusAudioDecoder] Error: No data after header stripping")
            throw AudioStreamError.opusDecodingError
        }

        do {
            let pcmBuffer = try decoder.decode(opusData)
            let frameLength = Int(pcmBuffer.frameLength)
            let channelCount = Int(pcmBuffer.format.channelCount)
            let totalSamples = frameLength * channelCount

            guard let audioBuffer = pcmBuffer.audioBufferList.pointee.mBuffers.mData else {
                print("[OpusAudioDecoder] Error: No audio buffer data")
                throw AudioStreamError.opusDecodingError
            }

            let floatPointer = audioBuffer.bindMemory(to: Float.self, capacity: totalSamples)
            var floatArray = [Float](repeating: 0, count: totalSamples)
            for i in 0..<totalSamples {
                floatArray[i] = floatPointer[i]
            }

            print("[OpusAudioDecoder] Decoded \(opusData.count) bytes -> \(floatArray.count) samples")

            return floatArray
        } catch {
            print("[OpusAudioDecoder] Decoding error: \(error)")
            throw AudioStreamError.opusDecodingError
        }
    }
}
