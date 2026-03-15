import Foundation
import AVFoundation

@Observable
class WaveformAnalyzer {
    // Array of normalized floats between 0.0 and 1.0
    var samples: [Float] = []
    var isAnalyzing = false
    
    // Config
    private let targetSampleCount = 50
    
    func analyze(audioFilePath: String) async {
        isAnalyzing = true
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentPath.appendingPathComponent(audioFilePath)
        
        let urlAsset = AVURLAsset(url: fileURL)
        
        // Use a background task to process the audio file live without blocking UI
        let computedSamples = await Task.detached(priority: .userInitiated) { () -> [Float] in
            guard let assetTrack = try? await urlAsset.loadTracks(withMediaType: .audio).first else { return [] }
            
            do {
                let reader = try AVAssetReader(asset: urlAsset)
                let outputSettings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                
                let trackOutput = AVAssetReaderTrackOutput(track: assetTrack, outputSettings: outputSettings)
                reader.add(trackOutput)
                reader.startReading()
                
                var rawSamples: [Float] = []
                
                while reader.status == .reading {
                    guard let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                          let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                        break
                    }
                    
                    let length = CMBlockBufferGetDataLength(blockBuffer)
                    var data = [Int16](repeating: 0, count: length / MemoryLayout<Int16>.stride)
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)
                    
                    // Widen to Int32 before abs() — abs(Int16.min) overflows Int16 and crashes
                    var bufferMax: Int32 = 0
                    for sample in data {
                        let absoluteSample = abs(Int32(sample))
                        if absoluteSample > bufferMax {
                            bufferMax = absoluteSample
                        }
                    }
                    rawSamples.append(Float(bufferMax))
                }
                
                // Downsample to target sample count
                return self.downsample(rawSamples: rawSamples, targetCount: self.targetSampleCount)

            } catch {
                print("Failed to read audio file for waveform: \(error)")
                return []
            }
        }.value
        
        await MainActor.run {
            self.samples = computedSamples
            self.isAnalyzing = false
        }
    }
    
    private func downsample(rawSamples: [Float], targetCount: Int) -> [Float] {
        guard !rawSamples.isEmpty else { return [] }
        if rawSamples.count <= targetCount {
            return normalize(samples: rawSamples)
        }
        
        let binSize = rawSamples.count / targetCount
        var downsampled: [Float] = []
        
        for i in 0..<targetCount {
            let start = i * binSize
            let end = min(start + binSize, rawSamples.count)
            let slice = rawSamples[start..<end]
            let avg = slice.reduce(0, +) / Float(slice.count)
            downsampled.append(avg)
        }
        
        return normalize(samples: downsampled)
    }
    
    private func normalize(samples: [Float]) -> [Float] {
        guard let max = samples.max(), max > 0 else { return samples }
        // We ensure a minimum height of 0.05 so silent parts still draw a dot/small line
        return samples.map { Swift.max(0.05, $0 / max) }
    }
}
