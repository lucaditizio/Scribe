# Bluetooth Microphone Connection Binding Fix

## TL;DR

> **Quick Summary**: Fix the missing SLink protocol handshake that prevents the Bluetooth microphone from maintaining connection. The device connects successfully but disconnects immediately because binding commands are never sent.
>
> **Deliverables**:
> - Complete SLink protocol documentation from DVR app analysis
> - Working device binding (connection stays alive for 5+ minutes)
> - Audio stream ready for Opus decoding (E49A3003 subscribed)
>
> **Estimated Effort**: Medium
> **Parallel Execution**: NO - Sequential phases (Research → Implementation → Hardening)
> **Critical Path**: Protocol Documentation → Bind Handshake → Audio Subscription → Connection Stability

---

## Context

### Original Request
Reverse engineer how the original iOS/macOS DVR applications connect to the Bluetooth microphone and keep that connection up. Focus only on this task using Bluetooth monitoring approaches available without Apple Developer subscription.

### Interview Summary

**Key Discussions**:
- **Problem**: Scribe app connects to LA518/LA519 Bluetooth mic, but connection drops immediately
- **Root Cause**: Missing proprietary SLink UART-over-BLE protocol handshake
- **Approach**: Critical path only (init commands, binding, audio subscription)
- **Tools Available**: macOS Console.app, Bluetooth Explorer, LightBlue/nRF Connect, BLE packet capture hardware
- **Source Access**: AI DVR Link app binary available for analysis, can capture DVR app logs

**Research Findings**:
- **Binary Analysis**: Discovered SLink command protocol (`DVRLinkInitializeDeviceRequest`, `SLinkBindSuccessRequest`, etc.)
- **Log Analysis**: bluetoothd logs show successful connection but no SLink command exchange
- **Code Review**: Found audio characteristic E49A3003 is NEVER subscribed (critical bug)
- **Protocol Discovery**: Packet validation uses 0x0905, length+checksum, keep-alive is 3 seconds

### Metis Review

**Identified Gaps** (addressed in plan):
- Audio characteristic E49A3003 subscription is CRITICAL missing piece
- Keep-alive starts too late (after first notification, but device disconnects before that)
- No response parsing for SLink commands - authentication ignores device response
- Missing connection parameter negotiation (interval, latency, timeout)
- MTU negotiation needed (iOS caps at 185 bytes)

---

## Work Objectives

### Core Objective
Establish stable Bluetooth connection to LA518/LA519 microphone by implementing the required SLink protocol handshake, enabling persistent binding and audio streaming.

### Concrete Deliverables
- `.sisyphus/evidence/slink-protocol-documentation.md` - Complete SLink command reference
- `.sisyphus/evidence/dvr-log-capture.txt` - Full DVR app bluetoothd logs
- Modified `DeviceConnectionManager.swift` - SLink protocol implementation
- Modified `AudioStreamReceiver.swift` - E49A3003 subscription
- Working connection test (5+ minute sustained connection)

### Definition of Done
- [ ] DVR app logs captured showing complete initialization sequence
- [ ] SLink command format documented (byte structure, timing)
- [ ] Device binds successfully and stays connected for 5+ minutes
- [ ] Audio packets arrive on E49A3003 subscription
- [ ] Connection recovers from temporary disconnections

### Must Have
- SLink bind handshake implemented
- Audio characteristic subscribed
- Device stays connected during idle periods

### Must NOT Have (Guardrails)
- **NO audio decoding** - Opus decoder is separate work
- **NO file transfer** - File sync is separate work
- **NO UI changes** - Only protocol layer changes
- **NO app store submission** - Development/ testing only

---

## Verification Strategy (MANDATORY)

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: NO dedicated test infrastructure in this project
- **Automated tests**: NO existing Bluetooth tests
- **Framework**: Manual verification + Agent-executed QA scenarios
- **Verification**: Agent uses bluetoothd logs, Console.app, and BLE packet capture

### QA Policy
Every task includes agent-executed QA scenarios:
- **Bluetooth Verification**: Use macOS Console.app with bluetoothd filter
- **Packet Capture**: BLE hardware + Wireshark for packet analysis
- **Connection Test**: Agent monitors connection duration with timeout
- **Evidence Capture**: Screenshots and log files saved to `.sisyphus/evidence/`

---

## Execution Strategy

### Phase Dependency Graph

```
Phase 1 (Research) → Phase 2 (Implementation) → Phase 3 (Hardening)

Phase 1: Protocol Documentation [Sequential]
├── Task 1.1: Capture DVR bluetoothd logs [user action]
├── Task 1.2: BLE packet capture [user action]
└── Task 1.3: Document SLink protocol [deep]

Phase 2: Critical Fixes [Sequential]
├── Task 2.1: Add DVRLinkInitializeDeviceRequest [deep]
├── Task 2.2: Implement SLinkBindSuccessRequest [deep]
├── Task 2.3: Subscribe to E49A3003 [quick]
├── Task 2.4: Implement UART RX monitoring [deep]
└── Task 2.5: Fix keep-alive timing [quick]

Phase 3: Connection Stability [Sequential]
├── Task 3.1: Add connection parameter negotiation [deep]
├── Task 3.2: Add MTU negotiation [quick]
└── Task 3.3: Add reconnection logic [deep]
```

