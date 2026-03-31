# Bluetooth Implementation Learnings

**Date:** March 30, 2026  
**Module:** Scribe/Scribe/Sources/Bluetooth/  
**Context:** Phase 1 - External Bluetooth Microphone Integration

---

## Key Issues I Overlooked

### 1. CBCentralManagerDelegate Signature Mismatch

**My Mistake:**
```swift
public func centralManager(_ central: CBCentralManager, 
                           didDiscover devices: [CBPeripheral],
                           advertisementData: [String: Any], 
                           rssi: NSNumber)
```

**Correct Implementation:**
```swift
public func centralManager(_ central: CBCentralManager,
                           didDiscover peripheral: CBPeripheral,
                           advertisementData: [String: Any],
                           rssi RSSI: NSNumber)
```

**Lesson:** The delegate receives **single peripheral** objects, not an array. The array version doesn't exist.

---

### 2. Method Ownership Confusion

**My Mistake:**
```swift
centralManager.discoverServices(nil, for: peripheral)
centralManager.setNotifyValue(true, for: characteristic)
centralManager.writeValue(data, for: characteristic, type: .withResponse)
```

**Correct Implementation:**
```swift
peripheral.discoverServices(nil)
peripheral.setNotifyValue(true, for: characteristic)
peripheral.writeValue(data, for: characteristic, type: writeType)
```

**Lesson:** GATT operations are **CBPeripheral methods**, not CBCentralManager methods. This is a fundamental CoreBluetooth pattern.

---

### 3. Delegate Protocol Separation

**My Mistake:**
- Single `CBCentralManagerDelegate` implementation for all BLE events

**Correct Implementation:**
```swift
extension DeviceConnectionManager: CBCentralManagerDelegate {
    // Connection lifecycle events
}

extension DeviceConnectionManager: CBPeripheralDelegate {
    // GATT operations (services, characteristics, values)
}
```

**Lesson:** CoreBluetooth uses **two separate delegate protocols**:
- `CBCentralManagerDelegate` - Adapter state, connection events
- `CBPeripheralDelegate` - Service discovery, characteristic operations, value updates

---

### 4. Peripheral Lifecycle Management

**My Mistake:**
- CBPeripheral objects could be deallocated before connection

**Correct Implementation:**
```swift
private var peripheralMap: [String: CBPeripheral] = [:]

// In didDiscover:
peripheralMap[uuid] = peripheral  // Retain for connection

// In connect:
guard let cbPeripheral = scanner?.cbPeripheral(for: device.id) else { ... }
```

**Lesson:** CoreBluetooth peripherals must be **retained** until after connection completes, otherwise they get deallocated.

---

### 5. Scanner-Manager Communication Pattern

**My Mistake:**
- Direct property access between classes
- Tight coupling

**Correct Implementation:**
```swift
weak var scanner: BluetoothDeviceScanner?

public func connect(to device: BluetoothDevice) {
    guard let cbPeripheral = scanner?.cbPeripheral(for: device.id) else {
        connectionState = .failed("CBPeripheral not found — scan first")
        return
    }
    // ...
}
```

**Lesson:** Use **weak references** to avoid retain cycles, and provide **accessor methods** for clean abstraction.

---

### 6. Data Flow Architecture

**My Mistake:**
- Direct property access for audio data delivery

**Correct Implementation:**
```swift
NotificationCenter.default.post(
    name: .audioCharacteristicDidUpdate,
    object: nil,
    userInfo: ["data": data]
)
```

**Lesson:** Use **NotificationCenter** for decoupled communication between services.

---

### 7. Write Type Selection

**My Mistake:**
```swift
centralManager.writeValue(data, for: characteristic, type: .withResponse)
```

**Correct Implementation:**
```swift
let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write)
    ? .withResponse
    : .withoutResponse
peripheral.writeValue(data, for: characteristic, type: writeType)
```

**Lesson:** Check characteristic properties to **dynamically select** the appropriate write type.

---

## CoreBluetooth Best Practices Reference

### Method Ownership Matrix

| Operation | Owner | Method Signature |
|-----------|-------|------------------|
| Scan for devices | CBCentralManager | `scanForPeripherals(withServices:options:)` |
| Connect | CBCentralManager | `connect(_:,options:)` |
| Disconnect | CBCentralManager | `cancelPeripheralConnection(_:)` |
| Discover services | CBPeripheral | `discoverServices(_:)` |
| Discover characteristics | CBPeripheral | `discoverCharacteristics(_:for:)` |
| Enable notifications | CBPeripheral | `setNotifyValue(_:for:)` |
| Write value | CBPeripheral | `writeValue(_:for:type:)` |

### Delegate Protocol Responsibilities

| Protocol | Handles |
|----------|---------|
| `CBCentralManagerDelegate` | Bluetooth adapter state, connection/disconnection events |
| `CBPeripheralDelegate` | Service discovery, characteristic discovery, value updates, write responses |

---

## Files Modified

1. **BluetoothDevice.swift** - Fixed delegate signature, added peripheral retention
2. **DeviceConnectionManager.swift** - Split delegates, fixed method ownership, added notification pattern

---

## Resources

- [CoreBluetooth Framework Reference](https://developer.apple.com/documentation/corebluetooth)
- [CBCentralManagerDelegate Protocol](https://developer.apple.com/documentation/corebluetooth/cbcentralmanagerdelegate)
- [CBPeripheralDelegate Protocol](https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate)

---

*This document captures lessons learned during Phase 1 Bluetooth implementation debugging.*
