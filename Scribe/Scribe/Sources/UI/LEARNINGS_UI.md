# UI Implementation Learnings

**Date:** March 30, 2026  
**File:** DeviceSettingsView.swift  
**Context:** Phase 1 - External Bluetooth Microphone Integration

---

## Key Issue: @State with @Observable Classes

### The Problem

```swift
// ❌ WRONG - Causes "self used before stored properties are initialized"
struct DeviceSettingsView: View {
    @State private var scanner: BluetoothDeviceScanner
    @State private var connectionManager: DeviceConnectionManager
    
    init() {
        self._scanner = StateObject(wrappedValue: BluetoothDeviceScanner())
        self._connectionManager = StateObject(wrappedValue: DeviceConnectionManager())
    }
}
```

**Why it fails:**
- `@State` is designed for **value types** (structs)
- When used with `@Observable` classes, SwiftUI's init chain tries to reference `self.scanner`
- But `@State` wrappers haven't been fully initialized yet
- Result: "self used before stored properties are initialized"

### The Solution

```swift
// ✅ CORRECT - Plain properties for @Observable classes
struct DeviceSettingsView: View {
    private let scanner = BluetoothDeviceScanner()
    private let connectionManager: DeviceConnectionManager
    private let fileSyncService: DeviceFileSyncService
    
    init() {
        let scanner = BluetoothDeviceScanner()
        let mgr = DeviceConnectionManager(scanner: scanner)
        self.connectionManager = mgr
        self.fileSyncService = DeviceFileSyncService(connectionManager: mgr)
    }
}
```

**Why it works:**
- `@Observable` macro generates all necessary `willSet`/`didSet` hooks
- No need for `@State`, `@StateObject`, or `@ObservedObject`
- SwiftUI automatically observes changes to `@Observable` properties
- Plain properties can be initialized in `init()` without conflicts

---

## Pattern: Service Composition in Views

### Before (Tight Coupling)

```swift
struct DeviceSettingsView: View {
    @StateObject private var scanner: BluetoothDeviceScanner
    @StateObject private var connectionManager: DeviceConnectionManager
    @StateObject private var fileSyncService: DeviceFileSyncService
    
    init() {
        self._scanner = StateObject(wrappedValue: BluetoothDeviceScanner())
        self._connectionManager = StateObject(wrappedValue: DeviceConnectionManager())
        self._fileSyncService = StateObject(wrappedValue: DeviceFileSyncService())
    }
}
```

**Issues:**
- No clear dependency flow
- Services don't know about each other
- Hard to test

### After (Explicit Composition)

```swift
struct DeviceSettingsView: View {
    private let scanner = BluetoothDeviceScanner()
    private let connectionManager: DeviceConnectionManager
    private let fileSyncService: DeviceFileSyncService
    
    init() {
        let scanner = BluetoothDeviceScanner()
        let mgr = DeviceConnectionManager(scanner: scanner)  // ← Inject scanner
        self.connectionManager = mgr
        self.fileSyncService = DeviceFileSyncService(connectionManager: mgr)  // ← Inject manager
    }
}
```

**Benefits:**
- Clear dependency injection flow
- Services can reference each other
- Easier to test with mocks
- Single source of truth for service initialization

---

## Pattern: Card-Based UI Architecture

### Before (Flat Section Layout)

```swift
struct DeviceSettingsView: View {
    var body: some View {
        NavigationView {
            VStack {
                DeviceConnectionSection(...)
                DeviceListSection(...)
                FileSyncSection(...)
            }
        }
    }
}
```

**Issues:**
- Inconsistent styling
- Hard to maintain visual coherence
- No shared design system

### After (Card-Based Design System)

```swift
struct DeviceSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ConnectionStatusCard(...)
                    .scribeCardStyle(scheme: colorScheme)
                
                DeviceListCard(...)
                    .scribeCardStyle(scheme: colorScheme)
                
                FileSyncCard(...)
                    .scribeCardStyle(scheme: colorScheme)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Theme.obsidian.ignoresSafeArea())
    }
}
```

**Benefits:**
- Consistent visual design
- Reusable card components
- Easy to apply theme changes
- Better separation of concerns

---

## Pattern: Theme Integration

### Before (Hardcoded Colors)

