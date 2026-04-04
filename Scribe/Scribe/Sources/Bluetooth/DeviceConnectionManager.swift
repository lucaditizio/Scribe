import Foundation
import Combine
import CoreBluetooth

// MARK: - Known AI DVR Link GATT UUIDs

enum DVRLinkUUID {
    static let primaryService            = CBUUID(string: "E49A3001-F69A-11E8-8EB2-F2801F1B9FD1")
    static let commandWriteChar          = CBUUID(string: "F0F1")
    static let fileTransferCharacteristic = CBUUID(string: "F0F2")
    static let fileTransferChar2          = CBUUID(string: "F0F3")
    static let fileTransferChar3          = CBUUID(string: "F0F4")
    static let audioStreamCharacteristic = CBUUID(string: "E49A3003-F69A-11E8-8EB2-F2801F1B9FD1")
    static let batteryService            = CBUUID(string: "180F")
    static let batteryCharacteristic     = CBUUID(string: "2A19")
}

public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case binding        // During SLink binding sequence
    case initializing   // During SLink init sequence
    case initialized    // Successfully initialized
    case bound          // Successfully bound
    case failed(String)
    case reconnecting(Int)
}

public struct ConnectionEvent: Equatable {
    let type: ConnectionEventType
    let message: String?
    
    public enum ConnectionEventType: Equatable {
        case connected
        case disconnected
        case connectionFailed
        case reconnected
        case servicesDiscovered
        case characteristicDiscovered
        case slinkCommandSent(String)
        case slinkResponseReceived(String)
    }
}

// MARK: - DeviceConnectionManager

@Observable
public class DeviceConnectionManager: NSObject, ScannerConnectionDelegate {

    private var peripheral: CBPeripheral?
    private var centralManager: CBCentralManager!
    private let bleQueue = DispatchQueue(label: "com.scribe.ble.connection", qos: .userInitiated)

    weak var scanner: BluetoothDeviceScanner?

    // Characteristics
    internal var audioStreamCharacteristic: CBCharacteristic?
    internal var fileTransferCharacteristic: CBCharacteristic?  // F0F2 - notifications
    internal var fileTransferChar2: CBCharacteristic?           // F0F3
    internal var fileTransferChar3: CBCharacteristic?           // F0F4
    internal var commandWriteCharacteristic: CBCharacteristic?  // F0F1
    internal var notificationCharacteristic: CBCharacteristic?  // F0F2 for notifications (handle 0x0024)

    public var connectionState: ConnectionState = .disconnected
    public var connectionEvents: [ConnectionEvent] = []
    public var connectedDevice: BluetoothDevice?
    public var availableServices: [CBService] = []
    public var supportedCharacteristics: [CBCharacteristic] = []

    // Connection management
    private let maxReconnectAttempts = 5
    private var reconnectAttempt = 0
    private let userDefaultsKey = "lastConnectedDeviceID"
    private var connectionTimeoutWork: DispatchWorkItem?
    private let connectionTimeoutSeconds: TimeInterval = 10

    private var pendingNotificationSubscriptions = 0
    private var hasSentInitialCommand = false
    private var hasReceivedFirstNotification = false
    private var keepAliveTimer: Timer?

    // SLink Protocol State
    private var slinkPacketParser = SLinkPacketParser()
    private var slinkState: SLinkConnectionState = .disconnected
    private var initSequenceStep = 0
    private var slinkCommandTimer: Timer?
    private var pendingCommand: SLinkCommand?
    
    // Device serial from capture
    private let deviceSerial = "129950"

    public init(scanner: BluetoothDeviceScanner) {
        self.scanner = scanner
        super.init()
        self.centralManager = scanner.centralManager
        scanner.connectionDelegate = self
        loadLastConnectedDevice()
    }

