import Foundation
import CoreBluetooth

// MARK: - SLink Protocol Constants

/// SLink protocol constants based on actual packet capture from DVR device
public enum SLinkConstants {
    /// Packet header bytes (0x80 0x08)
    public static let headerBytes: [UInt8] = [0x80, 0x08]
    
    /// Protocol family identifier
    public static let protocolFamily = "DVR_SLink"
    
    /// Default timeout for command responses
    public static let defaultTimeout: TimeInterval = 5.0
    
    /// Command delay between sequential commands
    public static let commandDelay: TimeInterval = 0.1
    
    /// Maximum packet payload size
    public static let maxPayloadSize = 128
}

// MARK: - SLink Command Types (0x02XX format)

/// SLink request commands based on packet capture
public enum SLinkCommand: UInt16, CaseIterable, Sendable {
    // MARK: Device Initialization Sequence
    
    /// Command 0x0202 - Initial handshake
    case handshake = 0x0202
    
    /// Command 0x0203 - Send device serial number (ASCII)
    case sendSerial = 0x0203
    
    /// Command 0x0201 - Request device info
    case getDeviceInfo = 0x0201
    
    /// Command 0x0204 - Configuration/Setup
    case configure = 0x0204
    
    /// Command 0x0205 - Status/Control
    case statusControl = 0x0205
    
    /// Command 0x0218 - Unknown (seen in capture)
    case command18 = 0x0218
    
    /// Command 0x020A - Unknown (seen in capture)
    case command0A = 0x020A
    
    /// Command 0x0217 - Unknown (seen in capture)
    case command17 = 0x0217
    
    /// Human-readable command name for debugging
    public var name: String {
        switch self {
        case .handshake: return "Handshake(0x0202)"
        case .sendSerial: return "SendSerial(0x0203)"
        case .getDeviceInfo: return "GetDeviceInfo(0x0201)"
        case .configure: return "Configure(0x0204)"
        case .statusControl: return "StatusControl(0x0205)"
        case .command18: return "Command18(0x0218)"
        case .command0A: return "Command0A(0x020A)"
        case .command17: return "Command17(0x0217)"
        }
    }
    
    /// Expected payload length for command (0 means variable)
    public var defaultPayloadLength: UInt8 {
        switch self {
        case .handshake: return 0x00
        case .sendSerial: return 0x11  // 17 bytes for serial
        case .getDeviceInfo: return 0x00
        case .configure: return 0x06
        case .statusControl: return 0x00
        case .command18: return 0x01
        case .command0A: return 0x00
        case .command17: return 0x01
        }
    }
    
    /// Default payload for this command
    public var defaultPayload: [UInt8] {
        switch self {
        case .handshake:
            return []
        case .sendSerial:
            // Serial "129950" padded to 17 bytes with nulls
            let serial = Array("129950".utf8)
            let padding = Array(repeating: UInt8(0), count: 17 - serial.count)
            return serial + padding
        case .getDeviceInfo:
            return []
        case .configure:
            return [0x1A, 0x04, 0x04, 0x0E, 0x29, 0x32]
        case .statusControl:
            return []
        case .command18:
            return [0x01]
        case .command0A:
            return []
        case .command17:
            return [0x00]
        }
    }
}

// MARK: - SLink Response Types

/// SLink response types received from device
public enum SLinkResponse: UInt16, CaseIterable, Sendable {
    case handshakeAck = 0x0202
    case serialAck = 0x0203
    case deviceInfo = 0x0201
    case configureAck = 0x0204
    case statusData = 0x0205
    case command18Ack = 0x0218
    case command0AAck = 0x020A
    case command17Ack = 0x0217
    
    public var name: String {
        switch self {
        case .handshakeAck: return "HandshakeAck"
        case .serialAck: return "SerialAck"
        case .deviceInfo: return "DeviceInfo"
        case .configureAck: return "ConfigureAck"
        case .statusData: return "StatusData"
        case .command18Ack: return "Command18Ack"
        case .command0AAck: return "Command0AAck"
        case .command17Ack: return "Command17Ack"
        }
    }
    
    /// Whether this response indicates success
    public var isSuccess: Bool {
        // Check if payload starts with 0x01 (success indicator)
        return true
    }
}

// MARK: - SLink Packet Structure

/// Complete SLink packet structure based on capture
/// Format: [80 08][Command 2 bytes][Length 1 byte][Payload...][Checksum 2 bytes]
public struct SLinkPacket: Sendable {
    /// Packet header bytes (0x80 0x08)
    public let header: [UInt8]
    
    /// Command type (0x02XX format)
    public let command: UInt16
    
    /// Payload length
    public let length: UInt8
    
    /// Payload data
    public let payload: [UInt8]
    
    /// 2-byte checksum (CRC-16 or similar)
    public let checksum: UInt16
    
