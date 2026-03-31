import Foundation
import CoreBluetooth

// MARK: - BluetoothDevice (value type)

public struct BluetoothDevice: Identifiable, Equatable {
    public let id: String        // CBPeripheral.identifier.uuidString
    public let name: String
    public let rssi: Int
    public var isConnected: Bool
    public var batteryLevel: Int?

    public init(id: String, name: String, rssi: Int, isConnected: Bool = false, batteryLevel: Int? = nil) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.isConnected = isConnected
        self.batteryLevel = batteryLevel
    }
}

// MARK: - Scanner Connection Delegate
/// Protocol for forwarding connection callbacks from scanner to connection manager.
public protocol ScannerConnectionDelegate: AnyObject {
    func scannerDidConnect(peripheral: CBPeripheral)
    func scannerDidFailToConnect(peripheral: CBPeripheral, error: Error?)
    func scannerDidDisconnect(peripheral: CBPeripheral, error: Error?)
}

// MARK: - BluetoothDeviceScanner
//
// Wraps CBCentralManager to discover nearby DVR microphones.
//
// Threading model:
//   • BLE callbacks arrive on `bleQueue` (a private serial queue).
//   • All mutations to @Observable properties are dispatched back to the main queue
//     so SwiftUI can safely observe them.
//
// Timing model:
//   • CBCentralManager init is asynchronous — state starts as .unknown.
//   • If startScanning() is called before the manager reaches .poweredOn,
//     the intent is recorded in `pendingScan` and executed automatically
//     when centralManagerDidUpdateState fires with .poweredOn.

@Observable
public class BluetoothDeviceScanner: NSObject {

    // MARK: Private BLE state
    /// Exposed for DeviceConnectionManager - MUST use the SAME centralManager for connections!
    var centralManager: CBCentralManager!
    private let bleQueue = DispatchQueue(label: "com.scribe.ble.scanner", qos: .userInitiated)

    /// Retained CBPeripheral objects keyed by UUID string. Must stay alive for connection.
    private var peripheralMap: [String: CBPeripheral] = [:]
    /// Presentable device models keyed by UUID string.
    private var deviceMap: [String: BluetoothDevice] = [:]
    private var scanning = false
    /// Set to true when startScanning() is called before BLE is ready.
    /// Consumed in centralManagerDidUpdateState(.poweredOn).
    private var pendingScan = false
    
    /// Delegate to receive forwarded connection callbacks (since scanner IS the CBCentralManagerDelegate)
    weak var connectionDelegate: ScannerConnectionDelegate?

    // MARK: Observable (SwiftUI-facing) properties
    public var devices: [BluetoothDevice] {
        Array(deviceMap.values).sorted { $0.name < $1.name }
    }
    public var isScanning: Bool { scanning }
    /// Exposed so the UI can show a "Bluetooth unauthorized" message.
    public var bluetoothState: CBManagerState = .unknown

    // MARK: Known DVR device name fragments (extracted from AI DVR Link binary)
    private let knownDeviceNames: Set<String> = [
        "LA518", "LA519", "L027", "L813", "L815", "L816", "L817", "MAR-2518",
        "19CAEEngine_2MicPhone", "MlpAES2MicTV"
    ]
    private let rssiThreshold: Int = -70

    // MARK: Init
    public override init() {
        super.init()
        // Use a dedicated background queue so BLE callbacks never block the main thread.
        self.centralManager = CBCentralManager(delegate: self, queue: bleQueue)
    }

    // MARK: - Public API

    public func startScanning() {
        // If BLE isn't ready yet, store the intent — performScan() will be called
        // automatically once centralManagerDidUpdateState fires with .poweredOn.
        guard centralManager.state == .poweredOn else {
            pendingScan = true
            print("[BluetoothDeviceScanner] BLE not ready (state=\(centralManager.state.rawValue)), scan queued")
            return
        }
        pendingScan = false
        performScan()
    }