### Critical Path
Task 1.1 → Task 1.2 → Task 1.3 → Task 2.1 → Task 2.2 → Task 2.3 → Task 2.4 → Task 2.5 → Task 3.1 → Task 3.2 → Task 3.3 → F1-F4

---

## TODOs

### Phase 1: Protocol Documentation (Research)

- [ ] 1. Capture Complete DVR App bluetoothd Logs

  **What to do**:
  - Close all apps on test device
  - Run the native DVR app (AI DVR Link or LA518 companion app)
  - Capture complete bluetoothd logs from device connection through audio streaming start
  - Save logs to `.sisyphus/evidence/dvr-app-bluetoothd.log`  - Extract timestamps for each initialization command

  **Must NOT do**:
  - Do NOT modify any Scribe code during this task
  - Do NOT skip this step - DVR logs are critical reference

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: This is a user action - just needs documentation of capture process
  - **Skills**: []
  - **Skills Evaluated but Omitted**: All - simple documentation task

  **Parallelization**:
  - **Can Run In Parallel**: NO - Must complete before Task 1.2
  - **Parallel Group**: Phase 1 (Sequential)
  - **Blocks**: Task 1.2, 1.3
  - **Blocked By**: None (can start immediately)

  **References**:
  - **Existing Code**: `bluetoothd_log_DVR.md` - Example log format (truncated)
  - **Existing Code**: `bluetoothd_log_Scribe.md` - Scribe connection logs for comparison
  - **External**: macOS Console.app - Filter for "bluetoothd" process

  **WHY Each Reference Matters**:
  - `bluetoothd_log_DVR.md` shows partial connection - need complete sequence
  - `bluetoothd_log_Scribe.md` shows successful connection but missing init commands

  **Acceptance Criteria**:
  - [ ] Log file captured showing complete device connection
  - [ ] Log includes device initialization sequence (E49A3003, F0F1 commands)
  - [ ] Log shows heartbeat/keep-alive packets
  - [ ] Timestamps extracted for each command phase

  **QA Scenarios**:
  ```
  Scenario: Log capture completeness  - Tool: Bash (cat, wc -l)    Preconditions: DVR app installed and working
    Steps:
      1. wc -l .sisyphus/evidence/dvr-app-bluetoothd.log
      2. grep -c "E49A" .sisyphus/evidence/dvr-app-bluetoothd.log
      3. grep -c "F0F" .sisyphus/evidence/dvr-app-bluetoothd.log    Expected Result: Log has > 500 lines, contains multiple E49A and F0F entries
    Failure Indicators: Log < 200 lines, missing E49A/F0F references    Evidence: .sisyphus/evidence/task-1-log-capture-evidence.txt
  ```

  **Evidence to Capture**:
  - [ ] Log file named: task-1-dvr-bluetoothd.log
  - [ ] Command timestamps saved to: task-1-command-timestamps.md

  **Commit**: NO (research only)

- [ ] 2. BLE Packet Capture for Command Format

  **What to do**:
  - Use BLE hardware analyzer (Wireshark with compatible adapter or nRF Sniffer)
  - Capture raw BLE packets during DVR app connection
  - Extract SLink packet structure: start byte, command type, sequence number, length, payload, checksum, end byte
  - Document checksum algorithm (likely XOR or CRC-16)  - Save packet captures to `.sisyphus/evidence/ble-packet-capture.pcap`

  **Must NOT do**:
  - Do NOT use simulated data - must capture real packets
  - Do NOT skip checksum verification - critical for packet validation

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Requires BLE protocol expertise and thorough packet analysis
  - **Skills**: []
  - **Skills Evaluated but Omitted**: All - specialized BLE knowledge needed

  **Parallelization**:
  - **Can Run In Parallel**: NO - Requires Task 1.1 logs for timing context
  - **Parallel Group**: Phase 1 (Sequential)
  - **Blocks**: Task 1.3
  - **Blocked By**: Task 1.1

  **References**:
  - **Existing Code**: `bluetoothd_log_Scribe.md:163-175` - Shows device discovery with packet data
  - **External**: Wireshark BLE dissector - For packet analysis
  - **External**: nRF Sniffer documentation - For Nordic devices

  **WHY Each Reference Matters**:
  - bluetoothd logs show raw packet data format in hex
  - Wireshark can decode BLE L2CAP/ATT layers

  **Acceptance Criteria**:
  - [ ] PCAP file captured with device initialization sequence
  - [ ] SLink packet structure documented (start byte, type, seq, length, payload, checksum, end byte)
  - [ ] Checksum algorithm identified (XOR, CRC-16, or custom)
  - [ ] Command byte codes documented (0x0905 validation referenced)

  **QA Scenarios**:
  ```
  Scenario: Packet capture validation
    Tool: Bash (tshark)
    Preconditions: Wireshark installed, BLE capture hardware connected
    Steps:
      1. tshark -r .sisyphus/evidence/ble-packet-capture.pcap -Y "btatt" -V | head -100
      2. Count E49A UUID in ATT packets
      3. Verify packet direction (request/response pairs)
    Expected Result: ATT packets contain E49A UUID, request/response pattern visible
    Failure Indicators: No E49A UUID, missing response packets
    Evidence: .sisyphus/evidence/task-2-packet-validation.txt
  ```

  **Evidence to Capture**:
  - [ ] PCAP file named: task-2-ble-packets.pcap
  - [ ] Protocol documentation: task-2-slink-protocol.md

  **Commit**: NO (research only)

