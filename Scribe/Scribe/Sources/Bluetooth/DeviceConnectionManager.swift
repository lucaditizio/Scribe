import Foundation
import Combine
import CoreBluetooth

// MARK: - Known AI DVR Link GATT UUIDs
// Device actually exposes: E49A3001, E0E0, F0F0, Battery

enum DVRLinkUUID {
    static let primaryService            = CBUUID(string: "E49A3001-F69A-11E8-8EB2-F2801F1B9FD1")
    static let authCharacteristic        = CBUUID(string: "E49A3002-F69A-11E8-8EB2-F2801F1B9FD1")
    static let commandCharacteristic     = CBUUID(string: "E49A3002-F69A-11E8-8EB2-F2801F1B9FD1")
    static let audioStreamCharacteristic = CBUUID(string: "E49A3003-F69A-11E8-8EB2-F2801F1B9FD1")
    static let fileTransferCharacteristic = CBUUID(string: "F0F2")
    static let fileTransferChar2          = CBUUID(string: "F0F3")
    static let fileTransferChar3          = CBUUID(string: "F0F4")
    static let commandWriteChar           = CBUUID(string: "F0F1")
    static let batteryService            = CBUUID(string: "180F")
    static let batteryCharacteristic     = CBUUID(string: "2A19")
}

public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
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
    }
}

// MARK: - DeviceConnectionManager

@Observable
public class DeviceConnectionManager: NSObject, ScannerConnectionDelegate {

    private var peripheral: CBPeripheral?
    private var centralManager: CBCentralManager!
    private let bleQueue = DispatchQueue(label: "com.scribe.ble.connection", qos: .userInitiated)

    weak var scanner: BluetoothDeviceScanner?

    private var authCharacteristic: CBCharacteristic?
    internal var audioNotificationCharacteristic: CBCharacteristic?
    internal var audioDataCharacteristic: CBCharacteristic?
    internal var fileTransferCharacteristic: CBCharacteristic?
    internal var fileTransferChar2: CBCharacteristic?
    internal var fileTransferChar3: CBCharacteristic?
    internal var commandWriteCharacteristic: CBCharacteristic?
    private var audioCCCDDescriptor: CBDescriptor?

    public var connectionState: ConnectionState = .disconnected
    public var connectionEvents: [ConnectionEvent] = []
    public var connectedDevice: BluetoothDevice?
    public var availableServices: [CBService] = []
    public var supportedCharacteristics: [CBCharacteristic] = []

    private let maxReconnectAttempts = 5
    private var reconnectAttempt = 0
    private let userDefaultsKey = "lastConnectedDeviceID"
    private var connectionTimeoutWork: DispatchWorkItem?
    private let connectionTimeoutSeconds: TimeInterval = 10
    
    private var pendingNotificationSubscriptions = 0
    private var hasSentInitialCommand = false
    private var hasReceivedFirstNotification = false
    private var keepAliveTimer: Timer?

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

    public func subscribeToAudioNotifications() {
        guard let characteristic = audioNotificationCharacteristic, let p = peripheral else { return }
        p.setNotifyValue(true, for: characteristic)
    }

    public func unsubscribeFromAudioNotifications() {
        guard let characteristic = audioNotificationCharacteristic, let p = peripheral else { return }
        p.setNotifyValue(false, for: characteristic)
    }

    public func writeAudioData(_ data: Data) {
        guard let characteristic = audioDataCharacteristic, let p = peripheral else { return }
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        p.writeValue(data, for: characteristic, type: writeType)
    }

    private func resetState() {
        stopKeepAlive()
        connectionState = .disconnected
        peripheral = nil
        connectedDevice = nil
        availableServices.removeAll()
        supportedCharacteristics.removeAll()
        authCharacteristic = nil
        audioNotificationCharacteristic = nil
        audioDataCharacteristic = nil
        fileTransferCharacteristic = nil
        fileTransferChar2 = nil
        fileTransferChar3 = nil
        commandWriteCharacteristic = nil
        hasSentInitialCommand = false
        hasReceivedFirstNotification = false
        pendingNotificationSubscriptions = 0
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
                if uuid == DVRLinkUUID.authCharacteristic {
                    self.authCharacteristic = characteristic
                    print("[DeviceConnectionManager] Auth char found")
                } else if uuid == DVRLinkUUID.audioStreamCharacteristic {
                    self.audioNotificationCharacteristic = characteristic
                    print("[DeviceConnectionManager] Audio stream char found (E49A3003)")
                } else if uuid == DVRLinkUUID.fileTransferCharacteristic {
                    self.fileTransferCharacteristic = characteristic
                    print("[DeviceConnectionManager] File transfer char found (F0F2)")
                    peripheral.discoverDescriptors(for: characteristic)
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
            
            self.subscribeToFileTransferChars()
        }
    }
    