    public func stopScanning() {
        pendingScan = false
        centralManager.stopScan()
        // stopScan() is thread-safe; update the UI flag on main.
        DispatchQueue.main.async { [weak self] in
            self?.scanning = false
        }
        print("[BluetoothDeviceScanner] Scanning stopped")
    }

    /// Scan for `timeout` seconds then stop automatically.
    public func scanForDevices(timeout: TimeInterval) {
        startScanning()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.stopScanning()
        }
    }

    // MARK: - Internal accessor for DeviceConnectionManager

    /// Returns the raw `CBPeripheral` for a given device UUID string.
    /// `DeviceConnectionManager` calls this before calling `centralManager.connect()`.
    func cbPeripheral(for deviceID: String) -> CBPeripheral? {
        peripheralMap[deviceID]
    }

    // MARK: - Private

    /// Actually start the CoreBluetooth scan. Must only be called when state == .poweredOn.
    private func performScan() {
        DispatchQueue.main.async { [weak self] in
            self?.peripheralMap.removeAll()
            self?.deviceMap.removeAll()
            self?.scanning = true
        }
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        print("[BluetoothDeviceScanner] Scanning started")
    }
}

// MARK: - CBCentralManagerDelegate
//
// All callbacks arrive on bleQueue. Every @Observable mutation must be
// dispatched to DispatchQueue.main to avoid data races with SwiftUI.

extension BluetoothDeviceScanner: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bluetoothState = central.state

            switch central.state {
            case .poweredOn:
                print("[BluetoothDeviceScanner] Bluetooth powered on — ready to scan")
                // Execute any scan that was requested before BLE was ready.
                if self.pendingScan {
                    self.pendingScan = false
                    // performScan() calls centralManager on bleQueue — safe to invoke here.
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        self?.performScan()
                    }
                }

            case .poweredOff:
                self.scanning = false
                print("[BluetoothDeviceScanner] Bluetooth powered off")

            case .unauthorized:
                self.scanning = false
                // If you see this, NSBluetoothAlwaysUsageDescription is missing from
                // Info.plist / Build Settings, or the user denied access in Settings.
                print("[BluetoothDeviceScanner] UNAUTHORIZED — check INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription in Build Settings")

            case .resetting:
                print("[BluetoothDeviceScanner] Bluetooth resetting")

            case .unknown:
                print("[BluetoothDeviceScanner] Bluetooth state unknown (still initialising)")

            case .unsupported:
                print("[BluetoothDeviceScanner] Bluetooth not supported on this device")

            @unknown default:
                print("[BluetoothDeviceScanner] Unknown Bluetooth state")
            }
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // This callback arrives on bleQueue — extract values before dispatching.
        let rssiValue = RSSI.intValue
        guard rssiValue > rssiThreshold else { return }

        let deviceName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? peripheral.name
            ?? "Unknown"

        let isKnownDevice = knownDeviceNames.contains { deviceName.contains($0) }
        guard isKnownDevice else { return }

        let uuid = peripheral.identifier.uuidString

        DispatchQueue.main.async { [weak self] in
            guard let self, self.scanning else { return }

            let existing = self.deviceMap[uuid]
            // Retain the CBPeripheral so it stays alive for connection.
            self.peripheralMap[uuid] = peripheral
            self.deviceMap[uuid] = BluetoothDevice(
                id: uuid,
                name: deviceName,
                rssi: rssiValue,
                isConnected: existing?.isConnected ?? false,
                batteryLevel: existing?.batteryLevel
            )
        }
    }
    
    // MARK: - Forward connection callbacks to delegate
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BluetoothDeviceScanner] → Forwarding didConnect to delegate")
        connectionDelegate?.scannerDidConnect(peripheral: peripheral)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[BluetoothDeviceScanner] → Forwarding didFailToConnect to delegate")
        connectionDelegate?.scannerDidFailToConnect(peripheral: peripheral, error: error)
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[BluetoothDeviceScanner] → Forwarding didDisconnect to delegate")
        connectionDelegate?.scannerDidDisconnect(peripheral: peripheral, error: error)
    }
}