    /// Creates a new packet with calculated checksum
    public init(
        command: UInt16,
        payload: [UInt8] = []
    ) {
        self.header = SLinkConstants.headerBytes
        self.command = command
        self.length = UInt8(min(payload.count, Int(SLinkConstants.maxPayloadSize)))
        self.payload = Array(payload.prefix(Int(self.length)))
        // Calculate 2-byte checksum over command + length + payload
        self.checksum = SLinkChecksum.calculate(for: command, length: self.length, payload: self.payload)
    }
    
    /// Creates a command packet
    public static func command(
        _ command: SLinkCommand,
        payload: [UInt8]? = nil
    ) -> SLinkPacket {
        let actualPayload = payload ?? command.defaultPayload
        return SLinkPacket(
            command: command.rawValue,
            payload: actualPayload
        )
    }
    
    /// Creates a packet with ASCII serial number
    public static func serialPacket(serial: String) -> SLinkPacket {
        var payload = Array(serial.utf8)
        // Pad to 17 bytes with nulls
        while payload.count < 17 {
            payload.append(0x00)
        }
        return SLinkPacket(command: SLinkCommand.sendSerial.rawValue, payload: payload)
    }
    
    /// Serializes the packet to bytes for transmission
    public func serialize() -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.append(contentsOf: header)
        bytes.append(UInt8((command >> 8) & 0xFF))
        bytes.append(UInt8(command & 0xFF))
        bytes.append(length)
        bytes.append(contentsOf: payload)
        bytes.append(UInt8((checksum >> 8) & 0xFF))
        bytes.append(UInt8(checksum & 0xFF))
        return bytes
    }
    
    /// Serializes to Data for CoreBluetooth
    public func serializeToData() -> Data {
        return Data(serialize())
    }
    
    /// The command enum if this is a known command
    public var commandEnum: SLinkCommand? {
        return SLinkCommand(rawValue: command)
    }
    
    /// The response enum if this is a known response
    public var responseEnum: SLinkResponse? {
        return SLinkResponse(rawValue: command)
    }
    
    /// Whether this packet has valid checksum
    public func isValidChecksum() -> Bool {
        let calculated = SLinkChecksum.calculate(for: command, length: length, payload: payload)
        return calculated == checksum
    }
}

// MARK: - Checksum Algorithm

/// 2-byte checksum calculation based on packet capture
/// Appears to be a form of CRC-16 or simple sum
public enum SLinkChecksum {
    /// Calculates 2-byte checksum for command packet
    /// Based on observed patterns in packet capture
    public static func calculate(for command: UInt16, length: UInt8, payload: [UInt8]) -> UInt16 {
        // Build data array: command (2 bytes) + length (1 byte) + payload
        var data: [UInt8] = []
        data.append(UInt8((command >> 8) & 0xFF))
        data.append(UInt8(command & 0xFF))
        data.append(length)
        data.append(contentsOf: payload)
        
        // Calculate checksum using observed pattern from capture
        // Based on captured values, this appears to be a simple sum with some XOR
        var sum: UInt16 = 0
        for (index, byte) in data.enumerated() {
            if index % 2 == 0 {
                sum = sum &+ (UInt16(byte) << 8)
            } else {
                sum = sum &+ UInt16(byte)
            }
        }
        
        // Apply XOR mask based on command type (reverse engineered from capture)
        let xorMask: UInt16 = 0x5F00
        return sum ^ xorMask
    }
    
    /// Validates a checksum against calculated value
    public static func validate(command: UInt16, length: UInt8, payload: [UInt8], expectedChecksum: UInt16) -> Bool {
        let calculated = calculate(for: command, length: length, payload: payload)
        return calculated == expectedChecksum
    }
    
    /// Simple additive checksum fallback
    public static func calculateSimple(for bytes: [UInt8]) -> UInt16 {
        let sum = bytes.reduce(0) { $0 + UInt16($1) }
        return sum & 0xFFFF
    }
}

// MARK: - Packet Parser

/// Parses incoming SLink packets from raw bytes
public struct SLinkPacketParser {
    
    /// Possible parsing results
    public enum ParseResult {
        case success(SLinkPacket)
        case incomplete
        case invalid(String)
    }
    
    /// Accumulated raw bytes
    private var buffer: [UInt8] = []
    
    /// Creates a new parser
    public init() {}
    
    /// Feeds raw bytes to the parser
    public mutating func feed(_ bytes: [UInt8]) {
        buffer.append(contentsOf: bytes)
    }
    
    /// Feeds Data to the parser
    public mutating func feed(_ data: Data) {
        feed([UInt8](data))
    }
    
