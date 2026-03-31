# Bluetooth Not Working — Root Cause Analysis & Fix Guide

## Why the permission prompt never appears

There are **three separate problems**, each of which would silently kill Bluetooth on its own. All three must be fixed together.

---

## Problem 1 — Missing `NSBluetoothAlwaysUsageDescription` (CRITICAL)

### What it is
iOS requires every app that uses CoreBluetooth to declare a human-readable purpose string in its `Info.plist`. Without it, iOS **silently denies** all Bluetooth access — no prompt is ever shown to the user, and `CBCentralManager` immediately enters the `.unauthorized` state.

### Where the gap is
The Xcode project uses `GENERATE_INFOPLIST_FILE = YES` (auto-generated plist from build settings). It already has:

```
INFOPLIST_KEY_NSMicrophoneUsageDescription = "Scribe needs access to the microphone"
INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "..."
```

But it is **missing**:

```
INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription
```

### How to fix it

**In Xcode (recommended — matches how the existing mic key is set):**

1. Open `Scribe.xcodeproj` in Xcode
2. Click the **Scribe** target → **Build Settings** tab
3. Search for `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription`
4. Set the value for both Debug and Release to:
   `"Scribe uses Bluetooth to connect to your AI DVR microphone for live recording and file synchronization."`

> [!IMPORTANT]
> The key name in Build Settings is `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription` (not `NSBluetoothPeripheralUsageDescription` — that key is deprecated since iOS 13 and does nothing on modern devices).

---

## Problem 2 — `CBCentralManager` is created with `queue: nil` (main thread)

### What it is
`CBCentralManager(delegate:queue:)` with `queue: nil` runs all delegate callbacks on the **main thread**. On modern iOS (17+), `@Observable` classes also expect their mutations to happen on the main actor. This is actually fine for simple cases — but it means the very first call, which triggers the permission prompt, races against SwiftUI's render cycle.

More critically: the `CBCentralManager` is being created inside `init()` of two different classes — both `BluetoothDeviceScanner` and `DeviceConnectionManager` create their own separate `CBCentralManager`. **Each `CBCentralManager` init triggers an independent Bluetooth permission check.** If the first one is authorized and the second one's initialization timing is off, one manager may enter `.unauthorized` while the other is `.poweredOn`. This creates an inconsistent state.

### How to fix it

Give `CBCentralManager` an explicit background queue so delegate callbacks don't block the UI. Always isolate mutations back to the main actor explicitly:

**In `BluetoothDeviceScanner.swift`**, change the init:

```swift
// Before
self.centralManager = CBCentralManager(delegate: self, queue: nil)

// After
private let bleQueue = DispatchQueue(label: "com.scribe.ble", qos: .userInitiated)

// In init:
self.centralManager = CBCentralManager(delegate: self, queue: bleQueue)
```

**In `DeviceConnectionManager.swift`**, do the same:

```swift
private let bleQueue = DispatchQueue(label: "com.scribe.ble.connection", qos: .userInitiated)

// In init:
self.centralManager = CBCentralManager(delegate: self, queue: bleQueue)
```

Then, in every delegate callback that mutates `@Observable` properties, dispatch back to the main queue:

```swift
public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        switch central.state {
        case .poweredOn:
            print("[BluetoothDeviceScanner] Bluetooth powered on — ready to scan")
        // ... etc
        }
    }
}
```

Apply `DispatchQueue.main.async { }` to **every** delegate method that writes to a published/observable property.

---

## Problem 3 — `startScanning()` is called before `CBCentralManager` is ready

### What it is
When the user taps "Scan" in `DeviceSettingsView`, `scanForDevices(timeout:)` calls `startScanning()`. Inside `startScanning()` there is a guard:

```swift
guard centralManager.state == .poweredOn else {
    print("[BluetoothDeviceScanner] Cannot scan — Bluetooth not powered on")
    return
}
```

**This guard will almost always fire on first tap.** Here's why:

`CBCentralManager` initialization is **asynchronous**. Creating it with `CBCentralManager(delegate:queue:)` does not mean it is immediately `.poweredOn`. On a fresh app launch, the manager will be in `.unknown` state for a brief period, then transition to `.poweredOn` (calling `centralManagerDidUpdateState`). If the user taps "Scan" within the first few seconds of opening the DeviceSettingsView sheet, `centralManager.state` is still `.unknown`, the guard fires, scanning never starts, and nothing happens — with no feedback to the user.

### How to fix it

Add a **pending scan** flag. If `startScanning()` is called before the manager is ready, store the intent and start scanning as soon as `centralManagerDidUpdateState` fires with `.poweredOn`:

**In `BluetoothDeviceScanner.swift`:**

```swift
// Add this property
private var pendingScan = false

public func startScanning() {
    guard centralManager.state == .poweredOn else {
        // Store the intent — will be executed in centralManagerDidUpdateState
        pendingScan = true
        print("[BluetoothDeviceScanner] BLE not ready yet, scan queued")
        return
    }
    pendingScan = false
    performScan()
}

private func performScan() {
    peripheralMap.removeAll()
    deviceMap.removeAll()
    scanning = true
    centralManager.scanForPeripherals(withServices: nil, options: [
        CBCentralManagerScanOptionAllowDuplicatesKey: false
    ])
    print("[BluetoothDeviceScanner] Scanning started")
}

// In centralManagerDidUpdateState:
public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        switch central.state {
        case .poweredOn:
            print("[BluetoothDeviceScanner] Bluetooth powered on — ready to scan")
            if self.pendingScan {
                self.pendingScan = false
                self.performScan()   // ← execute the deferred scan
            }
        case .unauthorized:
            self.scanning = false
            print("[BluetoothDeviceScanner] Bluetooth unauthorized — check Info.plist for NSBluetoothAlwaysUsageDescription")
        // ... other cases
        }
    }
}
```

---

## Summary Checklist

| # | Problem | Where to fix | Manual or code? |
|---|---|---|---|
| 1 | Missing `NSBluetoothAlwaysUsageDescription` | Xcode Build Settings | **Manual in Xcode** |
| 2 | BLE delegates mutating state on wrong thread | `BluetoothDeviceScanner.swift` + `DeviceConnectionManager.swift` | Code |
| 3 | Scan silently dropped if BLE not ready yet | `BluetoothDeviceScanner.swift` | Code |

> [!CAUTION]
> Fix Problem 1 **first**. Without the Info.plist key, CoreBluetooth will never call `centralManagerDidUpdateState` with `.poweredOn` — it will call it with `.unauthorized` immediately. Problems 2 and 3 become irrelevant until the permission key exists.

> [!NOTE]
> After adding the key and rebuilding, go to **Settings → Scribe → Bluetooth** on the device and confirm the toggle is On. If the app has been run before without the key, iOS may have silently denied access, and the prompt will **not** appear again automatically. You must grant access manually in Settings the first time after adding the key.

---

## How to verify it's working

1. Add the plist key (Problem 1), rebuild and install on device
2. Open the sheet → tap "Scan" — you should see a system Bluetooth permission alert
3. Grant permission — `centralManagerDidUpdateState` should fire with `.poweredOn`
4. With fixes for Problems 2 & 3 applied: scanning should start immediately or on the next tap

Add this log line to confirm the BLE state flow:

```swift
case .unauthorized:
    print("[BLE] UNAUTHORIZED — NSBluetoothAlwaysUsageDescription missing or user denied")
```

If this line appears in the console, Problem 1 is not yet fixed.