- [ ] 3. Document SLink Protocol Reference

  **What to do**:
  - Create comprehensive protocol documentation from Tasks 1.1 and 1.2
  - Document each SLink command: request format, expected response, timing
  - Document initialization sequence with state machine diagram
  - Document keep-alive heartbeat format and interval
  - Save to `.sisyphus/evidence/slink-protocol-reference.md`

  **Must NOT do**:
  - Do NOT implement yet - this is documentation only
  - Do NOT speculat e on unknown commands - label as "TBD"

  **Recommended Agent Profile**:
  - **Category**: `writing`
    - Reason: Documentation task, no code changes
  - **Skills**: []
  - **Skills Evaluated but Omitted**: All - documentation work

  **Parallelization**:
  - **Can Run In Parallel**: NO - Requires Task 1.2 packet analysis
  - **Parallel Group**: Phase 1 (Sequential)
  - **Blocks**: Phase 2 tasks
  - **Blocked By**: Task 1.1, Task 1.2

  **References**:
  - **Pattern Reference**: Binary analysis findings (see draft):
    ```
    SLink Commands Discovered:
    - DVRLinkInitializeDeviceRequest3085s
    - SLinkBindSuccessRequest
    - SLinkGetDeviceInfoRequest/Response  
    - SLinkBatteryRequest/Response
    - SLinkStartRecKeyRequest/Response
    - Packet: 0x0905 validation, length+checksum
    ```
  - **Pattern Reference**: `DeviceConnectionManager.swift:380-411` - Current auth sequence
  - **External**: Silicon Labs UART-over-BLE app notes

  **WHY Each Reference Matters**:
  - Binary analysis shows command class names
  - Current code shows what's implemented vs what's missing

  **Acceptance Criteria**:
  - [ ] Protocol reference document created
  - [ ] All discovered commands documented (request/response format)
  - [ ] Initialization sequence documentedwith state diagram
  - [ ] Keep-alive format documented
  - [ ] Checksum algorithm documented

  **QA Scenarios**:
  ```
  Scenario: Protocol documentation completeness
    Tool: Read
    Preconditions: Tasks 1.1 and 1.2 complete
    Steps:
      1. Read .sisyphus/evidence/slink-protocol-reference.md
      2. Verify "DVRLinkInitializeDeviceRequest" is documented
      3.  Verify "SLinkBindSuccessRequest" is documented
      4. Verify checksum algorithm is documented      5. Verify initialization sequence is documented
    Expected Result: All sections present, no TBD in critical commands
    Failure Indicators: Missing key commands, missing checksum algorithm
    Evidence: .sisyphus/evidence/task-3-protocol-doc-check.txt
  ```

  **Evidence to Capture**:
  - [ ] Protocol document: task-3-slink-protocol-reference.md

  **Commit**: NO (documentation only)

### Phase 2: Critical Fixes (Implementation)

- [ ]4. Add DVRLinkInitializeDeviceRequest Command

  **What to do**:
  - Add new `SLinkProtocol.swift` file to define SLink command types
  - Implement `DVRLinkInitializeDeviceRequest` command struct with packet format from Phase 1
  - Add `sendInitializationCommand()` method to `DeviceConnectionManager.swift`
  - Call initialization after authentication write (line 405 in current code)
  - Parse device response and validate (currently missing!)
  - Add timeout handling for initialization response

  **Must NOT do**:
  - Do NOT send initialization before authentication
  - Do NOT skip response parsing (current bug: auth ignores response)

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Requires understanding SLink protocol and implementing response parsing
  - **Skills**: []
  - **Skills Evaluated but Omitted**: All - Swift/CoreBluetooth knowledge

  **Parallelization**:
  - **Can Run In Parallel**: NO - Depends on Phase 1 documentation
  - **Parallel Group**: Phase 2 (Sequential)
  - **Blocks**: Task 5 (BindSuccess requires init first)
  - **Blocked By**: Task 3 (Protocol documentation)

  **References**:
  - **Pattern Reference**: `DeviceConnectionManager.swift:380-411` - Authentication sequence (auth then init)
  - **Pattern Reference**: `DeviceConnectionManager.swift:506-527` - Current notification handling (missing response parsing)
  - **External**: BLE UART app notes for response parsing patterns

  **WHY Each Reference Matters**:
  - Authentication shows write pattern but ignores response - must fix this
  - Notification handling shows where to add response parsing

  **Acceptance Criteria**:
  - [ ] `SLinkProtocol.swift` created with command type definitions
  - [ ] `sendInitializationCommand()` implemented after auth
  - [ ] Response parsing implemented with validation
  - [ ] Timeout handling added (5 second default)
  - [ ] Logs show initialization command sent and response received

  **QA Scenarios**:
  ```
  Scenario: Initialization command sent
    Tool: Bash (log stream)
    Preconditions: Device connected, authentication complete
    Steps:
      1. Start log stream: log stream --predicate 'process == "bluetoothd"'
      2. Run Scribe app with initialization
      3. Filter for initialization command in logs
    Expected Result: Logs show "Initialization command sent" and "Initialization response received"
    Failure Indicators: No response received within 5 seconds
    Evidence: .sisyphus/evidence/task-4-init-command-log.txt

  Scenario: Response validation
    Tool: Bash (grep logs)
    Preconditions: Device connected, init command sent
    Steps:
      1. grep "Initialization" .sisyphus/evidence/task-4-init-command-log.txt
      2. Verify response contains expected byte pattern
    Expected Result: Response has correct packet format (start byte, type, checksum valid)
    Failure Indicators: Checksum mismatch, timeout, no response
    Evidence: .sisyphus/evidence/task-4-response-validation.txt
  ```

  **Evidence to Capture**:
  - [ ] Log file: task-4-initialization-log.txt
  - [ ] Code diff: task-4-slink-protocol.diff

  **Commit**: YES
  - Message: `feat(bluetooth): add SLink protocol with initialization command`
  - Files: `Scribe/Scribe/Sources/Bluetooth/SLinkProtocol.swift` (new), `DeviceConnectionManager.swift` (modified)