    public func connect(to device: BluetoothDevice) {
        guard let cbPeripheral = scanner?.cbPeripheral(for: device.id) else {
            connectionState = .failed("Peripheral not found - scan first")
            return
        }
        
        guard centralManager.state == .poweredOn else {
            connectionState = .failed("Bluetooth not ready")
            return
        }
        
        connectedDevice = device
        peripheral = cbPeripheral
        cbPeripheral.delegate = self
        connectionState = .connecting
        reconnectAttempt = 0
        hasSentInitialCommand = false
        hasReceivedFirstNotification = false
        pendingNotificationSubscriptions = 0
        initSequenceStep = 0

        print("[DeviceConnectionManager] Connecting to \(device.name)")
        
        centralManager.connect(cbPeripheral, options: nil)
        
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectionState == .connecting else { return }
            print("[DeviceConnectionManager] Connection timed out")
            self.centralManager.cancelPeripheralConnection(cbPeripheral)
            DispatchQueue.main.async {
                self.connectionState = .failed("Connection timed out")
            }
        }
        connectionTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + connectionTimeoutSeconds, execute: work)
    }

    public func disconnect() {
        guard let p = peripheral else { return }
        centralManager.cancelPeripheralConnection(p)
        resetState()
    }

    public func reconnect() {
        guard let device = connectedDevice else { return }
        reconnectAttempt += 1
        guard reconnectAttempt <= maxReconnectAttempts else {
            connectionState = .failed("Max reconnection attempts reached")
            return
        }
        connectionState = .reconnecting(reconnectAttempt)
        connect(to: device)
    }

    public func persistLastConnectedDevice() {
        if let device = connectedDevice {
            UserDefaults.standard.set(device.id, forKey: userDefaultsKey)
        }
    }

    public func discoverServices() {
        peripheral?.discoverServices(nil)
    }

    private func resetState() {
        stopKeepAlive()
        slinkCommandTimer?.invalidate()
        connectionState = .disconnected
        slinkState = .disconnected
        peripheral = nil
        connectedDevice = nil
        availableServices.removeAll()
        supportedCharacteristics.removeAll()
        audioStreamCharacteristic = nil
        fileTransferCharacteristic = nil
        fileTransferChar2 = nil
        fileTransferChar3 = nil
        commandWriteCharacteristic = nil
        notificationCharacteristic = nil
        hasSentInitialCommand = false
        hasReceivedFirstNotification = false
        pendingNotificationSubscriptions = 0
        initSequenceStep = 0
        pendingCommand = nil
        slinkPacketParser.reset()
    }

    private func addConnectionEvent(_ type: ConnectionEvent.ConnectionEventType, message: String? = nil) {
        let event = ConnectionEvent(type: type, message: message)
        connectionEvents.append(event)
        if connectionEvents.count > 50 {
            connectionEvents.removeFirst()
        }
    }

    private func loadLastConnectedDevice() {
        if let lastDeviceID = UserDefaults.standard.string(forKey: userDefaultsKey) {
            print("[DeviceConnectionManager] Last connected: \(lastDeviceID)")
        }
    }
}

// MARK: - ScannerConnectionDelegate implementation

extension DeviceConnectionManager {
    
    public func scannerDidConnect(peripheral: CBPeripheral) {
        connectionTimeoutWork?.cancel()
        connectionTimeoutWork = nil
        print("[DeviceConnectionManager] Connected")
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.connectionState = .connected
            self.addConnectionEvent(.connected, message: "Connected")
        }
        
