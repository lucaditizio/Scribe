import XCTest
@testable import Scribe
import CoreBluetooth

@MainActor
final class BluetoothDeviceTests: XCTestCase {
    
    func testBluetoothDeviceInitialization() {
        // Given
        let id = "test-id-123"
        let name = "LA518"
        let rssi = -55
        
        // When
        let device = BluetoothDevice(id: id, name: name, rssi: rssi)
        
        // Then
        XCTAssertEqual(device.id, id)
        XCTAssertEqual(device.name, name)
        XCTAssertEqual(device.rssi, rssi)
        XCTAssertFalse(device.isConnected)
        XCTAssertNil(device.batteryLevel)
    }
    
    func testBluetoothDeviceWithAllProperties() {
        // Given
        let id = "test-id-456"
        let name = "MAR-2518"
        let rssi = -60
        let batteryLevel = 85
        
        // When
        let device = BluetoothDevice(id: id, name: name, rssi: rssi, isConnected: true, batteryLevel: batteryLevel)
        
        // Then
        XCTAssertEqual(device.id, id)
        XCTAssertEqual(device.name, name)
        XCTAssertEqual(device.rssi, rssi)
        XCTAssertTrue(device.isConnected)
        XCTAssertEqual(device.batteryLevel, batteryLevel)
    }
    
    func testBluetoothDeviceEquatable() {
        // Given
        let device1 = BluetoothDevice(id: "same-id", name: "Test", rssi: -50)
        let device2 = BluetoothDevice(id: "same-id", name: "Test", rssi: -50)
        let device3 = BluetoothDevice(id: "different-id", name: "Test", rssi: -50)
        
        // Then
        XCTAssertEqual(device1, device2)
        XCTAssertNotEqual(device1, device3)
    }
    
    func testBluetoothDeviceIdentifiable() {
        // Given
        let device = BluetoothDevice(id: "unique-id", name: "Test", rssi: -50)
        
        // Then
        XCTAssertEqual(device.id, "unique-id")
    }
}

@MainActor
final class ConnectionStateTests: XCTestCase {
    
    func testConnectionStateEquatable() {
        // Given
        let state1 = ConnectionState.connected
        let state2 = ConnectionState.connected
        let state3 = ConnectionState.failed("error")
        let state4 = ConnectionState.failed("error")
        let state5 = ConnectionState.failed("different error")
        
        // Then
        XCTAssertEqual(state1, state2)
        XCTAssertEqual(state3, state4)
        XCTAssertNotEqual(state1, state3)
        XCTAssertNotEqual(state3, state5)
    }
    
    func testConnectionStateReconnecting() {
        // Given
        let state1 = ConnectionState.reconnecting(1)
        let state2 = ConnectionState.reconnecting(1)
        let state3 = ConnectionState.reconnecting(2)
        
        // Then
        XCTAssertEqual(state1, state2)
        XCTAssertNotEqual(state1, state3)
    }
}

@MainActor
final class ConnectionEventTests: XCTestCase {
    
    func testConnectionEventInitialization() {
        // Given
        let type = ConnectionEvent.ConnectionEventType.connected
        let message = "Connected to device"
        
        // When
        let event = ConnectionEvent(type: type, message: message)
        
        // Then
        XCTAssertEqual(event.type, type)
        XCTAssertEqual(event.message, message)
    }
    
    func testConnectionEventWithoutMessage() {
        // Given
        let type = ConnectionEvent.ConnectionEventType.servicesDiscovered
        
        // When
        let event = ConnectionEvent(type: type, message: nil)
        
        // Then
        XCTAssertEqual(event.type, type)
        XCTAssertNil(event.message)
    }
    
    func testConnectionEventEquatable() {
        // Given
        let event1 = ConnectionEvent(type: .connected, message: "Connected")
        let event2 = ConnectionEvent(type: .connected, message: "Connected")
        let event3 = ConnectionEvent(type: .disconnected, message: "Disconnected")
        
        // Then
        XCTAssertEqual(event1, event2)
        XCTAssertNotEqual(event1, event3)
    }
}

@MainActor
final class DeviceConnectionManagerTests: XCTestCase {
    
