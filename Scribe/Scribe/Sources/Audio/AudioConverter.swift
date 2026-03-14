import Foundation
import AVFoundation

/// Handles downsampling and formatting audio specifically for CoreML Model ingestion
class AudioConverter {
    
    /// Converts an M4A audio file at `url` into a raw 16kHz Float32 PCM format required by standard ASR models
    static func convertToFloat32(audioURL: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: audioURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "AudioConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio track found in file."])
        }
        
        let reader = try AVAssetReader(asset: asset)
        
        // 16kHz is the standard for NeMo and OpenAI Whisper ASR models
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(trackOutput)
        reader.startReading()
        
        var floatArray: [Float] = []
        
        while reader.status == .reading {
            guard let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                break
            }
            
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.stride)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)
            
            floatArray.append(contentsOf: data)
        }
        
        if reader.status == .failed {
            throw reader.error ?? NSError(domain: "AudioConverter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to read audio data."])
        }
        
        return floatArray
    }
}
