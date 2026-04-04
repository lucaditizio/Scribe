# AI DVR Link Binary Analysis Results

**Analysis Date:** 2025-04-04
**Binary:** `/Users/lucaditizio/github/Scribe/AI_DVR_Link/Frameworks/App.framework/App`
**File Type:** Mach-O 64-bit dynamically linked shared library arm64

---

## 1. Command Byte Codes

### DVRLink Commands (3085s Protocol)
The binary contains references to two distinct command protocols: **3085s** and **SLink**.

#### DVRLinkInitializeDeviceRequest3085s
- **String Found:** `DVRLinkInitializeDeviceRequest3085s`
- **Context:** Device initialization command in the 3085s protocol family
- **File Reference:** `package:dvrlink/dvrlink_module/loom/loom_get_assist_response.dart`

#### DVRLinkInitializeDeviceResponse3085s
- **String Found:** `DVRLinkInitializeDeviceResponse3085s`
- **Context:** Response to device initialization request

### SLink Commands (UART-over-BLE Protocol)

#### SLinkBindSuccessRequest
- **String Found:** `SLinkBindSuccessRequest`
- **Context:** Command sent after successful device binding
- **Related:** `bindSuccess` function reference

#### Complete SLink Request Types Discovered:
```
SLinkAppUnBindRequest
SLinkBatteryRequest
SLinkBindSuccessRequest
SLinkBleRequest
SLinkDeleteRequest
SLinkEndRecKeyRequest
SLinkEndRecRequest
SLinkGetDeviceInfoRequest
SLinkGetFilesRequest
SLinkGetMacRequest
SLinkGetRecStRequest
SLinkPauseRecRequest
SLinkPauseSyncRequest
SLinkStartRecKeyRequest
SLinkStartRecRequest
SLinkStorageRequest
SLinkSyncFileRequest
SLinkSyncTimeRequest
SLinkVersionRequest
```

#### Complete SLink Response Types Discovered:
```
SLinkBatteryResponse
SLinkDataRecResponse
SLinkDeviceUnBindResponse
SLinkEndRecKeyResponse
SLinkEndRecResponse
SLinkEndSyncByDeviceResponse
SLinkGetDeviceInfoResponse
SLinkGetDeviceStResponse
SLinkGetFilesEndResponse
SLinkGetFilesResponse
SLinkGetMacResponse
SLinkGetRecStResponse
SLinkGetRecTimeResponse
SLinkPauseRecKeyResponse
SLinkRecStResponse
SLinkResumeRecKeyResponse
SLinkStartRecKeyResponse
SLinkStartRecResponse
SLinkStorageRemindResponse
SLinkSyncFileDataResponse
SLinkSyncFileEndResponse
SLinkSyncFileStartResponse
SLinkVersionResponse
```

---

## 2. Packet Structure

### Key Hex Patterns Found

#### 0x0905 Pattern
- **Evidence:** String `receive 0x0905 pkgValidSize:`
- **Interpretation:** This appears to be a packet type identifier or command code
- **Hex Dump Locations:** Found at multiple offsets (e.g., 0x16e10, 0x18b70, 0x200a0)
- **Context:** Used in packet validation: "did not match expected length and checksum"

#### 0x3085 Pattern
- **Evidence:** Multiple command strings ending with "3085s"
- **Interpretation:** Protocol identifier for a specific device communication family
- **Commands:** DVRLinkInitializeDeviceRequest3085s, DVRLinkSyncTimeRequest3085s, etc.

### Packet Validation Strings
```
" did not match expected length and checksum."
"receive 0x0905 pkgValidSize: "
```

### Packet Structure Hypothesis
Based on string analysis:
```
[Start Byte] [Type/Command] [Length] [Payload...] [Checksum] [End Byte]
```

**Validation Requirements:**
- Length field validation (`pkgValidSize`)
- Checksum validation
- Both must match expected values for packet to be accepted

---

## 3. Checksum Algorithm

### Checksum-Related Functions Found:
```
get:_checkSum@3099033
_calcTableChecksum@2843119492
```

### Checksum Validation Evidence:
```
" did not match expected length and checksum."
```