        print("[DeviceConnectionManager] Discovering services...")
        peripheral.discoverServices(nil)
    }
    
    public func scannerDidFailToConnect(peripheral: CBPeripheral, error: Error?) {
        connectionTimeoutWork?.cancel()
        connectionTimeoutWork = nil
        let msg = error?.localizedDescription ?? "Unknown error"
        print("[DeviceConnectionManager] Failed to connect: \(msg)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.connectionState = .failed(msg)
            self.addConnectionEvent(.connectionFailed, message: msg)
        }
    }
    
    public func scannerDidDisconnect(peripheral: CBPeripheral, error: Error?) {
        connectionTimeoutWork?.cancel()
        connectionTimeoutWork = nil
        
        let errorDesc = error?.localizedDescription ?? "no error"
        print("[DeviceConnectionManager] Disconnected - error: \(errorDesc)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.connectionState = .disconnected
            self.addConnectionEvent(.disconnected, message: "Disconnected: \(errorDesc)")
            
            if let error = error, self.connectedDevice != nil {
                print("[DeviceConnectionManager] Will NOT auto-reconnect - waiting for user action")
            } else {
                self.resetState()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension DeviceConnectionManager: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        print("[DeviceConnectionManager] Found \(services.count) services")
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let error = error {
                print("[DeviceConnectionManager] Service error: \(error)")
                self.connectionState = .failed(error.localizedDescription)
                return
            }
            self.availableServices = services
            self.addConnectionEvent(.servicesDiscovered)
        }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("[DeviceConnectionManager] Char error for \(service.uuid): \(error)")
            return
        }
        
        let characteristics = service.characteristics ?? []
        print("[DeviceConnectionManager] \(service.uuid): \(characteristics.count) chars")
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            for characteristic in characteristics {
                self.supportedCharacteristics.append(characteristic)
                
                let uuid = characteristic.uuid
                if uuid == DVRLinkUUID.audioStreamCharacteristic {
                    self.audioStreamCharacteristic = characteristic
                    print("[DeviceConnectionManager] Audio stream char found (E49A3003)")
                } else if uuid == DVRLinkUUID.fileTransferCharacteristic {
                    self.fileTransferCharacteristic = characteristic
                    print("[DeviceConnectionManager] File transfer char found (F0F2)")
                } else if uuid == DVRLinkUUID.fileTransferChar2 {
                    self.fileTransferChar2 = characteristic
                    print("[DeviceConnectionManager] File transfer char 2 found (F0F3)")
                } else if uuid == DVRLinkUUID.fileTransferChar3 {
                    self.fileTransferChar3 = characteristic
                    print("[DeviceConnectionManager] File transfer char 3 found (F0F4)")
                } else if uuid == DVRLinkUUID.commandWriteChar {
                    self.commandWriteCharacteristic = characteristic
                    print("[DeviceConnectionManager] Command write char found (F0F1)")
                } else if uuid == DVRLinkUUID.batteryCharacteristic {
                    print("[DeviceConnectionManager] Battery char found")
                }
            }
            
            self.addConnectionEvent(.characteristicDiscovered)
            
            // Start notification subscription process
            self.subscribeToNotificationChars()
        }
    }
    
    private func subscribeToNotificationChars() {
        guard let p = peripheral, p.state == .connected else {
            print("[DeviceConnectionManager] Cannot subscribe - peripheral nil or disconnected")
            return
        }
        
        pendingNotificationSubscriptions = 0
        
        // Subscribe to F0F2 for SLink responses (handle 0x0024)
        if let f0f2 = self.fileTransferCharacteristic {
            pendingNotificationSubscriptions += 1
            p.setNotifyValue(true, for: f0f2)
            p.discoverDescriptors(for: f0f2)
            print("[DeviceConnectionManager] Subscribing to F0F2 (notifications)")
        }
        
        if let f0f3 = self.fileTransferChar2 {
            pendingNotificationSubscriptions += 1
            p.setNotifyValue(true, for: f0f3)
            p.discoverDescriptors(for: f0f3)
            print("[DeviceConnectionManager] Subscribing to F0F3")
        }
        
        if let f0f4 = self.fileTransferChar3 {
            pendingNotificationSubscriptions += 1
            p.setNotifyValue(true, for: f0f4)
            p.discoverDescriptors(for: f0f4)
            print("[DeviceConnectionManager] Subscribing to F0F4")
        }
        
        print("[DeviceConnectionManager] Waiting for \(pendingNotificationSubscriptions) notifications to enable...")
    }
    
    // MARK: - SLink Initialization Sequence
    
    private func startSLinkInitialization() {
        guard let p = peripheral, p.state == .connected else {
            print("[DeviceConnectionManager] Cannot start init - not connected")
            return
        }
        
        guard let commandChar = commandWriteCharacteristic else {
            print("[DeviceConnectionManager] Cannot start init - F0F1 not found")
            return
        }
        
        print("[DeviceConnectionManager] Starting SLink initialization sequence...")
        slinkState = .handshaking
        initSequenceStep = 0
        
        // Start the sequence
        sendNextInitCommand()
    }
    
    private func sendNextInitCommand() {
        guard let p = peripheral, p.state == .connected else {
            print("[DeviceConnectionManager] Cannot send command - not connected")
            return
        }
        
        guard let commandChar = commandWriteCharacteristic else {
            print("[DeviceConnectionManager] Cannot send command - F0F1 not found")
            return
        }
        
        let commands = SLinkInitSequence.commands
        
        guard initSequenceStep < commands.count else {
            // Sequence complete
            print("[DeviceConnectionManager] Initialization sequence complete!")
            slinkState = .initialized
            connectionState = .initialized
            
            // Subscribe to audio stream
            subscribeToAudioStream()
            startKeepAlive()
            return
        }
        
        let command = commands[initSequenceStep]
        
        // Create packet based on command type
        let packet: SLinkPacket
        if command == .sendSerial {
            packet = SLinkPacket.serialPacket(serial: deviceSerial)
        } else {
            packet = SLinkPacket.command(command)
        }
        
        let data = packet.serializeToData()
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        
        print("[SLink TX] Step \(initSequenceStep + 1)/\(commands.count): \(command.name) -> [\(hexString)]")
        
        p.writeValue(data, for: commandChar, type: .withoutResponse)
        
        addConnectionEvent(.slinkCommandSent(command.name))
        
        pendingCommand = command
        slinkState = stateForStep(initSequenceStep)
        
        // Set timeout for this command
        slinkCommandTimer?.invalidate()
        slinkCommandTimer = Timer.scheduledTimer(withTimeInterval: SLinkConstants.defaultTimeout, repeats: false) { [weak self] _ in
            self?.handleSLinkTimeout()
        }
    }
    
    private func stateForStep(_ step: Int) -> SLinkConnectionState {
        switch step {
        case 0: return .handshaking
        case 1: return .sendingSerial
        case 2: return .gettingDeviceInfo
        case 3: return .configuring
        case 4: return .statusControl
        case 5, 6, 7: return .initializing
        default: return .initializing
        }
    }
    
    private func handleSLinkResponse(_ packet: SLinkPacket) {
        let hexString = packet.serializeToData().map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[SLink RX] Response: [\(hexString)]")
        
        addConnectionEvent(.slinkResponseReceived(packet.debugDescription))
        
        // Check if this is an expected response
        guard let pending = pendingCommand else {
            print("[DeviceConnectionManager] Unsolicited SLink response received")
            return
        }
        
        // Verify this is the expected response type (command bytes should match)
        let expectedCommand = pending.rawValue
        let receivedCommand = packet.command
        
        guard receivedCommand == expectedCommand else {
            print("[DeviceConnectionManager] Unexpected response: expected \(String(format: "0x%04X", expectedCommand)), got \(String(format: "0x%04X", receivedCommand))")
            return
        }
        
        // Cancel timeout
        slinkCommandTimer?.invalidate()
        
        // Process response based on step
        processResponseForCurrentStep(packet: packet)
        
        // Move to next step
        initSequenceStep += 1
        pendingCommand = nil
        
        // Send next command after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + SLinkInitSequence.commandDelay) { [weak self] in
            self?.sendNextInitCommand()
        }
    }
    
    private func processResponseForCurrentStep(packet: SLinkPacket) {
        switch initSequenceStep {
        case 0:
            print("[DeviceConnectionManager] Handshake acknowledged")
        case 1:
            print("[DeviceConnectionManager] Serial acknowledged")
        case 2:
            // Device info response contains serial
            if let serial = packet.deviceSerial {
                print("[DeviceConnectionManager] Device serial from response: \(serial)")
            }
        case 3:
            print("[DeviceConnectionManager] Configuration acknowledged")
        case 4:
            print("[DeviceConnectionManager] Status control acknowledged")
        case 5, 6, 7:
            print("[DeviceConnectionManager] Init command \(initSequenceStep) acknowledged")
        default:
            break
        }
    }
    
    private func handleSLinkTimeout() {
        guard let pending = pendingCommand else { return }
        
        print("[DeviceConnectionManager] SLink command timeout: \(pending.name)")
        
        // Retry this step (up to 3 retries per step)
        if initSequenceStep < 3 {
            print("[DeviceConnectionManager] Retrying step \(initSequenceStep + 1)...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.sendNextInitCommand()
            }
        } else {
            connectionState = .failed("SLink initialization timeout at step \(initSequenceStep + 1)")
            slinkState = .failed("Timeout: \(pending.name)")
        }
    }
    
    func subscribeToAudioStream() {
        guard let peripheral = peripheral,
              let audioChar = audioStreamCharacteristic else {
            print("[DeviceConnectionManager] Cannot subscribe to audio - characteristic not found")
            return
        }
        
        peripheral.setNotifyValue(true, for: audioChar)
        print("[DeviceConnectionManager] Subscribed to audio stream (E49A3003)")
        
        NotificationCenter.default.post(
            name: .audioCharacteristicDidUpdate,
            object: self,
            userInfo: ["characteristic": audioChar]
        )
    }
    
    // MARK: - AudioStreamReceiver Compatibility
    
    /// Alias for audioStreamCharacteristic (for AudioStreamReceiver compatibility)
    var audioNotificationCharacteristic: CBCharacteristic? {
        return audioStreamCharacteristic
    }
    
    /// Subscribe to audio notifications (alias for subscribeToAudioStream)
    func subscribeToAudioNotifications() {
        subscribeToAudioStream()
    }
    
    /// Unsubscribe from audio notifications
    func unsubscribeFromAudioNotifications() {
        guard let peripheral = peripheral,
              let audioChar = audioStreamCharacteristic else {
            return
        }
        peripheral.setNotifyValue(false, for: audioChar)
        print("[DeviceConnectionManager] Unsubscribed from audio notifications")
    }
    
    private func startKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }
    
    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }
    
    private func sendHeartbeat() {
        guard let p = peripheral, p.state == .connected else { return }
        guard let char = commandWriteCharacteristic else { return }
        
        // Simple heartbeat packet
        let heartbeat = SLinkPacket(command: 0x0205, payload: [0x00])
        p.writeValue(heartbeat.serializeToData(), for: char, type: .withoutResponse)
        print("[DeviceConnectionManager] Heartbeat sent")
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[DeviceConnectionManager] Value update error: \(error)")
            return
        }
        
        if let data = characteristic.value {
            let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("[SLink RX] Raw data from \(characteristic.uuid): [\(hexString)]")
            
            // Feed data to SLink parser for F0F2 (handle 0x0024)
            if characteristic.uuid == DVRLinkUUID.fileTransferCharacteristic {
                slinkPacketParser.feed(data)
                
                // Parse any complete packets
                var parseResult = slinkPacketParser.parseNext()
                while case .success(let packet) = parseResult {
                    handleSLinkResponse(packet)
                    parseResult = slinkPacketParser.parseNext()
                }
                
                if case .invalid(let errorMsg) = parseResult {
                    print("[DeviceConnectionManager] SLink parse error: \(errorMsg)")
                }
            }
            
            NotificationCenter.default.post(
                name: .audioCharacteristicDidUpdate,
                object: nil,
                userInfo: ["data": data]
            )
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[DeviceConnectionManager] Notification state error: \(error)")
        } else {
            print("[DeviceConnectionManager] Notifications \(characteristic.isNotifying ? "enabled" : "disabled") for \(characteristic.uuid)")
            
            if characteristic.isNotifying {
                pendingNotificationSubscriptions = max(0, pendingNotificationSubscriptions - 1)
                print("[DeviceConnectionManager] Pending subscriptions: \(pendingNotificationSubscriptions)")
                
                if pendingNotificationSubscriptions == 0 && !hasSentInitialCommand {
                    hasSentInitialCommand = true
                    print("[DeviceConnectionManager] All notifications enabled, starting SLink initialization...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.startSLinkInitialization()
                    }
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[DeviceConnectionManager] Descriptor error for \(characteristic.uuid): \(error)")
            return
        }

        let descriptors = characteristic.descriptors ?? []
        print("[DeviceConnectionManager] \(characteristic.uuid): \(descriptors.count) descriptors")
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didWriteValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error = error {
            print("[DeviceConnectionManager] Write failed: \(error)")
        } else {
            print("[DeviceConnectionManager] Write confirmed for \(characteristic.uuid)")
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let audioCharacteristicDidUpdate = Notification.Name("com.scribe.audioCharacteristicDidUpdate")
}
