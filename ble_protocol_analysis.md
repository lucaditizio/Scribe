# AI DVR Link — BLE Connection Protocol Analysis

## Context

This document describes the BLE protocol used by the LA518/LA519 AI DVR microphone, reverse-engineered from the `AI_DVR_Link/Runner` and `AI_DVR_Link/Frameworks/App.framework/App` binaries.

---

## The Connection Failure Explained

The "Connection cannot be established" message occurs **after** the CoreBluetooth `didConnect` callback fires, during GATT service/characteristic discovery. The device connects at the radio level (the OS handshake works), but then the app must complete a **proprietary application-layer handshake** over BLE characteristics before the device accepts any commands.

Our current `DeviceConnectionManager` discovers services and characteristics generically, then immediately tries to subscribe to the first notifiable characteristic — without sending the required auth handshake. The device ignores or drops the subscription.

---

## Extracted GATT UUIDs

Five proprietary service/characteristic UUIDs are hardcoded in the App.framework binary:

| UUID | Role |
|------|------|
| `0011200a-2233-4455-6677-889912345678` | **Primary Service** — device control & status |
| `0011201a-2233-4455-6677-889912345678` | **Auth / Handshake Characteristic** — write auth JSON here first |
| `0011202a-2233-4455-6677-889912345678` | **Command Characteristic** — send device commands (record, stop, file list) |
| `0011203a-2233-4455-6677-889912345678` | **Audio Stream Characteristic** — subscribe (notify) for live Opus audio frames |
| `0011204a-2233-4455-6677-889912345678` | **File Transfer Characteristic** — subscribe (notify) for file sync data |
| `00002902-0000-1000-8000-00805f9b34fb` | Standard GATT Client Characteristic Configuration Descriptor (CCCD) |

Two additional UUIDs appear likely related to a secondary service (possibly WiFi/file transfer):

| UUID | Likely Role |
|------|-------------|
| `e49a25e0-f69a-11e8-8eb2-f2801f1b9fd1` | Secondary service or WiFi characteristic |
| `e49a25f8-f69a-11e8-8eb2-f2801f1b9fd1` | Write characteristic in secondary service |
| `e49a28e1-f69a-11e8-8eb2-f2801f1b9fd1` | Notify characteristic in secondary service |

---

## The Auth Handshake

The binary contains a JSON template with two fields that must be written to the **Auth Characteristic** (`0011201a-...`) immediately after service discovery:

```json
{"auth_tm":"<timestamp>","encrypt_data":"<encrypted_payload>"}
```

- `auth_tm` — a Unix timestamp string (current time in seconds as a string)
- `encrypt_data` — AES-encrypted payload (the binary references `aes_use_key_bias` and an AES key derivation path)

> [!IMPORTANT]
> The AES key is embedded in the binary (not passed at runtime from a server). The `ascDecoderInit` / `initDecoder5` Obj-C methods in `AIDvrLinkRecordASCDecoder` contain the key derivation. Until the exact key bytes are extracted via a debugger (e.g. LLDB attached to the original app), we cannot reproduce the encrypted payload from first principles.

**Pragmatic workaround available:** Many consumer BLE devices that use a timestamp-based auth accept a **fixed or zeroed `encrypt_data`** when running on the same platform as the original app (iOS), because the device trusts platform CBCentralManager pairing. Try the handshake with `encrypt_data` set to an empty string or a fixed 16-byte zero block first — if the device accepts it, you don't need to reverse the AES key.

```swift
// Attempt 1: empty encrypt_data (many devices accept this)
let authPayload = """
{"auth_tm":"\(Int(Date().timeIntervalSince1970))","encrypt_data":""}
"""

// Attempt 2: zeros (16-byte AES block, base64-encoded)
let authPayload = """
{"auth_tm":"\(Int(Date().timeIntervalSince1970))","encrypt_data":"AAAAAAAAAAAAAAAAAAAAAA=="}
"""
```

---

## The Audio Codec: ASC, Not Raw Opus

**Critical finding:** The binary contains:
- `AIDvrLinkRecordASCDecoder` — a proprietary **ASC (Adaptive Sub-band Coding)** decoder
- `ASC_KBPS_Type5` — a bitrate mode constant
- `shortstreamlen5` / `initDecoder5` — init methods specific to ASC type 5
- `DualOpusHelper`, `BufferedOpusDecoder` — standard Opus wrappers

The device sends audio over BLE as **ASC-encoded frames, not raw Opus**. ASC is a proprietary codec developed by iFLYTEK (the `iflyse.bundle` and `iflyse.framework` in the app confirm this — iFLYTEK makes the embedded ASR engine). The `AIDvrLinkRecordASCDecoder` class is the decoder for this format.

The standard `OpusFlutterIosPlugin` is used for **cloud transcription** after decoding, not for the BLE audio stream itself.

**Consequence:** Our `OpusAudioDecoder` stub will not decode audio correctly — the incoming BLE frames must first be decoded via ASC before being fed into the pipeline.

**Pragmatic path forward:** The ASC codec is likely also present as a static library symbol within the Runner binary. However, since the `iflyse.framework` is present in the bundle:

```
AI_DVR_Link/Frameworks/iflyse.framework  ← contains ASC decoder
```

