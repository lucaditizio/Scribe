# BLE Connection - Remaining Questions

## Current Implementation Status

The DeviceConnectionManager now implements:
1. ✅ DVRLinkUUID enum with all 5 proprietary UUIDs
2. ✅ Connect → discoverServices → discoverCharacteristics → sendAuth → subscribe flow
3. ✅ Auth handshake with `{"auth_tm":"<timestamp>","encrypt_data":""}`
4. ✅ Subscription only after auth success

## What's Different from AI_DVR_Link App

### Libraries Used
| Component | AI DVR Link | Our Implementation |
|----------|-------------|---------------------|
| BLE Library | flutter_ble_lib (Flutter plugin) | Native CoreBluetooth |
| Reactive | RxBluetoothKit.framework | None (delegate pattern) |
| Audio Decoder | iflyse.framework (ASC) | Stub (Opus planned) |

### Potential Timing Differences
1. **Connection options** - Maybe we need specific CBConnectPeripheralOption flags
2. **MTU negotiation** - Maybe we need to request specific MTU before operations
3. **Thread/queue** - Maybe operations need to happen on specific dispatch queues
4. **Service discovery timing** - Maybe auth must happen BEFORE any service discovery

## Experiments to Try

### 1. Send Auth BEFORE Service Discovery
The device might reject service discovery until authenticated. Try:
```swift
// In didConnect:
peripheral.discoverServices([DVRLinkUUID.primaryService])
// After getting services, but BEFORE discovering characteristics:
sendAuthHandshake()
// Only then discover characteristics
```

### 2. Try Alternative encrypt_data Values
```swift
// Attempt 1: Empty string (current)
{"auth_tm":"1234567890","encrypt_data":""}

// Attempt 2: 16 null bytes base64
{"auth_tm":"1234567890","encrypt_data":"AAAAAAAAAAAAAAAAAAAAAA=="}
```

### 3. Connection Options
Try adding more connection options:
```swift
centralManager.connect(peripheral, options: [
    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
    "CBConnectPeripheralOptionPreferredPHY": 1,  // LE 1M PHY
])
```

### 4. Add Logging for Every Step
Ensure we can see:
- When service discovery completes (or fails)
- When characteristics are found
- When write completes (or fails)
- When notifications are enabled (or fail)

## Diagnostic Questions

1. **Does the device appear in scan results?** → Check BluetoothDeviceScanner
2. **Does connection succeed at radio level?** → Check didConnect fires
3. **Does service discovery succeed?** → Check didDiscoverServices error
4. **Does characteristic discovery succeed?** → Check didDiscoverCharacteristicsFor error
5. **Does auth write succeed?** → Check didWriteValueFor error
6. **Does notification subscription succeed?** → Check didUpdateNotificationStateFor error

## If Nothing Works

The device might require:
1. **Physical proximity** - Closer than typical BLE range
2. **No competing connections** - Only one device connected at a time
3. **Device reset** - Device might be in bad state
4. **Specific iOS version** - Some BLE behaviors differ by iOS version

## Next Steps

1. Run app and check console logs for each step
2. Verify device is found in scan
3. Verify connection succeeds
4. Check where exactly it fails
5. Try alternative encrypt_data values if auth fails

---

*Document created during debugging session - to be updated with findings*
