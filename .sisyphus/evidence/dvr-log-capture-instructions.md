# Capturing DVR App Bluetoothd Logs with macOS Console.app

This guide walks you through capturing the complete bluetoothd logs from the AI DVR Link app to analyze the SLink protocol initialization sequence.

## Prerequisites

- macOS 10.15 (Catalina) or later
- AI DVR Link app installed
- LA518/LA519 Bluetooth microphone

---

## Method 1: Using Console.app (GUI)

### Step 1: Open Console.app

1. Press `Cmd + Space` to open Spotlight
2. Type "Console" and press Enter
3. The Console app will open showing system logs

### Step 2: Set Up the Filter

1. In the top-right search bar, type: `bluetoothd`
2. Click the filter dropdown that appears
3. Select "Process" from the dropdown menu
4. The filter should now show: `process == "bluetoothd"`
5. Press Enter to apply the filter

### Step 3: Clear Previous Logs

1. Click the "Clear" button (trash can icon) in the toolbar
2. This ensures you only capture logs from your test session

### Step 4: Start Capture

1. Keep Console.app open and visible
2. Ensure the bluetoothd filter is active
3. Make sure your Mac's Bluetooth is enabled

### Step 5: Connect the Device

1. Open the AI DVR Link app on your iOS device
2. Power on your LA518/LA519 microphone
3. In the app, tap to connect to the microphone
4. Wait for the connection to establish

### Step 6: Start Audio Streaming

1. In the AI DVR Link app, start a recording or audio stream
2. Let it run for at least 10-15 seconds to capture keep-alive packets

### Step 7: Stop Capture

1. Return to Console.app
2. Click the "Pause" button to stop new log entries

### Step 8: Export the Logs

1. Select all relevant log entries (Cmd+A to select all)
2. Right-click and choose "Export Selected..."
3. Save the file as `dvr-app-bluetoothd.log`
4. Move the file to `.sisyphus/evidence/dvr-app-bluetoothd.log`

---

## Method 2: Using Terminal (log command)

### Step 1: Open Terminal

1. Press `Cmd + Space` to open Spotlight
2. Type "Terminal" and press Enter

### Step 2: Start Log Streaming

Run this command before connecting the device:

```bash
log stream --process bluetoothd --predicate 'process == "bluetoothd"' > ~/Desktop/dvr-bluetoothd-stream.log
```

### Step 3: Connect and Stream

1. Open AI DVR Link app
2. Connect to your microphone
3. Start audio streaming
4. Let it run for 10-15 seconds

### Step 4: Stop Capture

Press `Ctrl + C` in the Terminal window to stop the log stream.

### Step 5: Move the Log File

```bash
mv ~/Desktop/dvr-bluetoothd-stream.log .sisyphus/evidence/dvr-app-bluetoothd.log
```

---

## Method 3: Capturing Historical Logs

If you already connected the device and need to retrieve past logs:

```bash
# Get logs from the last 10 minutes
log show --process bluetoothd --last 10m > .sisyphus/evidence/dvr-app-bluetoothd.log
```

Or for a specific time range:

```bash
log show --process bluetoothd --start '2025-04-04 10:00:00' --end '2025-04-04 10:30:00' > .sisyphus/evidence/dvr-app-bluetoothd.log
```

---

## What to Look For in the Logs

### 1. Device Connection

Look for entries containing:
- `connecting to device`
- `connected to device`
- Device address/identifier

Example pattern:
```
bluetoothd: connecting to device <address>
bluetoothd: connected to device <address>
```

### 2. Service Discovery

Search for these service UUIDs:
- `E49A3001` - Main service
- `F0F0` - Secondary service

Look for:
- `discovering services`
- `service discovered`
- `UUID = E49A3001`
- `UUID = F0F0`

### 3. Initialization Commands

Key indicators:
- `DVRLinkInitializeDeviceRequest`
- `SLinkBindSuccessRequest`
- Any hex data starting with `0x` sent to characteristics

Look for write operations to characteristics with these patterns.

### 4. Audio Subscription

Critical characteristic:
- `E49A3003` - Audio data characteristic

Look for:
- `subscribing to characteristic`
- `setNotifyValue` for E49A3003
- `E49A3003` with `notify: true`

### 5. Keep-Alive Packets

Signs of keep-alive:
- Regular 3-second interval packets
- Small data writes (typically 4-8 bytes)
- Sent to control characteristic (often E49A3002)
- Look for timestamps showing ~3 second gaps

---

## Verifying Complete Capture

Your log should contain ALL of these in sequence:

1. [ ] Device connection event
2. [ ] Service discovery (E49A3001, F0F0)
3. [ ] Characteristic discovery
4. [ ] DVRLinkInitializeDeviceRequest sent
5. [ ] SLinkBindSuccessRequest sent
6. [ ] Subscription to E49A3003 (notify enabled)
7. [ ] First audio data indication from E49A3003
8. [ ] Keep-alive packets at 3-second intervals

---

## Troubleshooting

### No Logs Appearing

- Ensure filter is set to `process == "bluetoothd"`
- Check that the filter is applied (not just typed)
- Try removing and re-adding the filter
- Restart Console.app

### Logs Stop After Connection

- Some apps suppress logs during active streaming
- Try the Terminal method with `sudo`:
  ```bash
  sudo log stream --process bluetoothd
  ```

### Too Many Logs

- Use a more specific predicate:
  ```bash
  log stream --predicate 'process == "bluetoothd" AND (eventMessage CONTAINS "E49A" OR eventMessage CONTAINS "write")'
  ```

### Missing Initialization Commands

- Ensure you start capture BEFORE opening the app
- The initialization happens immediately after connection
- Watch for "Data Out" or "Write Request" entries

---

## Quick Reference: Filter Predicates

| What You Want | Predicate |
|---------------|-----------|
| All bluetoothd logs | `process == "bluetoothd"` |
| Specific UUID | `process == "bluetoothd" AND eventMessage CONTAINS "E49A3001"` |
| Write operations | `process == "bluetoothd" AND eventMessage CONTAINS "write"` |
| Connection events | `process == "bluetoothd" AND (eventMessage CONTAINS "connect" OR eventMessage CONTAINS "disconnect")` |

---

## Next Steps

After capturing the logs:

1. Open the log file in a text editor
2. Search for "E49A3003" to find audio subscription
3. Look backward from there to find initialization commands
4. Document any hex data patterns you see
5. Compare with Scribe app logs to identify missing commands

---

## Log File Location

Save all captures to:
```
.sisyphus/evidence/dvr-app-bluetoothd.log
```

This ensures logs are tracked with the project evidence.