    var manager: DeviceConnectionManager!
    var mockScanner: MockBluetoothDeviceScanner!
    
    override func setUp() {
        super.setUp()
        mockScanner = MockBluetoothDeviceScanner()
        manager = DeviceConnectionManager(scanner: mockScanner)
    }
    
    override func tearDown() {
        manager = nil
        mockScanner = nil
        super.tearDown()
    }
    
    func testInitialState() {
        // Then
        XCTAssertEqual(manager.connectionState, .disconnected)
        XCTAssertTrue(manager.connectionEvents.isEmpty)
        XCTAssertNil(manager.connectedDevice)
        XCTAssertTrue(manager.availableServices.isEmpty)
    }
    
    func testConnectWithValidDevice() {
        // Given
        let device = BluetoothDevice(id: "test-id", name: "LA518", rssi: -50)
        mockScanner.stubPeripheral(for: device.id, peripheral: MockCBPeripheral())
        
        // When
        manager.connect(to: device)
        
        // Then
        XCTAssertEqual(manager.connectionState, .connecting)
        XCTAssertEqual(manager.connectedDevice?.id, device.id)
    }
    
    func testConnectWithInvalidDevice() {
        // Given
        let device = BluetoothDevice(id: "non-existent-id", name: "LA518", rssi: -50)
        
        // When
        manager.connect(to: device)
        
        // Then
        XCTAssertEqual(manager.connectionState, .failed("CBPeripheral not found — scan first"))
        XCTAssertNil(manager.connectedDevice)
    }
    
    func testDisconnect() {
        // Given
        let device = BluetoothDevice(id: "test-id", name: "LA518", rssi: -50)
        mockScanner.stubPeripheral(for: device.id, peripheral: MockCBPeripheral())
        manager.connect(to: device)
        XCTAssertEqual(manager.connectionState, .connecting)
        
        // When
        manager.disconnect()
        
        // Then
        XCTAssertEqual(manager.connectionState, .disconnected)
        XCTAssertNil(manager.connectedDevice)
    }
    
    func testReconnectAttempts() {
        // Given
        let device = BluetoothDevice(id: "test-id", name: "LA518", rssi: -50)
        mockScanner.stubPeripheral(for: device.id, peripheral: MockCBPeripheral())
        manager.connect(to: device)
        
        // When - Trigger reconnection 6 times (max is 5)
        for _ in 0..<6 {
            manager.reconnect()
        }
        
        // Then
        XCTAssertEqual(manager.connectionState, .failed("Max reconnection attempts reached"))
    }
    
    func testPersistLastConnectedDevice() {
        // Given
        let device = BluetoothDevice(id: "persist-test-id", name: "LA518", rssi: -50)
        mockScanner.stubPeripheral(for: device.id, peripheral: MockCBPeripheral())
        manager.connect(to: device)
        
        // When
        manager.persistLastConnectedDevice()
        
        // Then
        let storedId = UserDefaults.standard.string(forKey: "lastConnectedDeviceID")
        XCTAssertEqual(storedId, device.id)
    }
    
    func testDiscoverServices() {
        // Given
        let device = BluetoothDevice(id: "test-id", name: "LA518", rssi: -50)
        let mockPeripheral = MockCBPeripheral()
        mockScanner.stubPeripheral(for: device.id, peripheral: mockPeripheral)
        manager.connect(to: device)
        
        // When
        manager.discoverServices()
        
        // Then
        XCTAssertTrue(mockPeripheral.discoverServicesCalled)
    }
    
    func testSubscribeToAudioNotifications() {
        // Given
        let device = BluetoothDevice(id: "test-id", name: "LA518", rssi: -50)
        let mockPeripheral = MockCBPeripheral()
        mockScanner.stubPeripheral(for: device.id, peripheral: mockPeripheral)
        manager.connect(to: device)
        manager.audioNotificationCharacteristic = CBCharacteristic()
        
        // When
        manager.subscribeToAudioNotifications()
        
        // Then
        XCTAssertTrue(mockPeripheral.setNotifyValueCalled)
    }
    
