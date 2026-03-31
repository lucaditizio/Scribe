import Foundation
import CoreBluetooth

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

    public var state: AudioStreamState = .idle
    public var isStreaming: Bool { state == .streaming }
    public var lastFrameTimestamp: Date?

    private let maxBufferFrames = 200

    public init(connectionManager: DeviceConnectionManager? = nil) {
        self.connectionManager = connectionManager
        self.audioBuffer = CircularAudioBuffer(maxFrames: maxBufferFrames)
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
            let frame = AudioFrame(data: data)
            self.audioBuffer.enqueue(frame)
            self.lastFrameTimestamp = frame.timestamp
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
//
// NOTE: This decoder requires libopus to be linked. The AI DVR Link app bundles
// `opus.framework` and `opus_flutter_ios.framework`. When those frameworks are
// added to the Scribe target, uncomment the implementation below.
// Until then this stub returns an empty buffer so the pipeline compiles cleanly.

public final class OpusAudioDecoder {
    private let sampleRate: Int
    private let channels: Int

    /// Number of PCM frames per 20 ms Opus packet at the configured sample rate.
    public var frameSizePerPacket: Int { sampleRate / 50 }

    public init(sampleRate: Int = 16000, channels: Int = 1) {
        self.sampleRate = sampleRate
        self.channels = channels
        // TODO: initialise libopus decoder handle once opus.framework is linked
        print("[OpusAudioDecoder] Stub initialised — link opus.framework to enable decoding")
    }

    /// Decode one Opus packet into Float32 PCM samples.
    /// - Returns: Array of Float32 samples normalised to [-1.0, 1.0].
    public func decode(_ data: Data) throws -> [Float] {
        guard !data.isEmpty else { throw AudioStreamError.opusDecodingError }
        // TODO: replace stub with real libopus call once framework is linked:
        //   let n = opus_decode(handle, bytes, Int32(data.count), &pcm, Int32(frameSizePerPacket), 0)
        //   return pcm.map { Float($0) / 32768.0 }
        return [Float](repeating: 0, count: frameSizePerPacket * channels)
    }
}
