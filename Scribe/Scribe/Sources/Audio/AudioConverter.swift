import Foundation
import AVFoundation

class AudioConverter {
    static func convertToFloat32(audioURL: URL) async throws -> [Float] {
        let data = try Data(contentsOf: audioURL)
        
        guard data.count > 8 else {
            throw NSError(domain: "AudioConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "File too small"])
        }
        
        let isCAF = data.prefix(4).elementsEqual("caff".utf8)
        
        if isCAF {
            return try parseCAFFile(data)
        } else {
            throw NSError(domain: "AudioConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format. Expected CAF."])
        }
    }
    
    private static func parseCAFFile(_ data: Data) throws -> [Float] {
        var offset = 4
        
        guard data.count > offset + 4 else {
            throw NSError(domain: "AudioConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid CAF header"])
        }
        
        offset += 4
        
        var audioData: Data?
        
        while offset < data.count - 12 {
            guard let chunkType = String(data: data.subdata(in: offset..<offset+4), encoding: .ascii) else {
                break
            }
            offset += 4
            
            let chunkSize = data.subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            offset += 8
            
            if chunkType == "data" {
                offset += 4
                
                let audioSize = Int(chunkSize) - 4
                guard offset + audioSize <= data.count else {
                    throw NSError(domain: "AudioConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data chunk size"])
                }
                
                audioData = data.subdata(in: offset..<offset+audioSize)
                break
            } else {
                offset += Int(chunkSize)
            }
        }
        
        guard let audioBytes = audioData else {
            throw NSError(domain: "AudioConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio data found in CAF"])
        }
        
        guard audioBytes.count % MemoryLayout<Float>.stride == 0 else {
            throw NSError(domain: "AudioConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio data size"])
        }
        
        let sampleCount = audioBytes.count / MemoryLayout<Float>.stride
        var floatArray = [Float](repeating: 0, count: sampleCount)
        
        _ = floatArray.withUnsafeMutableBytes { rawBuffer in
            audioBytes.copyBytes(to: rawBuffer)
        }
        
        return floatArray
    }
}