    func testWriteAudioData() {
        // Given
        let device = BluetoothDevice(id: "test-id", name: "LA518", rssi: -50)
        let mockPeripheral = MockCBPeripheral()
        mockScanner.stubPeripheral(for: device.id, peripheral: mockPeripheral)
        manager.connect(to: device)
        manager.audioDataCharacteristic = CBCharacteristic(properties: [.write])
        let testData = Data([0x01, 0x02, 0x03])
        
        // When
        manager.writeAudioData(testData)
        
        // Then
        XCTAssertTrue(mockPeripheral.writeValueCalled)
    }
}

@MainActor
final class AudioStreamReceiverTests: XCTestCase {
    
    var receiver: AudioStreamReceiver!
    var mockConnectionManager: MockDeviceConnectionManager!
    
    override func setUp() {
        super.setUp()
        mockConnectionManager = MockDeviceConnectionManager()
        receiver = AudioStreamReceiver(connectionManager: mockConnectionManager)
    }
    
    override func tearDown() {
        receiver = nil
        mockConnectionManager = nil
        super.tearDown()
    }
    
    func testInitialState() {
        // Then
        XCTAssertEqual(receiver.state, .idle)
        XCTAssertFalse(receiver.isStreaming)
        XCTAssertTrue(receiver.receivedFrames.isEmpty)
        XCTAssertEqual(receiver.frameCount, 0)
    }
    
    func testStartStreamingWhenNotConnected() {
        // Given
        mockConnectionManager.connectionState = .disconnected
        
        // When
        try? receiver.startStreaming()
        
        // Then
        XCTAssertEqual(receiver.state, .error(AudioStreamError.notConnected.localizedDescription))
        XCTAssertFalse(receiver.isStreaming)
    }
    
    func testStartStreamingWhenConnected() {
        // Given
        mockConnectionManager.connectionState = .connected
        mockConnectionManager.stubAudioNotificationCharacteristic()
        
        // When
        try? receiver.startStreaming()
        
        // Then
        XCTAssertEqual(receiver.state, .streaming)
        XCTAssertTrue(receiver.isStreaming)
    }
    
    func testStopStreaming() {
        // Given
        mockConnectionManager.connectionState = .connected
        mockConnectionManager.stubAudioNotificationCharacteristic()
        try? receiver.startStreaming()
        XCTAssertEqual(receiver.state, .streaming)
        
        // When
        receiver.stopStreaming()
        
        // Then
        XCTAssertEqual(receiver.state, .paused)
        XCTAssertFalse(receiver.isStreaming)
    }
    
    func testProcessAudioFrame() {
        // Given
        let audioData = Data([0x01, 0x02, 0x03, 0x04])
        let frame = AudioFrame(data: audioData, timestamp: Date(), sampleRate: 16000)
        
        // When
        receiver.processAudioFrame(frame)
        
        // Then
        XCTAssertEqual(receiver.receivedFrames.count, 1)
        XCTAssertEqual(receiver.frameCount, 1)
        XCTAssertEqual(receiver.lastFrameTimestamp, frame.timestamp)
        XCTAssertEqual(receiver.receivedFrames[0].data, audioData)
    }
    
    func testProcessMultipleAudioFrames() {
        // Given
        let frame1 = AudioFrame(data: Data([0x01]), timestamp: Date())
        let frame2 = AudioFrame(data: Data([0x02]), timestamp: Date())
        let frame3 = AudioFrame(data: Data([0x03]), timestamp: Date())
        
        // When
        receiver.processAudioFrame(frame1)
        receiver.processAudioFrame(frame2)
        receiver.processAudioFrame(frame3)
        
        // Then
        XCTAssertEqual(receiver.frameCount, 3)
        XCTAssertEqual(receiver.receivedFrames[0].data, Data([0x01]))
        XCTAssertEqual(receiver.receivedFrames[1].data, Data([0x02]))
        XCTAssertEqual(receiver.receivedFrames[2].data, Data([0x03]))
    }
    
