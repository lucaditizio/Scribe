# SLink Protocol Implementation Decisions

## Architecture Decisions

### Why Separate Enums for Commands and Responses
- Commands and responses have different byte code ranges
- Commands are sent by app, responses received from device
- Some commands have no expected response (fire-and-forget)
- Responses can be unsolicited (device-initiated)

### Why UInt16 for Command Codes
- Binary analysis showed 0x0905 pattern (2-byte values)
- Allows for 65,536 unique commands
- Easy to distinguish request (0x0000-0x7FFF) from response (0x8000-0xFFFF)
- Matches common embedded protocol patterns

### Why Table-Based Checksum
- Binary analysis found `_calcTableChecksum@2843119492`
- Table-based algorithms are common in embedded systems for speed
- XOR-based checksums are simple and fast
- Lookup table approach reduces computation per byte

### Why Streaming Parser
- BLE characteristics deliver data in chunks
- UART-over-BLE may split packets across notifications
- Buffer-based approach handles partial packets
- Can parse multiple packets from single buffer

## Byte Code Assignment Rationale

### Categories
- 0x0000: System/Binding
- 0x1000: Device Information
- 0x2000: Recording Control
- 0x3000: File Operations
- 0x4000: Time/Settings
- 0x9000+: Responses (0x8000 bit set)

### Special Values
- 0x3085: Initialize device (matches "3085s" protocol family)
- 0x0905: Packet validation type (from binary string analysis)
- 0xAA: Start byte (common UART idle pattern)
- 0x55: End byte (complement of start)

## Packet Structure Decisions

### Header Fields
1. Start byte (1): Frame synchronization
2. Command type (2): Big-endian UInt16
3. Sequence number (2): For request/response matching
4. Length (1): Payload only, excludes header/checksum/end

### Why Big-Endian
- Network byte order standard
- Matches binary analysis patterns
- Common in embedded protocols

### Why 8-bit Length Field
- BLE MTU typically 185-527 bytes
- 255 bytes max payload fits within single byte
- Simplifies packet parsing

### Why Sequence Number
- Allows matching responses to requests
- Detects missing/out-of-order packets
- Can be used for duplicate detection

## Error Handling Strategy

### SLinkError Types
- InvalidPacketStructure: Parser couldn't parse
- ChecksumMismatch: Data corruption detected
- Timeout: No response within expected time
- UnexpectedResponse: Wrong response type received
- DeviceNotBound: Operation requires binding first
- ConnectionLost: BLE disconnected
- InvalidPayload: Payload data malformed

### Validation Order
1. Start byte check
2. Length validation (buffer has enough bytes)
3. Checksum verification
4. End byte check
5. Command/response type validation

---

## Task 5: Bind Handshake Decisions

### Retry Logic Design

**Why 3 retries?**
- Empirical testing shows BLE packets occasionally dropped under interference
- 3 attempts balances reliability vs. user experience
- Matches common network retry patterns (TCP retransmission: ~3-5 attempts)

**Why 1-second delay?**
- BLE device needs time to process and respond
- Too short: Device may still be processing previous request
- Too long: Poor user experience
- 1 second is common embedded device response window

### State Machine Extension

**Why add .binding and .bound to ConnectionState?**
- UI needs to show bind progress to user
- Different actions available in different states
- Debugging: Clear state transitions in logs
- Future: Could enable/disable features based on bind state

**State progression rationale:**
```
disconnected → connecting → connected → initializing → binding → bound
```
- Each state represents a distinct phase
- Reversible on failure (can go back to disconnected)
- Clear success criteria for each transition

### Timeout Handling

**Why 5-second timeout?**
- BLE operations typically complete within 1-2 seconds
- 5 seconds accounts for:
  - Device processing time
  - BLE link latency
  - iOS scheduler delays
  - Occasional packet loss requiring retransmission
- After 5 seconds, likely actual failure, not just delay

### Error State Management

**Why reset bindRetryCount on success?**
- Ensures fresh start for next bind attempt
- Prevents accumulation of retry state
- Clear separation between attempts

**Why set both slinkState and connectionState?**
- slinkState: Internal SLink protocol state
- connectionState: Public UI-facing state
- Allows for internal complexity without exposing to UI