- [ ] 5. Implement SLinkBindSuccessRequest Handshake

  **What to do**:
  - Add`SLinkBindSuccessRequest` command to protocol
  - Implement bind handshake sequence:
    1. After init response received, send `SLinkBindSuccessRequest`
    2. Wait for `SLinkBindSuccessResponse` from device
    3. If success, connection is now "bound" and will stay alive
  - Add `connectionState` enum: `.disconnected`, `.connected`, `.bound`
  - Update UI observers for bind state changes
  - On bind failure, retry 3 times with 1 second delay

  **Must NOT do**:
  - Do NOT proceed to audio streaming without successful bind
  - Do NOT skip bind response validation

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Critical handshake logic with retry handling
  - **Skills**: []
  - **Skills Evaluated but Omitted**: All - Swift state machine

  **Parallelization**:
  - **Can Run In Parallel**: NO - Depends on Task 4 initialization
  - **Parallel Group**: Phase 2 (Sequential)
  - **Blocks**: Task 6 (Audio subscription requires bind)
  - **Blocked By**: Task 4

  **References**:
  - **Pattern Reference**: `DeviceConnectionManager.swift:68-78` - Current connection state enum
  - **Pattern Reference**: `DeviceConnectionManager.swift:136-144` - Reconnection logic (can reuse pattern)
  - **Binary Finding**: SLinkBindSuccessRequest sends after init, expects bind-success response

  **WHY Each Reference Matters**:
  - Connection state needs new `.bound` state
  - Reconnection pattern can be reused for bind retry

  **Acceptance Criteria**:
  - [ ] `SLinkBindSuccessRequest` command implemented
  - [ ] Bind response parsing with validation
  - [ ] `ConnectionState` enum has `.bound` case
  - [ ] Retry logic: 3 attempts with 1s delay
  - [ ] logs show "Bind request sent" and "Bound successfully" or "Bind failed"

  **QA Scenarios**:
  ```
  Scenario: Successful bind handshake
    Tool: Bash (log stream)
    Preconditions: Device connected, initialization complete
    Steps:
      1. Start Scribe app
      2. Monitor logs for bind sequence
      3. Verify "Bind request sent" → "Bound successfully"
    Expected Result: Connection state changes to `.bound`
    Failure Indicators: "Bind failed" after 3 retries
    Evidence: .sisyphus/evidence/task-5-bind-success-log.txt

  Scenario: Bind retry on failure
    Tool: Bash (grep)
    Preconditions: Simulated bind failure (optional)
    Steps:
      1. grep "Bind retry" .sisyphus/evidence/task-5-bind-success-log.txt
      2. Count retry attempts
    Expected Result: Exactly 3 retry attempts before failure
    Failure Indicators: No retry, or infinite retry
    Evidence: .sisyphus/evidence/task-5-bind-retry.txt
  ```

  **Evidence to Capture**:
  - [ ] Log file: task-5-bind-handshake.txt
  - [ ] State machine diagram: task-5-connection-state.png

  **Commit**: YES
  - Message: `feat(bluetooth): implement bind handshake with retry logic`
  - Files: `DeviceConnectionManager.swift`