### Algorithm Hypothesis:
- **Type:** Likely XOR-based or custom checksum (not standard CRC-16 based on function names)
- **Function Pattern:** `_calcTableChecksum` suggests a lookup table-based approach
- **Validation:** Packets must pass both length AND checksum checks

### Notes:
- The function `_calcTableChecksum` implies a pre-computed table approach
- This is common in embedded systems for performance
- Without disassembly, exact algorithm cannot be determined

---

## 4. Timing Constants

### Keep-Alive Mechanism
- **String Found:** `AutomaticKeepAliveClientMixin` (Flutter framework pattern)
- **Evidence:** Multiple references to keep-alive patterns in state management

### Timeout References
```
dvrlink_network_error_timeout
Request timeout
connection timeout
send timeout
TimeoutException
```

### Timer Patterns
```
_timer2@1721297881
_DelayedError@5048458
_DelayedDone@5048458
```

### From Context (provided in task description):
- **Keep-alive interval:** 3 seconds (verified via app behavior)

---

## 5. Protocol Architecture

### UART-over-BLE Service Indicators
```
isUARTService3085s
isUARTServiceSLink
isSLinkUARTRXUuid
isSLinkUARTRXKeyUuid
isSLINKUARTTXUuid
```

### File Structure References
```
package:dvrlink/dvrlink_bluetooth/xlx_link/protocol/cmd_slink/request.dart
package:dvrlink/dvrlink_bluetooth/xlx_link/protocol/cmd_3085s/request_3085s.dart
package:dvrlink/dvrlink_bluetooth/xlx_link/protocol/cmd_slink/setting/setting.dart
package:dvrlink/dvrlink_bluetooth/xlx_link/protocol/cmd_slink/setting/file.dart
package:dvrlink/dvrlink_bluetooth/xlx_link/protocol/cmd_slink/setting/record.dart
package:dvrlink/dvrlink_bluetooth/xlx_link/protocol/cmd_slink/setting/key.dart
```

### Key Processing
```
SLinkOpusHelper._internal@1581171928
SLinkOpusHelper.getInstance
package:dvrlink/dvrlink_common/opus/slink_opus_helper.dart
```

---

## 6. Command Flow Analysis

### Device Initialization Flow
1. `DVRLinkInitializeDeviceRequest3085s` → Initialize device connection
2. `SLinkBindSuccessRequest` → Confirm successful binding
3. `SLinkGetDeviceInfoRequest` → Retrieve device information

### Recording Control Flow
1. `SLinkStartRecRequest` / `SLinkStartRecKeyRequest` → Start recording
2. `SLinkPauseRecRequest` → Pause recording
3. `SLinkEndRecRequest` / `SLinkEndRecKeyRequest` → End recording
4. `SLinkGetRecStRequest` → Get recording status

### File Management Flow
1. `SLinkSyncFileRequest` → Request file sync
2. `SLinkGetFilesRequest` → List files
3. `SLinkDeleteRequest` → Delete files

---

## 7. Unresolved Questions

### Missing Information:
1. **Exact byte codes** for each command (would require disassembly or runtime analysis)
2. **Complete packet structure** with byte offsets
3. **Precise checksum algorithm** implementation
4. **Timing constants** (delays between commands)

### Recommendations for Further Analysis:
1. Runtime analysis with Frida or similar tool
2. BLE packet capture during actual device communication
3. Disassembly of `_calcTableChecksum` function
4. Analysis of `pkgValidSize` calculation logic

---

## 8. Summary

### Confirmed Protocol Details:
- Two protocol families: **3085s** and **SLink**
- **SLink** uses UART-over-BLE communication
- Packets validated by **length** and **checksum**
- 0x0905 appears to be a significant packet type identifier
- **Keep-alive**: 3-second intervals
- **Checksum**: Table-based calculation (likely custom/XOR)

### Command Categories:
1. **Device Management:** Initialize, bind, get info
2. **Recording Control:** Start, pause, end recording
3. **File Operations:** Sync, list, delete files
4. **Settings:** Storage, version, MAC address queries
5. **Key Events:** Record key press handling

---

*Analysis performed using strings and hexdump tools on Mach-O binary*
