import Foundation
import AVFoundation

class AudioConverter {
    static func convertToFloat32(audioURL: URL) async throws -> [Float] {
        let data = try Data(contentsOf: audioURL)
        
        let isWAV = data.count > 12 &&
                    data.prefix(4).elementsEqual("RIFF".utf8) &&
                    data.subdata(in: 8..<12).elementsEqual("WAVE".utf8)
        
        let audioData: Data
        if isWAV {
            guard let dataChunkOffset = findDataChunk(in: data) else {
                throw NSError(domain: "AudioConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "WAV data chunk not found"])
            }
            audioData = data.subdata(in: dataChunkOffset + 8..<data.count)
        } else {
            audioData = data
        }
        
        guard audioData.count % MemoryLayout<Float>.stride == 0 else {
            throw NSError(domain: "AudioConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid PCM data size"])
        }
        
        let sampleCount = audioData.count / MemoryLayout<Float>.stride
        var floatArray = [Float](repeating: 0, count: sampleCount)
        
        _ = floatArray.withUnsafeMutableBytes { rawBuffer in
            audioData.copyBytes(to: rawBuffer)
        }
        
        return floatArray
    }
    
    private static func findDataChunk(in data: Data) -> Int? {
        let fmtSize = Int(data.subdata(in: 16..<20).withUnsafeBytes { $0.load(as: UInt32.self) })
        let searchStart = 20 + fmtSize
        
        for i in searchStart..<data.count - 4 {
            if data.subdata(in: i..<i+4).elementsEqual("data".utf8) {
                return i
            }
        }
        return nil
    }
}
