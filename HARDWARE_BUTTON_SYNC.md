# Hardware Button Sync - Implementation Notes

## Problem
The hardware record button on the BLE microphone doesn't trigger recording in the app, and vice versa.

## Root Cause
The SLink protocol implementation currently only supports:
- Device initialization/handshake (commands 0x0202, 0x0203, 0x0201, 0x0204, 0x0205, 0x0218, 0x020A, 0x0217)
- Audio streaming (F0F3 characteristic)
- Status polling (0x0205)

**Missing:** Button state notifications from device to app

## Required Implementation

### 1. Protocol Discovery
Need to capture packets when physical button is pressed on microphone:
- Use PacketLogger on macOS
- Look for notifications on F0F2 (command characteristic)
- Check for new command codes (likely 0x02XX range)

### 2. Expected Implementation
```swift
// In DeviceConnectionManager or BleAudioRecorder
// Listen for button press notifications

private func handleButtonNotification(_ data: Data) {
    // Parse button state from SLink packet
    // Trigger recording start/stop in BleAudioRecorder
}
```

### 3. Bidirectional Sync
- Device → App: Button press notification
- App → Device: Recording state confirmation (optional)

## Next Steps
1. Capture packets with DVR app while pressing hardware button
2. Identify command code for button events
3. Add notification handler in DeviceConnectionManager
4. Wire to BleAudioRecorder toggleRecording()

## Complexity: HIGH
Requires reverse engineering the proprietary protocol.