    func testAverageBitrateCalculation() {
        // Given
        let frame1 = AudioFrame(data: Data(repeating: 0, count: 100), timestamp: Date())
        let frame2 = AudioFrame(data: Data(repeating: 0, count: 200), timestamp: Date(timeIntervalSince: frame1.timestamp, by: 1.0))
        
        // When
        receiver.processAudioFrame(frame1)
        receiver.processAudioFrame(frame2)
        
        // Then
        XCTAssertNotNil(receiver.averageBitrate)
        XCTAssertEqual(receiver.averageBitrate, 1200) // (100 + 200) * 8 bits / 2 seconds = 1200 bps
    }
}

@MainActor
final class DeviceFileSyncServiceTests: XCTestCase {
    
    var service: DeviceFileSyncService!
    var mockConnectionManager: MockDeviceConnectionManager!
    
    override func setUp() {
        super.setUp()
        mockConnectionManager = MockDeviceConnectionManager()
        service = DeviceFileSyncService(connectionManager: mockConnectionManager)
    }
    
    override func tearDown() {
        service = nil
        mockConnectionManager = nil
        super.tearDown()
    }
    
    func testInitialState() {
        // Then
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.transferProgress, 0.0)
        XCTAssertTrue(service.files.isEmpty)
        XCTAssertFalse(service.isTransferring)
    }
    
    func testEnumerateFilesWhenNotConnected() {
        // Given
        mockConnectionManager.connectionState = .disconnected
        
        // When
        try? service.enumerateFiles()
        
        // Then
        XCTAssertEqual(service.state, .failed("Not connected to device"))
    }
    
    func testEnumerateFilesWhenConnected() {
        // Given
        mockConnectionManager.connectionState = .connected
        mockConnectionManager.stubFileList([
            DeviceFile(id: "1", name: "recording1.m4a", size: 1024000, createdAt: Date(), modifiedAt: Date(), filePathOnDevice: "/recordings/recording1.m4a"),
            DeviceFile(id: "2", name: "recording2.m4a", size: 2048000, createdAt: Date(), modifiedAt: Date(), filePathOnDevice: "/recordings/recording2.m4a")
        ])
        
        // When
        try? service.enumerateFiles()
        
        // Then
        XCTAssertEqual(service.state, .completed)
        XCTAssertEqual(service.files.count, 2)
        XCTAssertEqual(service.files[0].name, "recording1.m4a")
        XCTAssertEqual(service.files[1].name, "recording2.m4a")
    }
    
    func testDownloadFile() {
        // Given
        let file = DeviceFile(id: "1", name: "recording1.m4a", size: 1024000, createdAt: Date(), modifiedAt: Date(), filePathOnDevice: "/recordings/recording1.m4a")
        service.files = [file]
        
        // When
        let result = service.downloadFile(file)
        
        // Then
        XCTAssertTrue(result.isSuccess)
        XCTAssertNotNil(result.data)
        XCTAssertEqual(result.data?.count, 1024000)
    }
    
    func testDownloadFileNotFound() {
        // When
        let file = DeviceFile(id: "non-existent", name: "missing.m4a", size: 1024, createdAt: Date(), modifiedAt: Date(), filePathOnDevice: "/missing.m4a")
        let result = service.downloadFile(file)
        
        // Then
        XCTAssertFalse(result.isSuccess)
        XCTAssertNil(result.data)
    }
    
    func testSyncRecordings() {
        // Given
        mockConnectionManager.connectionState = .connected
        mockConnectionManager.stubFileList([
            DeviceFile(id: "1", name: "sync-test.m4a", size: 512000, createdAt: Date(), modifiedAt: Date(), filePathOnDevice: "/recordings/sync-test.m4a")
        ])
        
        // When
        try? service.syncRecordings()
        
        // Then
        XCTAssertEqual(service.state, .completed)
        XCTAssertEqual(service.files.count, 1)
        XCTAssertFalse(service.isTransferring)
    }
    
    func testIsTransferringState() {
        // Given
        service.state = .enumerating
        
        // Then
        XCTAssertTrue(service.isTransferring)
        
        // When
        service.state = .completed
        
        // Then
        XCTAssertFalse(service.isTransferring)
    }
}

// MARK: - Mocks

final class MockBluetoothDeviceScanner: BluetoothDeviceScanner {
    var stubbedPeripherals: [String: CBPeripheral] = [:]
    