- [ ] 6. Subscribe to Audio Characteristic E49A3003

  **What to do**:
  - **CRITICAL**: This is the PRIMARY fix - E49A3003 is currently NEVER subscribed
  - Add `audioStreamCharacteristic` property to `DeviceConnectionManager.swift`
  - In `peripheral(_:didDiscoverCharacteristicsFor:)` line 310, add:
    ```swift    if uuid.uuidString.contains("E49A3003") {
        self.audioStreamCharacteristic = characteristic
        print("[DeviceConnectionManager] Audio stream char found - SUBSCRIBING")
        peripheral.setNotifyValue(true, for: characteristic)
    }
    ```
  - Move `startKeepAlive()` to after bind success (currently starts too early at line 522)
  - Add error handling for subscription failure

  **Must NOT do**:
  - Do NOT only subscribe to F0F2/F0F3/F0F4 (current bug)
  - Do NOT start keep-alive before bind success

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple subscription addition, well-defined change
  - **Skills**: []
  - **Skills Evaluated but Omitted**: All - straightforward CoreBluetooth

  **Parallelization**:
  - **Can Run In Parallel**: NO - Depends on Task 5 bind success
  - **Parallel Group**: Phase 2 (Sequential)
  - **Blocks**: Task 7 (UART RX needs audio characteristic)
  - **Blocked By**: Task 5

  **References**:
  - **CRITICAL**: `DeviceConnectionManager.swift:333-377` - `subscribeToFileTransferChars()` ONLY subscribes F0F2/F0F3/F0F4 - MISSING E49A3003!
  - **Pattern Reference**: `DeviceConnectionManager.swift:356-374` - Subscription pattern to follow
  - **Pattern Reference**: `AudioStreamReceiver.swift:83-86` - Current subscription call (calls subscribeToAudioNotifications but characteristic never set)

  **WHY Each Reference Matters**:
  - This is the ROOT CAUSE - audio characteristic never subscribed
  - Shows exact line where fix must be added

  **Acceptance Criteria**:
  - [ ] `audioStreamCharacteristic` propertyadded
  - [ ] E49A3003 subscribed in characteristic discovery
  - [ ] `startKeepAlive()` moved to after bind success
  - [ ] Error handling for subscription failure
  - [ ] logs show "Audio stream char found - SUBSCRIBING"

  **QA Scenarios**:
  ```
  Scenario: Audio characteristic subscription
    Tool: Bash (log stream)
    Preconditions: Device connected, bind successful
    Steps:
      1. Start Scribe app
      2. Monitor logs for "Audio stream char found - SUBSCRIBING"
      3. Verify "Notifications enabled for E49A3003"
    Expected Result: E49A3003 subscription appears in logs
    Failure Indicators: No E49A3003 subscription, only F0F subscriptions
    Evidence: .sisyphus/evidence/task-6-audio-subscription.txt

  Scenario: Keep-alive timing
    Tool: Bash (grep)
    Preconditions: Bind successful
    Steps:
      1. grep "starting keep-alive" .sisyphus/evidence/task-6-audio-subscription.txt
      2. Verify keep-alive starts AFTER "Bound successfully" not before
    Expected Result: Keep-alive log appears after bind success log
    Failure Indicators: Keep-alive starts before bind
    Evidence: .sisyphus/evidence/task-6-keepalive-timing.txt
  ```

  **Evidence to Capture**:
  - [ ] Log file: task-6-subscription-evidence.txt
  - [ ] GATT service map showing E49A3003

  **Commit**: YES
  - Message: `fix(bluetooth): subscribe to audio characteristic E49A3003`
  - Files: `DeviceConnectionManager.swift`

- [ ] 7. Implement UART RX Response Monitoring

  **What to do**:
  - Add `SLinkResponseParser.swift` to parse incoming UART packets
  - Implement packet framing validation:
    - Start byte check
    - Length validation
    - Checksum verification (algorithm from Phase 1)
    - End byte check
  - Add response queue to match requests with responses
  - Handle async responses (device may send unsolicited packets)
  - Add delegate callback for parsed responses to `DeviceConnectionManager`

  **Must NOT do**:
  - Do NOT assume all responses arrive in order
  - Do NOT ignore checksum failures

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Protocol parsing with checksum validation, complex logic
  - **Skills**: []
  - **Skills Evaluated but Omitted**: All - requires protocol knowledge

  **Parallelization**:
  - **Can Run In Parallel**: NO - Depends on Task 6
  - **Parallel Group**: Phase 2 (Sequential)
  - **Blocks**: Task 8 (Keep-alive needs response handling)
  - **Blocked By**: Task 6

  **References**:
  - **Pattern Reference**: `DeviceConnectionManager.swift:506-533` - Current `didUpdateValueFor` implementation (lacks packet parsing)
  - **Binary Finding**: Packet format is 0x0905 validation with length+checksum
  - **External**: UART framing patterns (start byte, type, seq, length, payload, checksum, end byte)

  **WHY Each Reference Matters**:
  - Current notification handler writes data to log but doesn't parse
  - Must add proper packet parsing here

  **Acceptance Criteria**:
  - [ ] `SLinkResponseParser.swift` created
  - [ ] Packet framing validation (start/end bytes, length, checksum)
  - [ ] Response queue to match requests
  - [ ] Async response handling
  - [ ] Delegate callback for parsed responses
  - [ ] logs show "[SLinkParser] Received packet type=0xXX, length=YY, checksum=VALID"

  **QA Scenarios**:
  ```
  Scenario: Packet parsing validation
    Tool: Bash (log stream)
    Preconditions: Device connected, audio subscribed
    Steps:
      1. Start Scribe app
      2. Monitor for "[SLinkParser]" log entries
      3. Verify packets are parsed (not just raw hex)
    Expected Result: Parsed packet logs with type, length, checksum validation
    Failure Indicators: Raw hex only, no parsed output, checksum errors
    Evidence: .sisyphus/evidence/task-7-packet-parsing.txt

  Scenario: Checksum validation
    Tool: Bash (grep)
    Preconditions: Device sending packets
    Steps:
      1. grep "checksum" .sisyphus/evidence/task-7-packet-parsing.txt
      2. Count VALID vs INVALID checksums
    Expected Result: All checksums VALID
    Failure Indicators: Any INVALID checksum
    Evidence: .sisyphus/evidence/task-7-checksum-validation.txt
  ```

  **Evidence to Capture**:
  - [ ] Parser code: task-7-slink-response-parser.swift
  - [ ] Packet parsing logs

  **Commit**: YES
  - Message: `feat(bluetooth): add SLink UART response parser with checksum validation`
  - Files: `SLinkResponseParser.swift` (new), `DeviceConnectionManager.swift`

