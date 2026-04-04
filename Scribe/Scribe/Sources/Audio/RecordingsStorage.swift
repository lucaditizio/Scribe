import Foundation

enum RecordingsStorage {
    /// Returns the URL to the Recordings directory within Documents
    static func recordingsDirectory() -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent("Recordings", isDirectory: true)
    }

    /// Ensures the Recordings directory exists, creating it if necessary
    /// - Throws: An error if directory creation fails
    static func ensureRecordingsDirectoryExists() throws {
        let recordingsURL = recordingsDirectory()
        
        if FileManager.default.fileExists(atPath: recordingsURL.path) {
            return
        }
        
        try FileManager.default.createDirectory(
            at: recordingsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