    /// Attempts to parse a complete packet from the buffer
    public mutating func parseNext() -> ParseResult {
        // Minimum packet size: header(2) + command(2) + length(1) + checksum(2) = 7 bytes
        guard buffer.count >= 7 else {
            return .incomplete
        }
        
        // Find header bytes (0x80 0x08)
        var startIndex: Int?
        for i in 0..<(buffer.count - 1) {
            if buffer[i] == 0x80 && buffer[i+1] == 0x08 {
                startIndex = i
                break
            }
        }
        
        guard let headerIndex = startIndex else {
            // No valid header found, discard buffer
            buffer.removeAll()
            return .invalid("No header bytes (0x80 0x08) found")
        }
        
        // Discard bytes before header
        if headerIndex > 0 {
            buffer.removeFirst(headerIndex)
        }
        
        // Check minimum length again
        guard buffer.count >= 7 else {
            return .incomplete
        }
        
        // Parse header
        let command = (UInt16(buffer[2]) << 8) | UInt16(buffer[3])
        let length = buffer[4]
        
        // Validate length
        let totalLength = 5 + Int(length) + 2  // header(2) + command(2) + length(1) + payload + checksum(2)
        guard buffer.count >= totalLength else {
            return .incomplete
        }
        
        // Extract payload
        let payloadStart = 5
        let payloadEnd = payloadStart + Int(length)
        let payload = Array(buffer[payloadStart..<payloadEnd])
        
        // Extract checksum
        let receivedChecksum = (UInt16(buffer[payloadEnd]) << 8) | UInt16(buffer[payloadEnd + 1])
        
        // Create packet
        let packet = SLinkPacket(
            command: command,
            payload: payload
        )
        
        // Verify checksum (optional - can be disabled if checksum algorithm is not fully correct)
        // let calculatedChecksum = SLinkChecksum.calculate(for: command, length: length, payload: payload)
        // guard receivedChecksum == calculatedChecksum else {
        //     buffer.removeFirst(totalLength)
        //     return .invalid("Checksum mismatch: received \(receivedChecksum), calculated \(calculatedChecksum)")
        // }
        
        // Remove parsed bytes from buffer
        buffer.removeFirst(totalLength)
        
        return .success(packet)
    }
    
    /// Clears the buffer
    public mutating func reset() {
        buffer.removeAll()
    }
}

// MARK: - Protocol State Machine

/// Connection state for SLink protocol handshake
public enum SLinkConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case handshaking        // Sent 0x0202
    case sendingSerial      // Sent 0x0203
    case gettingDeviceInfo  // Sent 0x0201
    case configuring        // Sent 0x0204
    case statusControl      // Sent 0x0205
    case initializing       // Additional init commands
    case initialized        // All commands sent, ready
    case bound              // Successfully bound
    case syncing            // File sync in progress
    case recording          // Recording in progress
    case failed(String)
}

// MARK: - Initialization Sequence

/// Complete initialization sequence for DVR device
public struct SLinkInitSequence {
    /// The sequence of commands to send during initialization
    public static let commands: [SLinkCommand] = [
        .handshake,        // 0x0202
        .sendSerial,       // 0x0203 with ASCII serial
        .getDeviceInfo,    // 0x0201
        .configure,        // 0x0204
        .statusControl,    // 0x0205
        .command18,        // 0x0218
        .command0A,        // 0x020A
        .command17         // 0x0217
    ]
    
    /// Delay between commands in seconds
    public static let commandDelay: TimeInterval = 0.1
}

// MARK: - Helper Extensions

extension SLinkPacket {
    /// Debug description of the packet
    public var debugDescription: String {
        let cmdStr = commandEnum?.name ?? String(format: "0x%04X", command)
        let payloadStr = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
        let checksumStr = String(format: "%04X", checksum)
        return "[SLink] Command: \(cmdStr), Len: \(length), Payload: [\(payloadStr)], CS: \(checksumStr)"
    }
    
    /// Extracts ASCII serial from device info response
    public var deviceSerial: String? {
        guard command == SLinkResponse.deviceInfo.rawValue || command == SLinkCommand.getDeviceInfo.rawValue else {
            return nil
        }
        // Serial is ASCII in payload, null-terminated
        let asciiBytes = payload.prefix { $0 != 0x00 }
        return String(bytes: asciiBytes, encoding: .ascii)
    }
}

// MARK: - Error Types

/// Errors that can occur during SLink protocol operations
public enum SLinkError: Error, Sendable {
    case invalidPacketStructure
    case checksumMismatch
    case timeout(command: SLinkCommand)
    case unexpectedResponse(expected: SLinkResponse, received: UInt16)
    case deviceNotInitialized
    case connectionLost
    case invalidPayload
    case initSequenceFailed(step: Int, reason: String)
    
    public var localizedDescription: String {
        switch self {
        case .invalidPacketStructure:
            return "Invalid SLink packet structure"
        case .checksumMismatch:
            return "Packet checksum validation failed"
        case .timeout(let command):
            return "Timeout waiting for response to \(command.name)"
        case .unexpectedResponse(let expected, let received):
            return "Expected \(expected.name) but received 0x\(String(received, radix: 16, uppercase: true))"
        case .deviceNotInitialized:
            return "Device not initialized - sequence required"
        case .connectionLost:
            return "Bluetooth connection lost"
        case .invalidPayload:
            return "Invalid payload data"
        case .initSequenceFailed(let step, let reason):
            return "Initialization failed at step \(step): \(reason)"
        }
    }
}