- [ ] 8. Fix Keep-Alive Timing

  **What to do**:
  - Move `startKeepAlive()` call from line 522 to after bind success
  - Capture exact keep-alive interval from DVR logs (expected 3 seconds based on binary analysis)
  - Implement proper keep-alive command using SLink protocol from Phase 1
  - Add keep-alive response handling
  - Track last keep-alive response timestamp
  - If no response for 3 keep-alives, mark connection as unstable

  **Must NOT do**:
  - Do NOT start keep-alive before bind success (current bug)
  - Do NOT send heartbeat without response validation

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Timing fix and using protocol from Phase 1, straightforward
  - **Skills**: []
  - **Skills Evaluated but Omitted**: All - simple timer and command send

  **Parallelization**:
  - **Can Run In Parallel**: NO - Depends on Task 7
  - **Parallel Group**: Phase 2 (Sequential)
  - **Blocks**: Phase 3 tasks
  - **Blocked By**: Task 7

  **References**:
  - **CRITICAL**: `DeviceConnectionManager.swift:522` - Keep-alive currently starts FIRST notification (TOO EARLY!)
  - **Pattern Reference**: `DeviceConnectionManager.swift:462-473` - Current `startKeepAlive()` implementation
  - **Binary Finding**: Keep-alive interval is 3 seconds

  **WHY Each Reference Matters**:
  - Shows current broken timing
  - Shows keep-alive implementation to fix

  **Acceptance Criteria**:
  - [ ] `startKeepAlive()` moved to after bind success
  - [ ] Keep-alive interval matches DVR app (3 seconds)
  - [ ] Keep-alive uses SLink protocol command
  - [ ] Response handling tracks last response time
  - [ ] Connection marked unstable after 3 missed keep-alives
  - [ ] Logs show keep-alive sent and response received

  **QA Scenarios**:
  ```
  Scenario: Keep-alive timing correctness
    Tool: Bash (grep)
    Preconditions: Device bound successfully
    Steps:
      1. grep "Keep-alive" .sisyphus/evidence/task-8-keepalive.txt
      2. Verify timestamps: sent at T, response at T+100ms max
      3. Verify interval: next sent at T+3000ms
    Expected Result: Keep-alive sent every 3 seconds, response within 100ms
    Failure Indicators: Keep-alive sent before "Bound successfully", no response
    Evidence: .sisyphus/evidence/task-8-keepalive-timing.txt

  Scenario: Connection stability detection
    Tool: Bash (grep)
    Preconditions: Simulate missed keep-alives (optional)
    Steps:
      1. grep "unstable" .sisyphus/evidence/task-8-keepalive.txt
      2. Verify unstable detection after 3 misses
    Expected Result: Connection marked unstable after 3 missed keep-alives
    Failure Indicators: No unstable detection, or false positive
    Evidence: .sisyphus/evidence/task-8-stability-detection.txt
  ```

  **Evidence to Capture**:
  - [ ] Keep-alive timing logs
  - [ ] Connection state transitions

  **Commit**: YES
  - Message: `fix(bluetooth): correct keep-alive timing and add stability detection`
  - Files: `DeviceConnectionManager.swift`

### Phase 3: Connection Stability (Hardening)

- [ ] 9. Add Connection Parameter Negotiation

  **What to do**:
  - Add `negotiateConnectionParameters()` method to `DeviceConnectionManager`
  - Request preferred parameters:
    - Interval: 15-20ms (iOS minimum is 15ms)
    - Latency: 0 (no skipping for voice)
    - Timeout: 5000ms (supervision timeout)
  - Use CoreBluetooth API: `peripheral.requestConnectionParameterUpdate()` (if available) or negotiate via MTU exchange timing
  - Validate parameters after connection with `peripheral.readValue(for: connectionParameterCharacteristic)`
  - Log accepted parameters

  **Must NOT do**:
  - Do NOT request parameters iOS doesn't allow (< 15ms interval)
  - Do NOT block connection on negotiation failure

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: BLE protocol parameters, iOS constraints
  - **Skills**: []
  - **Skills Evaluated but Omitted**: All - CoreBluetooth knowledge

  **Parallelization**:
  - **Can Run In Parallel**: NO - Depends on Phase 2
  - **Parallel Group**: Phase 3 (Sequential)
  - **Blocks**: Task 10
  - **Blocked By**: Task 8

  **References**:
  - **External**: Apple Accessory Design Guidelines - Section 49.6 (connection parameters)
  - **External**: BLE formula: timeout > (1 + latency) × interval × 2
  - **Log Reference**: bluetoothd_log_Scribe.md:174 - Current params: "interval: 30 ms, latency: 0, lsto: 72"

  **WHY Each Reference Matters**:
  - Shows current parameters (30ms interval, 0 latency, 720ms timeout)
  - iOS minimums constrain negotiation

  **Acceptance Criteria**:
  - [ ] Connection parameter negotiation implemented
  - [ ] Parameters logged afterconnection
  - [ ] Parameters match or exceed minimums: interval ≤ 20ms, timeout ≥ 500ms
  - [ ] Negotiation doesn't block connection (fallback to defaults on failure)

  **QA Scenarios**:
  ```
  Scenario: Parameter negotiation
    Tool: Bash (log stream)
    Preconditions: Device connected, bind successful
    Steps:
      1. Start Scribe app
      2. Monitor logs for "Connection parameters"
      3. Verify interval ≤ 20ms, timeout ≥ 500ms
    Expected Result: Negotiated parameters logged, within acceptable range
    Failure Indicators: Negotiation fails, or parameters out of range
    Evidence: .sisyphus/evidence/task-9-connection-params.txt
  ```

  **Evidence to Capture**:
  - [ ] Connection parameter logs

  **Commit**: YES
  - Message: `feat(bluetooth): add connection parameter negotiation`
  - Files: `DeviceConnectionManager.swift`