It may be usable as a linked dependency, but it requires an iFLYTEK appkey (seen in the binary as `appkey=...`). Without this key, instantiating the ASC decoder fails at init-time.

**Alternative:** Record raw BLE bytes to a file during a live session with the original app and reverse-engineer the frame format empirically.

---

## The Correct Connection Sequence

Based on the analysis, the correct sequence is:

```
1. CBCentralManager connects to peripheral
2. Peripheral fires didConnect
3. Discover services → filter for 0011200a-2233-4455-6677-889912345678
4. Discover characteristics for that service
5. Write auth JSON to 0011201a-... (withResponse)
6. Wait for didWriteValueFor callback (success = device accepted auth)
7. Subscribe (setNotifyValue: true) to 0011203a-... (audio stream)
8. Subscribe (setNotifyValue: true) to 0011204a-... (file transfer)
9. Write command to 0011202a-... to start streaming or request file list
10. Receive Opus/ASC frames on 0011203a-...
```

---

## Code Changes Required in `DeviceConnectionManager.swift`

### Step 1: Add the known UUIDs as constants

```swift
// MARK: - Known AI DVR Link GATT UUIDs
// Extracted from AI_DVR_Link/Frameworks/App.framework/App binary

enum DVRLinkUUID {
    static let primaryService     = CBUUID(string: "0011200a-2233-4455-6677-889912345678")
    static let authCharacteristic = CBUUID(string: "0011201a-2233-4455-6677-889912345678")
    static let commandCharacteristic = CBUUID(string: "0011202a-2233-4455-6677-889912345678")
    static let audioStreamCharacteristic = CBUUID(string: "0011203a-2233-4455-6677-889912345678")
    static let fileTransferCharacteristic = CBUUID(string: "0011204a-2233-4455-6677-889912345678")
}
```

### Step 2: Discover only the known service (faster + correct)

```swift
// In discoverServices():
peripheral?.discoverServices([DVRLinkUUID.primaryService])
```

### Step 3: Pin characteristics by UUID instead of by property

```swift
// In didDiscoverCharacteristicsFor:
for characteristic in service.characteristics ?? [] {
    switch characteristic.uuid {
    case DVRLinkUUID.authCharacteristic:
        authCharacteristic = characteristic
    case DVRLinkUUID.commandCharacteristic:
        audioDataCharacteristic = characteristic
    case DVRLinkUUID.audioStreamCharacteristic:
        audioNotificationCharacteristic = characteristic
    case DVRLinkUUID.fileTransferCharacteristic:
        fileTransferCharacteristic = characteristic
    default:
        break
    }
}
// Auth handshake fires after ALL characteristics are pinned
if authCharacteristic != nil {
    sendAuthHandshake()
}
```

### Step 4: Implement the auth handshake

```swift
private func sendAuthHandshake() {
    guard let peripheral, let authChar = authCharacteristic else { return }
    
    let timestamp = Int(Date().timeIntervalSince1970)
    // Attempt with empty encrypt_data first — update if device rejects
    let json = "{\"auth_tm\":\"\(timestamp)\",\"encrypt_data\":\"\"}"
    
    guard let data = json.data(using: .utf8) else { return }
    peripheral.writeValue(data, for: authChar, type: .withResponse)
    print("[DeviceConnectionManager] Auth handshake sent (auth_tm=\(timestamp))")
}

// In didWriteValueFor:
public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    if characteristic.uuid == DVRLinkUUID.authCharacteristic {
        if let error {
            print("[DeviceConnectionManager] Auth handshake failed: \(error)")
            DispatchQueue.main.async { self.connectionState = .failed("Auth failed: \(error.localizedDescription)") }
            return
        }
        print("[DeviceConnectionManager] Auth handshake accepted — subscribing to audio stream")
        subscribeToAudioAndFileTransfer()
    }
}

private func subscribeToAudioAndFileTransfer() {
    guard let peripheral else { return }
    if let audioChar = audioNotificationCharacteristic {
        peripheral.setNotifyValue(true, for: audioChar)
    }
    if let fileChar = fileTransferCharacteristic {
        peripheral.setNotifyValue(true, for: fileChar)
    }
}
```

---

## Checklist for the Smaller Model

- [ ] Add `DVRLinkUUID` enum with the 5 hardcoded UUIDs
- [ ] Change `discoverServices(nil)` → `discoverServices([DVRLinkUUID.primaryService])`
- [ ] Add `authCharacteristic` and `fileTransferCharacteristic` stored properties
- [ ] Replace "first notifiable" characteristic pinning with UUID-based switch
- [ ] Add `sendAuthHandshake()` called from `didDiscoverCharacteristicsFor`
- [ ] Add `didWriteValueFor` delegate method to respond to auth success/failure
- [ ] Subscribe to audio + file transfer only after auth is confirmed
- [ ] Update `AudioStreamReceiver` to know the audio frames are ASC-encoded, not Opus

> [!NOTE]
> Test with `encrypt_data: ""` first. If the device returns an error on `didWriteValueFor`, try `"encrypt_data":"AAAAAAAAAAAAAAAAAAAAAA=="` (16 null bytes, base64). If both fail, the full AES key needs to be extracted from the binary via LLDB.
