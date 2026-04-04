import SwiftUI

// MARK: - DeviceSettingsView
//
// Root view for external Bluetooth microphone management.
// Allows the user to scan, connect, and sync flash-drive recordings
// from the AI DVR microphone.
//
// FIX: @Observable classes must NOT be wrapped in @State when owned by a View.
// @State is for value types (structs). Using @State on an @Observable class
// causes "self used before stored properties are initialised" because the
// init chain tries to reference self.scanner before all @State wrappers settle.
// Solution: store as plain `let` / `var` properties — @Observable's macro
// generates all necessary willSet/didSet observation hooks automatically.

struct DeviceSettingsView: View {
    @Environment(\.colorScheme) var colorScheme

    // Services — plain stored properties, not @State.
    // @Observable handles change propagation automatically.
    // IMPORTANT: all three services must share the SAME scanner instance.
    // scanner is declared without a default value so init() can assign it
    // alongside connectionManager — guaranteeing one shared peripheral map.
    private let scanner: BluetoothDeviceScanner
    private let connectionManager: DeviceConnectionManager
    private let fileSyncService: DeviceFileSyncService

    @State private var showingError = false
    @State private var errorMessage = ""

    init() {
        let scanner = BluetoothDeviceScanner()
        let mgr = DeviceConnectionManager(scanner: scanner)
        self.scanner = scanner              // ← same instance the manager holds
        self.connectionManager = mgr
        self.fileSyncService = DeviceFileSyncService(connectionManager: mgr)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── 1. Connection Status Card ─────────────────────────────
                ConnectionStatusCard(connectionManager: connectionManager)
                    .scribeCardStyle(scheme: colorScheme)

                // ── 2. Device List Card ───────────────────────────────────
                DeviceListCard(
                    scanner: scanner,
                    connectionManager: connectionManager,
                    onDeviceSelected: { connectionManager.connect(to: $0) }
                )
                .scribeCardStyle(scheme: colorScheme)

                // ── 3. File Sync Card ─────────────────────────────────────
                FileSyncCard(fileSyncService: fileSyncService) {
                    do {
                        try fileSyncService.syncRecordings()
                    } catch {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
                .scribeCardStyle(scheme: colorScheme)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Theme.obsidian.ignoresSafeArea())
        .navigationTitle("External Mic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ScanButton(scanner: scanner)
            }
        }
        .alert("Sync Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Scan Button

private struct ScanButton: View {
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

// MARK: - Connection Status Card

private struct ConnectionStatusCard: View {
    let connectionManager: DeviceConnectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            Label("Connection", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                // Status indicator dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.6), radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let device = connectionManager.connectedDevice {
                        HStack(spacing: 6) {
                            Text(device.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            RSSIBadge(rssi: device.rssi)
                        }
                    }
                }

                Spacer()

                if connectionManager.connectionState == .connected {
                    Button("Disconnect") {
                        connectionManager.disconnect()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.scribeRed)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.scribeRed.opacity(0.12))
                    .clipShape(Capsule())
                } else if case .connecting = connectionManager.connectionState {
                    ProgressView()
                        .tint(Theme.scribeRed)
                }
            }
        }
    }

    private var statusTitle: String {
        switch connectionManager.connectionState {
        case .disconnected:           return "Not Connected"
        case .connecting:             return "Connecting…"
        case .connected:              return "Connected"
        case .binding:                return "Binding…"
        case .initializing:           return "Initializing…"
        case .initialized:            return "Initialized"
        case .bound:                  return "Bound"
        case .failed(let msg):        return "Error: \(msg)"
        case .reconnecting(let n):    return "Reconnecting (\(n)/5)…"
        }
    }

    private var statusColor: Color {
        switch connectionManager.connectionState {
        case .connected,
             .initialized,
             .bound:         return .green
        case .connecting,
             .binding,
             .initializing,
             .reconnecting:  return .yellow
        case .failed:        return Theme.scribeRed
        case .disconnected:  return Color.secondary
        }
    }
}

// MARK: - Device List Card

private struct DeviceListCard: View {
    let scanner: BluetoothDeviceScanner
    let connectionManager: DeviceConnectionManager
    let onDeviceSelected: (BluetoothDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Available Devices", systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if scanner.isScanning {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(Theme.scribeRed)
                    Text("Scanning for AI DVR microphones…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if scanner.devices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "mic.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No devices found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Tap Scan to discover nearby microphones")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(scanner.devices) { device in
                        DeviceRow(
                            device: device,
                            isConnected: connectionManager.connectedDevice?.id == device.id,
                            onSelect: { onDeviceSelected(device) }
                        )
                    }
                }
            }

            // Footer
            Text("Supported: LA518, LA519, L027, L813–L817, MAR-2518")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let device: BluetoothDevice
    let isConnected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Mic icon with connection tint
                Image(systemName: isConnected ? "mic.fill" : "mic")
                    .font(.title3)
                    .foregroundStyle(isConnected ? Theme.scribeRed : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        if isConnected {
                            Text("Connected")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.scribeRed.opacity(0.15))
                                .foregroundStyle(Theme.scribeRed)
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        RSSIBadge(rssi: device.rssi)

                        if let battery = device.batteryLevel {
                            Label("\(battery)%", systemImage: "battery.50")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isConnected
                          ? Theme.scribeRed.opacity(0.07)
                          : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File Sync Card

private struct FileSyncCard: View {
    let fileSyncService: DeviceFileSyncService
    let onSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("File Transfer", systemImage: "arrow.down.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Sync button
            Button(action: onSync) {
                HStack(spacing: 10) {
                    Image(systemName: fileSyncService.isTransferring
                          ? "arrow.triangle.2.circlepath"
                          : "arrow.down.to.line")
                        .font(.title3)
                        .foregroundStyle(fileSyncService.isTransferring ? .secondary : Theme.scribeRed)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileSyncService.isTransferring
                             ? syncStatusText
                             : "Sync Recordings")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if !fileSyncService.isTransferring, !fileSyncService.files.isEmpty {
                            Text("\(fileSyncService.files.count) file(s) available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if fileSyncService.isTransferring {
                        ProgressView(value: fileSyncService.transferProgress)
                            .progressViewStyle(.circular)
                            .tint(Theme.scribeRed)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(fileSyncService.isTransferring)

            // Progress bar shown during transfer
            if fileSyncService.isTransferring {
                ProgressView(value: fileSyncService.transferProgress)
                    .progressViewStyle(.linear)
                    .tint(Theme.scribeRed)
                    .animation(.easeInOut, value: fileSyncService.transferProgress)
            }

            Text("Downloads recordings stored on the microphone's flash drive")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    private var syncStatusText: String {
        switch fileSyncService.state {
        case .enumerating:          return "Reading device files…"
        case .transferring(let f):  return f
        case .completed:            return "Sync Complete"
        case .failed(let e):        return "Error: \(e)"
        default:                    return "Syncing…"
        }
    }
}

// MARK: - RSSI Signal Badge

private struct RSSIBadge: View {
    let rssi: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: signalIcon)
                .font(.caption2)
            Text("\(rssi) dBm")
                .font(.caption)
        }
        .foregroundStyle(signalColor)
    }

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
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeviceSettingsView()
    }
    .preferredColorScheme(.dark)
}