    private func subscribeToFileTransferChars() {
        guard let p = peripheral, p.state == .connected else {
            print("[DeviceConnectionManager] Cannot subscribe - peripheral nil or disconnected")
            return
        }
        
        pendingNotificationSubscriptions = 0
        
        if let f0f2 = self.fileTransferCharacteristic {
            pendingNotificationSubscriptions += 1
            p.setNotifyValue(true, for: f0f2)
            p.discoverDescriptors(for: f0f2)
            print("[DeviceConnectionManager] Subscribing to F0F2")
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
    
    private func checkAndSendInitialCommand() {
        if pendingNotificationSubscriptions > 0 {
            print("[DeviceConnectionManager] Still waiting for \(pendingNotificationSubscriptions) notifications")
            return
        }
        
        if hasSentInitialCommand {
            print("[DeviceConnectionManager] Initial command already sent")
            return
        }
        
        sendInitialCommand()
    }
    
    private func sendInitialCommand() {
        guard let p = peripheral else {
            print("[DeviceConnectionManager] No peripheral")
            return
        }
        
        guard p.state == .connected else {
            print("[DeviceConnectionManager] Cannot send initial command - not connected")
            return
        }
        
        guard let char = commandWriteCharacteristic else {
            print("[DeviceConnectionManager] Command char F0F1 not found")
            return
        }
        
        p.writeValue(Data([0x00]), for: char, type: .withoutResponse)
        print("[DeviceConnectionManager] Sent initial command via F0F1")
        hasSentInitialCommand = true
    }
    
    private func startKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.sendDeviceCommand("heartbeat")
        }
    }
    
    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }
    
    private func sendDeviceCommand(_ command: String) {
        guard let p = peripheral else {
            print("[DeviceConnectionManager] No peripheral")
            return
        }
        
        guard p.state == .connected else {
            print("[DeviceConnectionManager] Cannot send command - not connected")
            return
        }
        
        guard let char = commandWriteCharacteristic else {
            print("[DeviceConnectionManager] Command char F0F1 not available")
            return
        }
        
        let commandData: Data
        if command == "start_record" {
            commandData = Data([0x01, 0x00, 0x00, 0x00])
        } else if command == "get_status" {
            commandData = Data([0x02, 0x00, 0x00, 0x00])
        } else if command == "heartbeat" {
            commandData = Data([0x00, 0x00, 0x00, 0x00])
        } else {
            commandData = Data([0x00])
        }
        
        p.writeValue(commandData, for: char, type: .withoutResponse)
        print("[DeviceConnectionManager] Sent command: \(command)")
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[DeviceConnectionManager] Value update error: \(error)")
            return
        }
        
        if let data = characteristic.value {
            let bytes = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("[DeviceConnectionManager] Received from \(characteristic.uuid): [\(bytes)]")
            
            if characteristic.uuid == DVRLinkUUID.fileTransferCharacteristic ||
               characteristic.uuid == DVRLinkUUID.fileTransferChar2 ||
               characteristic.uuid == DVRLinkUUID.fileTransferChar3 ||
               characteristic.uuid == DVRLinkUUID.audioStreamCharacteristic {
                if !hasReceivedFirstNotification {
                    hasReceivedFirstNotification = true
                    print("[DeviceConnectionManager] First notification received, starting keep-alive")
                    startKeepAlive()
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
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.checkAndSendInitialCommand()
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

        for descriptor in descriptors {
            print("[DeviceConnectionManager]   Descriptor: \(descriptor.uuid)")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        if let error = error {
            print("[DeviceConnectionManager] Descriptor write error: \(error)")
        } else {
            print("[DeviceConnectionManager] Descriptor \(descriptor.uuid) write SUCCESS")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[DeviceConnectionManager] Write error for \(characteristic.uuid): \(error)")
        } else {
            print("[DeviceConnectionManager] Write success for \(characteristic.uuid)")
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let audioCharacteristicDidUpdate = Notification.Name("com.scribe.audioCharacteristicDidUpdate")
}
