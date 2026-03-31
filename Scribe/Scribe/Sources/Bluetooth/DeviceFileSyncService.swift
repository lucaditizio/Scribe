import Foundation
import Combine
import CoreBluetooth

public struct DeviceFile: Identifiable {
    public let id: String
    public let name: String
    public let size: Int64
    public let createdAt: Date
    public let modifiedAt: Date
    public let filePathOnDevice: String
    
    public init(id: String, name: String, size: Int64, createdAt: Date, modifiedAt: Date, filePathOnDevice: String) {
        self.id = id
        self.name = name
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.filePathOnDevice = filePathOnDevice
    }
}

public enum FileTransferProgress {
    case uploading(String)
    case downloading(String, Double)
    case completed
    case error(String)
}

public enum FileTransferState: Equatable {
    case idle
    case enumerating
    case transferring(String)
    case completed
    case failed(String)
}

@Observable
public class DeviceFileSyncService: NSObject {
    
    private var connectionManager: DeviceConnectionManager?
    private var fileTransferProgress: [String: Double] = [:]
    
    public var state: FileTransferState = .idle
    public var transferProgress: Double = 0.0
    public var files: [DeviceFile] = []
    public var transferEvents: [FileTransferProgress] = []
    public var isTransferring: Bool {
        switch state {
        case .idle, .completed, .failed:
            return false
        default:
            return true
        }
    }
    
    private let fileTransferQueue = DispatchQueue(label: "com.scribe.fileTransfer", qos: .userInitiated)
    private let documentsDirectory: URL
    private let maxTransferEvents = 50
    
    public init(connectionManager: DeviceConnectionManager? = nil) {
        self.connectionManager = connectionManager
        self.documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        super.init()
    }

    
    public func enumerateFiles() throws {
        guard let connectionManager = connectionManager else {
            state = .failed("Not connected to device")
            return
        }
        
        guard connectionManager.connectionState == .connected else {
            state = .failed("Device not connected")
            return
        }
        
        state = .enumerating
        files.removeAll()
        
        fileTransferQueue.async { [weak self] in
            guard let self = self else { return }
            self.enumerateFilesFromDevice()
        }
    }
    
    public func syncRecordings() throws {
        // If the file list hasn't been populated yet, kick off enumeration and bail.
        // The caller should re-invoke syncRecordings() once enumerateFiles() completes.
        if files.isEmpty {
            try enumerateFiles()
            return
        }

        guard !files.isEmpty else {
            state = .failed("No files to sync")
            return
        }
        
        state = .transferring("Starting file transfer")
        transferProgress = 0.0
        
        fileTransferQueue.async { [weak self] in
            guard let self = self else { return }
            
            let totalFiles = self.files.count
            for (index, file) in self.files.enumerated() {
                self.state = .transferring("Transferring \(file.name) (\(index + 1)/\(totalFiles))")
                
                do {
                    try self.downloadFile(file)
                    self.transferProgress = Double(index + 1) / Double(totalFiles)
                } catch {
                    self.state = .failed("Failed to transfer \(file.name): \(error.localizedDescription)")
                    self.addTransferEvent(.error(error.localizedDescription))
                    return
                }
            }
            
            self.state = .completed
            self.transferProgress = 1.0
            self.addTransferEvent(.completed)
        }
    }
    
    public func downloadFile(_ file: DeviceFile) throws {
        guard let connectionManager = connectionManager else {
            throw FileTransferError.notConnected
        }
        
        guard connectionManager.connectionState == .connected else {
            throw FileTransferError.notConnected
        }
        
        let destinationURL = documentsDirectory.appendingPathComponent(file.name)
        let mockData = Data(repeating: 0, count: Int(file.size))
        try mockData.write(to: destinationURL)
        
        addTransferEvent(.downloading(file.name, 1.0))
    }
    
    public func cancelTransfer() {
        state = .idle
        fileTransferProgress.removeAll()
        transferEvents.removeAll()
    }
    
    public func clearTransferHistory() {
        transferEvents.removeAll()
    }
    
    public func getLocalFilePath(for deviceFile: DeviceFile) -> URL? {
        return documentsDirectory.appendingPathComponent(deviceFile.filePathOnDevice)
    }
    
    public func deleteLocalFile(_ file: DeviceFile) throws {
        let localURL = getLocalFilePath(for: file)
        guard let url = localURL else {
            throw FileTransferError.fileNotFound
        }
        
        try FileManager.default.removeItem(at: url)
    }
    
    private func enumerateFilesFromDevice() {
        let mockFiles: [(name: String, size: Int64, createdAt: Date, modifiedAt: Date, path: String)] = [
            ("recording_2024_03_30.m4a", 5_242_880, Date().addingTimeInterval(-3600), Date(), "recordings/recording_2024_03_30.m4a"),
            ("meeting_notes_2024_03_29.m4a", 3_145_728, Date().addingTimeInterval(-86400), Date(), "recordings/meeting_notes_2024_03_29.m4a"),
            ("interview_2024_03_28.m4a", 7_340_032, Date().addingTimeInterval(-172800), Date(), "recordings/interview_2024_03_28.m4a"),
        ]
        
        files = mockFiles.map { name, size, createdAt, modifiedAt, path in
            DeviceFile(
                id: UUID().uuidString,
                name: name,
                size: size,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                filePathOnDevice: path
            )
        }
        
        state = .completed
        addTransferEvent(.uploading("Enumerated \(files.count) files"))
    }
    
    private func addTransferEvent(_ event: FileTransferProgress) {
        transferEvents.append(event)
        if transferEvents.count > maxTransferEvents {
            transferEvents.removeFirst()
        }
    }
}

public enum FileTransferError: Error, LocalizedError {
    case notConnected
    case fileNotFound
    case downloadFailed
    case permissionDenied
    case insufficientStorage
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to device"
        case .fileNotFound:
            return "File not found on device"
        case .downloadFailed:
            return "Failed to download file"
        case .permissionDenied:
            return "Permission denied to access files"
        case .insufficientStorage:
            return "Insufficient storage on device"
        }
    }
}
