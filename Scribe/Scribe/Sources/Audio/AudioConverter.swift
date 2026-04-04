import Foundation
import AVFoundation

class AudioConverter {
    static func convertToFloat32(audioURL: URL) async throws -> [Float] {
        let data = try Data(contentsOf: audioURL)
        
        guard data.count % MemoryLayout<Float>.stride == 0 else {
            throw NSError(domain: "AudioConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid PCM data size"])
        }
        
        let sampleCount = data.count / MemoryLayout<Float>.stride
        var floatArray = [Float](repeating: 0, count: sampleCount)
        
        _ = floatArray.withUnsafeMutableBytes { rawBuffer in
            data.copyBytes(to: rawBuffer)
        }
        
        return floatArray
    }
}