- [ ] 10. Add MTU Negotiation

  **What to do**:
  - Add MTU negotiation after connection
  - iOS caps MTU at 185 bytes for BLE
  - Device requests 247, iOS returns 527 (from logs) - use max available
  - Call `peripheral.maximumWriteValueLength(for: .withoutResponse)` to get actual MTU
  - Store MTU for packet fragmentation calculations
  - Log negotiated MTU value

  **Must NOT do**:
  - Do NOT assume device can handle iOS's 527 MTU
  - Do NOT send packets larger than device's supported MTU

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple MTU query, CoreBluetooth API
  - **Skills**: []
  - **Skills Evaluated but Omitted**: All - straightforward

  **Parallelization**:
  - **Can Run In Parallel**: NO - Depends on Task 9
  - **Parallel Group**: Phase 3 (Sequential)
  - **Blocks**: Task 11
  - **Blocked By**: Task 9

  **References**:
  - **Log Reference**: bluetoothd_log_Scribe.md:268-269 - "MTU 527 (calculated 1251): for rx 251 bytes, tx 251 bytes"
  - **Log Reference**: bluetoothd_log_Scribe.md:242 - "Peer asked for MTU:247 while link is not ready"
  - **External**: iOS BLE MTU limits - max 185 for writes, max 527 for reads

  **WHY Each Reference Matters**:
  - Shows actual MTU negotiation from logs (527)
  - Shows device's MTU request (247)

  **Acceptance Criteria**:
  - [ ] MTU negotiation implemented
  - [ ] `maximumWriteValueLength` queried and stored
  - [ ] MTU value logged
  - [ ] MTU used for packet fragmentation (if needed)

  **QA Scenarios**:
  ```
  Scenario: MTU negotiation
    Tool: Bash (log stream)
    Preconditions: Device connected
    Steps:
      1. Start Scribe app
      2. Monitor logs for "MTU"
      3. Verify MTU is logged and is ≥ 185
    Expected Result: MT U logged, value is max available
    Failure Indicators: No MTU log, or MTU < 185
    Evidence: .sisyphus/evidence/task-10-mtu-negotiation.txt
  ```

  **Evidence to Capture**:
  - [ ] MTU negotiation logs

  **Commit**: YES
  - Message: `feat(bluetooth): add MTU negotiation`
  - Files: `DeviceConnectionManager.swift`

- [ ] 11. Add Reconnection Logic with Exponential Backoff

  **What to do**:
  - Implement reconnection on unexpected disconnect
  - Use exponential backoff: 1s, 2s, 4s, 8s, 16s (max 30s)
  - Store device UUID in `UserDefaults` for quick reconnect
  - On reconnect, re-run full initialization sequence:
    1. Authentication
    2. Initialization command
    3. Bind handshake
    4. Audio subscription
    5. Start keep-alive
  - Track reconnection attempts and success rate
  - Add user notification for prolonged disconnect (>3 attempts)

  **Must NOT do**:
  - Do NOT reconnect infinitely - cap at 5 attempts
  - Do NOT skip initialization on reconnect

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: State machine logic, error handling, exponential backoff
  - **Skills**: []
  - **Skills Evaluated but Omitted**: All - CoreBluetooth and state management

  **Parallelization**:
  - **Can Run In Parallel**: NO - Depends on Task 10
  - **Parallel Group**: Phase 3 (Sequential)
  - **Blocks**: Final verification
  - **Blocked By**: Task 10

  **References**:
  - **Pattern Reference**: `DeviceConnectionManager.swift:136-144` - Existing reconnect skeleton (needs enhancement)
  - **Pattern Reference**: `DeviceConnectionManager.swift:68-78` - ConnectionState enum (needs `.reconnecting`)
  - **External**: BLE reconnection best practices - exponential backoff pattern

  **WHY Each Reference Matters**:
  - Shows existing reconnect logic to enhance
  - Shows state enum to extend

  **Acceptance Criteria**:
  - [ ] Exponential backoff reconnection implemented
  - [ ] Full initialization sequence on reconnect
  - [ ] Reconnection capped at 5 attempts
  - [ ] Device UUID persisted for quick reconnect
  - [ ] User notification for prolonged disconnect

  **QA Scenarios**:
  ```
  Scenario: Reconnection after disconnect
    Tool: Bash (log stream)
    Preconditions: Device connected and bound
    Steps:
      1. Power cycle device (simulated disconnect)
      2. Monitor reconnection logs
      3. Verify exponential backoff: 1s, 2s, 4s delays between attempts
      4. Verify full init sequence runs on reconnect
    Expected Result: Reconnect succeeds within 5 attempts, init sequence runs
    Failure Indicators: Infinite reconnection, skipped init
    Evidence: .sisyphus/evidence/task-11-reconnection.txt

  Scenario: Reconnection failure handling
    Tool: Bash (grep)
    Preconditions: Device unavailable
    Steps:
      1. grep "Reconnection attempt" .sisyphus/evidence/task-11-reconnection.txt
      2. Verify exactly 5 attempts
      3. Verify user notification triggered
    Expected Result: 5 attempts, then failure notification
    Failure Indicators: Infinite attempts, no notification
    Evidence: .sisyphus/evidence/task-11-reconnection-failure.txt
  ```

  **Evidence to Capture**:
  - [ ] Reconnection logs
  - [ ] State transition diagram

  **Commit**: YES
  - Message: `feat(bluetooth): add reconnection with exponential backoff`
  - Files: `DeviceConnectionManager.swift`