```swift
struct DeviceRowView: View {
    private var signalStrengthColor: Color {
        if rssi > -50 { return .green }
        else if rssi > -60 { return .yellow }
        else { return .red }
    }
}
```

### After (Theme-Aware Design)

```swift
struct DeviceRow: View {
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isConnected ? "mic.fill" : "mic")
                    .foregroundStyle(isConnected ? Theme.scribeRed : .secondary)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        
                        if isConnected {
                            Text("Connected")
                                .background(Theme.scribeRed.opacity(0.15))
                                .foregroundStyle(Theme.scribeRed)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isConnected ? Theme.scribeRed.opacity(0.07) : Color.primary.opacity(0.04))
            )
        }
    }
}
```

**Benefits:**
- Consistent brand colors (`Theme.scribeRed`)
- Supports light/dark mode via `Theme.obsidian`
- Professional, polished appearance

---

## Pattern: Component Hierarchy

### Component Breakdown

```
DeviceSettingsView (root)
├── ConnectionStatusCard
│   ├── Status indicator dot
│   ├── Status title
│   ├── Device info (name, RSSI)
│   └── Disconnect button
├── DeviceListCard
│   ├── Scanning state
│   ├── Empty state
│   └── DeviceRow (repeated)
│       ├── Mic icon
│       ├── Device name
│       ├── Connection badge
│       ├── RSSI badge
│       └── Battery indicator
└── FileSyncCard
    ├── Sync button
    ├── Progress bar
    └── Status text
```

**Benefits:**
- Each component has single responsibility
- Easy to test in isolation
- Reusable across views
- Clear data flow

---

## Pattern: Environment & State Management

### Before (Local State Only)

```swift
struct DeviceSettingsView: View {
    @State private var showingError = false
    @State private var errorMessage = ""
}
```

### After (Environment + Local State)

```swift
struct DeviceSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let scanner = BluetoothDeviceScanner()
    private let connectionManager: DeviceConnectionManager
    private let fileSyncService: DeviceFileSyncService
}
```

**Benefits:**
- `@Environment` provides system-level data (color scheme)
- `@State` for local UI state (alerts, toggles)
- Plain properties for service references
- Clear separation of concerns

---

## Pattern: Button States

### Before (Simple Text Button)

```swift
Button("Scan") {
    scanner.scanForDevices(timeout: 10.0)
}
```

### After (Contextual Button with States)

```swift
struct ScanButton: View {
    let scanner: BluetoothDeviceScanner
    
    var body: some View {
        Button {
            scanner.scanForDevices(timeout: 10.0)
        } label: {
            if scanner.isScanning {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.scribeRed)
                    Text("Scanning")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.scribeRed)
                }
            } else {
                Text("Scan")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.scribeRed)
            }
        }
        .disabled(scanner.isScanning)
    }
}
```

**Benefits:**
- Visual feedback for scanning state
- Consistent branding
- Better UX

---

## Pattern: RSSI Signal Visualization

### Before (Simple Color)

```swift
private var rssiColor: Color {
    if rssi > -50 { return .green }
    else if rssi > -60 { return .yellow }
    else { return .red }
}
```

### After (Rich RSSI Badge)

```swift
struct RSSIBadge: View {
    let rssi: Int
    
    private var signalIcon: String {
        if rssi > -50 { return "wifi" }
        if rssi > -65 { return "wifi.exclamationmark" }
        return "wifi.slash"
    }
    
    private var signalColor: Color {
        if rssi > -50 { return .green }
        if rssi > -65 { return .yellow }
        return Theme.scribeRed
    }
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: signalIcon)
                .font(.caption2)
            Text("\(rssi) dBm")
                .font(.caption)
        }
        .foregroundStyle(signalColor)
    }
}
```

**Benefits:**
- Visual icon + numeric value
- Clear signal strength indication
- Consistent with iOS design language

---

## Key Takeaways

1. **@Observable classes don't need @State** - Use plain properties
2. **Inject dependencies explicitly** - Clear service composition flow
3. **Use card-based architecture** - Reusable, consistent components
4. **Integrate theme system** - Use `Theme.scribeRed`, `Theme.obsidian`
5. **Separate concerns** - Root view, card components, helper views
6. **Provide visual feedback** - Loading states, error states, success states
7. **Follow iOS design patterns** - Use standard icons, badges, progress views

---

*This document captures UI implementation patterns from DeviceSettingsView refactoring.*