    func stubPeripheral(for id: String, peripheral: CBPeripheral) {
        stubbedPeripherals[id] = peripheral
    }
    
    override func cbPeripheral(for deviceID: String) -> CBPeripheral? {
        return stubbedPeripherals[deviceID]
    }
}

final class MockCBPeripheral: CBPeripheral {
    var discoverServicesCalled = false
    var setNotifyValueCalled = false
    var writeValueCalled = false
    var delegate: CBPeripheralDelegate?
    
    override init(identifier: UUID, name: String?) {
        super.init(identifier: identifier, name: name)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func discoverServices(_ services: [CBUUID]?) {
        discoverServicesCalled = true
        delegate?.peripheral(self, didDiscoverServices: nil)
    }
    
    override func discoverCharacteristics(_ characteristics: [CBUUID]?, for service: CBService) {
        delegate?.peripheral(self, didDiscoverCharacteristicsFor: service, error: nil)
    }
    
    override func setNotifyValue(_ notify: Bool, for characteristic: CBCharacteristic) {
        setNotifyValueCalled = true
        delegate?.peripheral(self, didUpdateNotificationStateFor: characteristic, error: nil)
    }
    
    override func writeValue(_ value: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        writeValueCalled = true
        delegate?.peripheral(self, didWriteValueFor: characteristic, error: nil)
    }
    
    override var isConnected: Bool { true }
    override var services: [CBService]? {
        let service = CBService(uuid: CBUUID(string: "test-service"), isPrimary: true)
        let characteristic = CBCharacteristic(uuid: CBUUID(string: "test-char"), properties: [.notify, .write], value: nil, descriptors: [])
        service.characteristics = [characteristic]
        return [service]
    }
}

final class MockDeviceConnectionManager: DeviceConnectionManager {
    var connectionState: ConnectionState = .disconnected
    var stubbedFileList: [DeviceFile] = []
    var stubbedAudioNotificationCharacteristic: CBCharacteristic?
    var stubbedAudioDataCharacteristic: CBCharacteristic?
    
    override init(scanner: BluetoothDeviceScanner?) {
        super.init(scanner: scanner)
    }
    
    func stubFileList(_ files: [DeviceFile]) {
        stubbedFileList = files
    }
    
    func stubAudioNotificationCharacteristic() {
        stubbedAudioNotificationCharacteristic = CBCharacteristic()
    }
    
    func stubAudioDataCharacteristic() {
        stubbedAudioDataCharacteristic = CBCharacteristic(properties: [.write])
    }
    
    override func connect(to device: BluetoothDevice) {
        connectionState = .connected
    }
    
    override func disconnect() {
        connectionState = .disconnected
    }
    
    override func enumerateFiles() throws {
        if connectionState != .connected {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        // Simulate file enumeration
        for file in stubbedFileList {
            NotificationCenter.default.post(
                name: .fileEnumerationComplete,
                object: nil,
                userInfo: ["files": stubbedFileList]
            )
        }
    }
    
    override func downloadFile(_ file: DeviceFile) -> FileDownloadResult {
        // Simulate successful download
        return FileDownloadResult(isSuccess: true, data: Data(repeating: 0, count: Int(file.size)))
    }
}

// MARK: - Additional Test Extensions

extension Notification.Name {
    static let fileEnumerationComplete = Notification.Name("fileEnumerationComplete")
}

extension AudioStreamReceiver {
    func processAudioFrame(_ frame: AudioFrame) {
        receivedFrames.append(frame)
        lastFrameTimestamp = frame.timestamp
        
        if receivedFrames.count >= 2 {
            let timeDiff = receivedFrames[1].timestamp.timeIntervalSince(receivedFrames[0].timestamp)
            if timeDiff > 0 {
                let totalBytes = receivedFrames.reduce(0) { $0 + $1.data.count }
                averageBitrate = (totalBytes * 8) / Int(timeDiff)
            }
        }
    }
}

extension DeviceFile {
    init(id: String, name: String, size: Int64, createdAt: Date, modifiedAt: Date, filePathOnDevice: String) {
        self.init(id: id, name: name, size: size, createdAt: createdAt, modifiedAt: modifiedAt, filePathOnDevice: filePathOnDevice)
    }
}