---

## Final Verification Wave (MANDATORY)

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.

- [ ] F1. **Plan Compliance Audit** — `oracle`

  Read the plan end-to-end. For each "Must Have": verify implementation exists. For each "Must NOT Have": search codebase for forbidden patterns. Check evidence files exist. Compare deliverables against plan.

  **What to verify**:
  - SLink protocol documentation exists (`.sisyphus/evidence/slink-protocol-reference.md`)
  - Audio characteristic E49A3003 subscription exists in `DeviceConnectionManager.swift`
  - Bind handshake implemented (`SLinkBindSuccessRequest` and response handling)
  - No Opus decoder changes (Must NOT Have)
  - No file transfer implementation (Must NOT Have)
  - No UI changes beyond DeviceSettingsView (Must NOT Have)
  - Evidence files for each task exist in `.sisyphus/evidence/`

  **Output**: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`

  Run `swift build` (or Xcode build). Run `swiftlint` if available. Review all changed files for: `as any`, `@ts-ignore` (if Swift), empty catches, `print` statements in prod code (use logging instead), commented-out code, unused imports.

  **What to check**:
  - Build succeeds with no errors
  - No SwiftLint warnings (or documented exceptions)
  - No force unwrapping without guard
  - Proper error handling (no empty `catch` blocks)
  - Logging uses proper log levels (not just `print`)
  - All new types are documented with `///` comments

  **Output**: `Build [PASS/FAIL] | Lint [N issues] | Code Quality [N issues] | VERDICT`

- [ ] F3. **Real Manual QA** — `unspecified-high`

  **CRITICAL: This task requires actual device testing with LA518/LA519 microphone.**

  Start from clean state. Execute EVERY QA scenario from EVERY task:
  - Task 1-3: Verify logs exist and contain expected content
  - Task 4: Verify initialization command sent and response received
  - Task 5: Verify bind handshake succeeds
  - Task 6: Verify E49A3003 subscription
  - Task 7: Verify packet parsing logs appear
  - Task 8: Verify keep-alive timing (3-second intervals)
  - Task 9: Verify connection parameters negotiated
  - Task 10: Verify MTU negotiated
  - Task 11: Verify reconnection works after disconnect

  **Test cross-task integration**:
  - Connection stays alive for 5+ minutes during idle
  - Audio packets arrive on E49A3003
  - Device reconnects after power cycle
  - Multiple connect/disconnect cycles work

  **Test edge cases**:
  - Connection timeout during bind
  - Packet checksum failure
  - Keep-alive response timeout
  - Rapid connect/disconnect cycles

  Save evidence to `.sisyphus/evidence/final-qa/`.

  **Output**: `Scenarios [N/N pass] | Integration [N/N] | Edge Cases [N tested] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`

  For each task: read "What to do", review actual git diff. Verify 1:1 — everything in spec was built, nothing beyond spec was built. Check "Must NOT do" compliance. Detect cross-task contamination.

  **What to verify**:
  - Task 4: Only init command added, no file transfer code
  - Task 5: Only bind handshake, no audio processing
  - Task 6: Only E49A3003 subscription, no new UI
  - Task 7: Only packet parsing, no audio decoding
  - Task 8: Only keep-alive timing, no new features
  - Task 9-11: Only connection stability, no app logic

  **Check for unaccounted changes**:
  - Files changed that aren't in task specs
  - New dependencies added
  - Build settings modified

  **Output**: `Tasks [N/N compliant] | Contamination [CLEAN/N issues] | Unaccounted [N files] | VERDICT`

---

## Commit Strategy

- **Phase 1**: No code changes (research only)
- **Phase 2**: `feat(bluetooth): add SLink protocol handshake for device binding`
- **Phase 3**: `fix(bluetooth): improve connection stability with parameter negotiation`

---

## Success Criteria

### Verification Commands
```bash
# Check connection stays alive for 5 minutes
log stream --predicate 'subsystem == "com.apple.bluetooth"' --timeout 300

# Verify E49A3003 subscription in logs
log show --predicate 'process == "bluetoothd" AND message CONTAINS "E49A3003"' --last 5m

# Check SLink commands in logs
log show --predicate 'message CONTAINS "SLink" OR message CONTAINS "BindSuccess"' --last 5m
```

### Final Checklist
- [ ] All "Must Have" requirements present
- [ ] All "Must NOT Have" requirements absent
- [ ] Connection maintained for 5+ minutes during idle
- [ ] Audio packets received on E49A3003
- [ ] Device reconnects after temporary disconnection