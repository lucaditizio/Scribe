# Audio Recording from Bluetooth Microphone

## TL;DR

> **Quick Summary**: Implement live audio recordingfrom the LA518/LA519 Bluetooth microphone. The device streams Opus audio on F0F3 characteristic which needs to be decoded, encoded to M4A/AAC, and stored in the app's Documents/Recordings/ directory with SwiftData Recording entries displayed in RecordingListView.
>
> **Deliverables**:
> - Working Opus decoder integrated into AudioStreamReceiver
> - M4A/AAC encoder for saving recordings
> - Recordings stored in Documents/Recordings/ with SwiftData entries
> - Recordings displayed in RecordingListView
> - Playback through existing AudioPlayer
>
> **Estimated Effort**: Medium
> **Parallel Execution**: YES -3 waves
> **Critical Path**: Opus Decoder → M4A Encoder → UI Integration → Disconnect Handling

---

## Context

### Original Request
"We now need to plan the further improvements. We need to make sure that we can record from the microphone and that these recordings are stored in the main view of the application."

### Interview Summary
**Key Discussions**:
- Audio format: User chose M4A/AAC (decoded from Opus)
- File sync from device: Deferred (no packet capture available)
- Testing: Agent-executed QA only (no unit tests)
- Storage: SwiftData Recording model + FileManagerfor audio files

**Research Findings**:
- Opus audio streams on F0F3 characteristic (handle 0x0028)
- Frame header pattern: `FF F3 48 C4...`
- OpusAudioDecoder stub exists in AudioStreamReceiver.swift (lines 199-232)
- AudioConverter.swift shows pattern for PCM processing at 16kHz
- DeviceConnectionManager posts .audioCharacteristicDidUpdate notifications
- RecordingListView uses @Query for SwiftData, RecordButtonView for recording

### Metis Review
**Identified Gaps** (addressed):
- Opus decoder library: Will use SwiftOpus package or AVAudioConverter with Opus support
- Sample rate: 16kHz (matching AudioConverter.swift pattern)
- Recording lifecycle: START on button press, STOP on button press or disconnect
- File naming: Timestamp-based (`Recording_2026-04-04_14-41-53.m4a`)
- Storage structure: `Documents/Recordings/`

---

## Work Objectives

### Core Objective
Implement live audio recording from Bluetooth microphone with Opus decoding, M4A encoding, storage, and playback.

### Concrete Deliverables
- Opus decoder integrated into AudioStreamReceiver
- M4A encoder saving to Documents/Recordings/
- SwiftData Recording entries created on recording stop
- Recordings displayed in RecordingListView
- Playback working through AudioPlayer

### Definition ofDone
- [ ] User can start recording via RecordButtonView
- [ ] User can stop recording via RecordButtonView
- [ ] Recording appears in RecordingListView after stop
- [ ] Recording plays back correctly in AudioPlayer
- [ ] Bluetooth disconnect stops recording gracefully

### Must Have
- Opus to PCM decoding (16kHz, mono)
- PCM to M4A/AAC encoding
- SwiftData Recording entry creation
- RecordingListView display
- AudioPlayer playback
- Disconnect handling

### Must NOT Have (Guardrails)
- NO file sync from device storage (deferred)
- NO unit tests (agent-executed QA only)
- NO pause/resume functionality
- NO background recording support
- NO audio visualization during recording
- NO recording editing/trimming
- NO cloud sync or sharing
- NO format selection (M4A/AAC only)

---

## Verification Strategy (MANDATORY)

> **ZERO HUMAN INTERVENTION** —ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: Partial (test files exist, but no test target in Xcode project)
- **Automated tests**: None
- **Framework**: N/A
- **Agent-Executed QA**: ALWAYS (mandatory for all tasks)

### QA Policy
Every task MUST include agent-executed QA scenarios.
Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **iOS App**: Build in Xcode, run in Simulator, verify UI with Manual testing steps (documented for agent)
- **Audio Recording**: Start recording,verify file creation, check SwiftData entry
- **Playback**: Tap recording, verify audio plays

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — foundation):
├── Task 1: Integrate SwiftOpus package[deep]
├── Task 2: Verify Recording model fields [quick]
└── Task 3: Verify AudioPlayer M4A support [quick]

Wave 2 (After Wave 1 — core implementation):
├── Task 4: Implement Opus → PCM decoding [deep]
├── Task 5: Create BleAudioRecorder service [deep]
└── Task 6: Create Documents/Recordings/ storage [quick]

Wave 3 (After Wave 2 — integration):
├── Task 7: Connect RecordButtonView to BleAudioRecorder [visual-engineering]
├── Task 8: Create SwiftData Recording entry on stop [quick]
└── Task 9: Wire RecordingListView to display recordings [visual-engineering]

Wave 4 (After Wave 3 — playback and edge cases):
├── Task 10: Connect playback to AudioPlayer [quick]
├── Task 11: Handle Bluetooth disconnect during recording [deep]
└── Task 12: Update DeviceSettingsView recording state [visual-engineering]

Wave FINAL (After ALL tasks — verification):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Manual QA in Simulator (unspecified-high)
└── Task F4: Scope fidelity check (deep)
```

### Dependency Matrix

- **1, 2, 3**: No dependencies (can run in parallel)
- **4**: Depends on 1
- **5**: Depends on 4
- **6**: No dependencies
- **7**: Depends on 5
- **8**: Depends on 5, 7
- **9**: Depends on 8
- **10**: Depends on 9
- **11**: Depends on 5, 7
- **12**: Depends on 7

### Agent Dispatch Summary

- **Wave 1**:3 agents — T1→`deep`, T2→`quick`, T3→`quick`
- **Wave 2**:3 agents — T4→`deep`, T5→`deep`, T6→`quick`
- **Wave 3**:3 agents — T7→`visual-engineering`, T8→`quick`, T9→`visual-engineering`
- **Wave 4**:3 agents — T10→`quick`, T11→`deep`, T12→`visual-engineering`
- **FINAL**:4 agents — F1→`oracle`, F2→`unspecified-high`, F3→`unspecified-high`, F4→`deep`

---

## TODOs

- [x] 1. Integrate SwiftOpus Package for Opus Decoding

  **What to do**:
  - Add SwiftOpus package dependency to Scribe project (via Xcode > File > Add Packages or Package.swift)
  - SwiftOpus provides `OpusDecoder` class for decoding Opus packets to PCM
  - Alternative: Use `dlopen`/`dlsym` to access opus.framework functions directly if SwiftOpus isn't available
  - Verify package builds with `xcodebuild -workspace Scribe.xcworkspace -scheme Scribe build`
  
  **Must NOT do**:
  - DO NOT implement custom Opus decoder from scratch
  - DO NOT use the opus.framework binary directlywithout proper Swift bridging

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: [] (no special skills needed)
  
  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3)
  - **Blocks**: Task 4
  - **Blocked By**: None

  **References**:
  - `AI_DVR_Link/Frameworks/opus.framework/opus` - Binary location for dlopen approach
  - https://github.com/emuve/SwiftOpus - SwiftOpus package reference
  - `Scribe/Scribe/Sources/Bluetooth/AudioStreamReceiver.swift:199-232` - Existing OpusAudioDecoder stub to replace

  **Acceptance Criteria**:
  - [ ] SwiftOpus (or equivalent) package added to project dependencies
  - [ ] Project builds successfully with new dependency
  - [ ] OpusDecoder class available for import

  **QA Scenarios**:
  ```
  Scenario: SwiftOpus package integration
    Tool: Bash
    Preconditions: Xcode project open
    Steps:
      1. Navigate to Scribe directory
      2. Run: xcodebuild -workspace Scribe.xcworkspace -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' build
    Expected Result: Build succeeds with exit code 0
    Failure Indicators: Build errors mentioning "SwiftOpus" or "Opus"
    Evidence: .sisyphus/evidence/task-01-build-log.txt
  ```

  **Commit**: YES
  - Message: `feat(audio): add SwiftOpus package dependency`
  - Files: `Scribe.xcodeproj/project.pbxproj` or `Package.swift`

- [x] 2. Verify Recording.swift Model Fields

  **What to do**:
  - Read `Scribe/Scribe/Sources/Models/Recording.swift`
  - Verify it has required fields: `id`, `title`, `duration`, `createdAt`, `audioFilePath`, `categoryTag`
  - Check ifdevice-related fields exist (optional: `deviceId`, `deviceName`)
  - Document any fields that need to be added
  - NO CODE CHANGES - just verification and documentation

  **Must NOT do**:
  - DO NOT modify the model unless explicitly asked
  - DO NOT add new fields without confirmation

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []
  
  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3)
  - **Blocks**: None
  - **Blocked By**: None

  **References**:
  - `Scribe/Scribe/Sources/Models/Recording.swift` - SwiftData Recording model

  **Acceptance Criteria**:
  - [ ] Model verified to have: `id: String` (@Attribute(.unique))
  - [ ] Model verified to have: `title: String`
  - [ ] Model verified to have: `duration: TimeInterval`
  - [ ] Model verified to have: `createdAt: Date`
  - [ ] Model verified to have: `audioFilePath: String`
  - [ ] Document any missing fields

  **QA Scenarios**:
  ```
  Scenario: Model verification
    Tool: Bash
    Steps:
      1. Read Recording.swift
      2. Parse SwiftData model fields
      3. Verify required fields exist
    Expected Result: All required fields documented
    Evidence: .sisyphus/evidence/task-02-model-verification.md
  ```

  **Commit**: NO

- [x] 3. Verify AudioPlayer Supports M4A/AAC

  **What to do**:
  - Read `Scribe/Scribe/Sources/Audio/AudioPlayer.swift`
  - Verify AVAudioPlayer initialization supports M4A/AAC files
  - Check if any format restrictions exist
  - Document the playback capabilities
  - NO CODE CHANGES - just verification

  **Must NOT do**:
  - DO NOT modify AudioPlayer unless required
  - DO NOT add new playback features

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []
  
  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2)
  - **Blocks**: Task 10
  - **Blocked By**: None

  **References**:
  - `Scribe/Scribe/Sources/Audio/AudioPlayer.swift` - Existing audio player

  **Acceptance Criteria**:
  - [ ] Document that AVAudioPlayer loads `.m4a` files
  - [ ] Identify any needed modifications (if any)

  **QA Scenarios**:
  ```
  Scenario: AudioPlayer M4A verification
    Tool: Read
    Steps:
      1. Read AudioPlayer.swift
      2. Find AVAudioPlayer initialization
      3. Verify no format restrictions prevent M4A playback
    Expected Result: Documentation confirms M4A support
    Evidence: .sisyphus/evidence/task-03-audioplayer-verification.md
  ```

  **Commit**: NO

- [x] 4. Implement Opus → PCM Decoding in AudioStreamReceiver

  **What to do**:
  - Replace the stub in `OpusAudioDecoder` class (AudioStreamReceiver.swift:199-232)
  - Initialize SwiftOpus decoder with sample rate 16000, channels 1
  - Implement `decode(_ data: Data) throws -> [Float]` to:
    1. Pass Opus packet data to SwiftOpus decoder
    2. Receive PCM Int16 samples
    3. Normalize to Float32 in range [-1.0, 1.0]
  - Handle Opus frame header (`FF F3 48 C4...`) - strip it before decoding if present
  - Update `handleIncomingAudioData()` to use the decoder

  **Must NOT do**:
  - DO NOT change the AudioFrame structure
  - DO NOT modify the CircularAudioBuffer
  - DO NOT add error recovery beyond logging and skipping bad packets

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []
  
  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 2)
  - **Blocks**: Task 5
  - **Blocked By**: Task 1

  **References**:
  - `Scribe/Scribe/Sources/Bluetooth/AudioStreamReceiver.swift:199-232` - OpusAudioDecoder stub
  - `Scribe/Scribe/Sources/Bluetooth/AudioStreamReceiver.swift:handleIncomingAudioData()` - Where to integrate decoder
  - `Scribe/Scribe/Sources/Audio/AudioConverter.swift` - PCM pattern reference

  **Acceptance Criteria**:
  - [ ] OpusAudioDecoder.decode() returns [Float] PCM samples
  - [ ] Frame rate is 16000 samples/second
  - [ ] 20ms packets produce ~320 samples
  - [ ] Values normalized to [-1.0, 1.0] range
  - [ ] Invalid packets are logged and skipped (no crash)

  **QA Scenarios**:
  ```
  Scenario: Opus decoding produces PCM
    Tool: Bash (unit test or manual verification)
    Preconditions: OpusAudioDecoder class implemented
    Steps:
      1. Create test Opus packet data (from captured F0F3 data)
      2. Call decoder.decode(testData)
      3. Verify output is [Float] array
      4. Check sample count matches expected (320 for 20ms at 16kHz)
    Expected Result: Float array with~320 samples, values in [-1.0, 1.0]
    Failure Indicators: Empty array, crash, values outside range
    Evidence: .sisyphus/evidence/task-04-decoder-test.txt
  ```

  **Commit**: YES
  - Message: `feat(audio): implement Opus decoder in AudioStreamReceiver`
  - Files: `Scribe/Scribe/Sources/Bluetooth/AudioStreamReceiver.swift`

- [x] 5. Create BleAudioRecorder Service for Live Recording

  **What to do**:
  - Create new file: `Scribe/Scribe/Sources/Audio/BleAudioRecorder.swift`
  - Implement `@Observable class BleAudioRecorder: NSObject`:
    - `state: RecordingState` (.idle, .recording, .paused, .stopped)
    - `audioBuffer: [Float]` accumulating PCM samples
    - `startRecording()` - Subscribe to .audioCharacteristicDidUpdate notification
    - `stopRecording() -> URL?` - Stop, encode to M4A, return file URL
    - `handleAudioData(_ data: [Float])` - Append to buffer
  - Encode PCM to M4A using AVAudioRecorder or AudioConverter:
    - Create AVAudioRecorder with PCM buffer
    - Write to temporary file first, then move to Documents/Recordings/
  - Handle disconnect notification to stop recording gracefully

  **Must NOT do**:
  - DO NOT use AVAudioRecorder for BLE streaming (it's for mic input)
  - DO NOT implement pause/resume functionality
  - DO NOT support background recording

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []
  
  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 2, after Task 4)
  - **Blocks**: Tasks 7, 11
  - **Blocked By**: Task 4

  **References**:
  - `Scribe/Scribe/Sources/Audio/AudioRecorder.swift` - Pattern for @Observable recording class
  - `Scribe/Scribe/Sources/Audio/AudioConverter.swift` - PCM processing pattern
  - `Scribe/Scribe/Sources/Bluetooth/DeviceConnectionManager.swift` - .audioCharacteristicDidUpdate notification

  **Acceptance Criteria**:
  - [ ] BleAudioRecorder class created with @Observable
  - [ ] startRecording() subscribes to audio notifications
  - [ ] stopRecording() generatesM4A file URL
  - [ ] M4A file plays successfully in AVAudioPlayer
  - [ ] Disconnect stops recording and saves partial file

  **QA Scenarios**:
  ```
  Scenario: Recording lifecycle
    Tool: Simulator manual test
    Preconditions: App launched, Bluetooth device connected
    Steps:
      1. bleAudioRecorder.startRecording()
      2. Receive audio data for 3 seconds
      3. let url = bleAudioRecorder.stopRecording()
      4. Verify url != nil
      5. Verify file exists at url
      6. Try AVAudioPlayer(contentsOf: url) - verify it initializes
    Expected Result: M4A file created and playable
    Failure Indicators: URL is nil, file doesn't exist, player fails
    Evidence: .sisyphus/evidence/task-05-recording-test.m4a
  ```

  **Commit**: YES
  - Message: `feat(audio): create BleAudioRecorder service for live recording`
  - Files: `Scribe/Scribe/Sources/Audio/BleAudioRecorder.swift`

- [x] 6. Create Documents/Recordings/ Storage Directory

  **What to do**:
  - Add helper method to ensure Documents/Recordings/ directory exists
  - Create `RecordingsStorage.swift` or add to existing utility:
    - `static func recordingsDirectory() -> URL`
    - `static func ensureRecordingsDirectoryExists() throws`
  - Use FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  - Call this from BleAudioRecorder.startRecording() or app startup

  **Must NOT do**:
  - DO NOT move or delete existing files
  - DO NOT create subdirectories beyond Recordings/

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []
  
  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 5)
  - **Blocks**: None
  - **Blocked By**: None

  **References**:
  - `Scribe/Scribe/Sources/Audio/AudioRecorder.swift` - Pattern for Documents/ access

  **Acceptance Criteria**:
  - [ ] Documents/Recordings/ directory created on first run
  - [ ] URL builder returns valid path
  - [ ] Directory persists across app launches

  **QA Scenarios**:
  ```
  Scenario: Directory creation
    Tool: Bash (Simulator)
    Steps:
      1. Launch app
      2. Check for Documents/Recordings/ existence
      3. Verify path is writable
    Expected Result: Directory exists and is writable
    Evidence: .sisyphus/evidence/task-06-directory-test.txt
  ```

  **Commit**: YES
  - Message: `feat(storage): create Documents/Recordings/ storage directory`
  - Files: `Scribe/Scribe/Sources/Audio/RecordingsStorage.swift`

- [x] 7. Connect RecordButtonView to BleAudioRecorder

  **What to do**:
  - Update `Scribe/Scribe/Sources/UI/RecordButtonView.swift`:
    - Add `@State private var bleRecorder = BleAudioRecorder()`
    - Modify tap action to call `bleRecorder.startRecording()` / `bleRecorder.stopRecording()`
    - Update button state based on `bleRecorder.state`
  - Connect to DeviceConnectionManager to check connection state
  - Disable recording button when device is disconnected

  **Must NOT do**:
  - DO NOT change button visual design
  - DO NOT add pause button
  - DO NOT implement background recording

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: [`frontend-ui-ux`]
  
  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 3, after Task 5)
  - **Blocks**: Tasks 8, 12
  - **Blocked By**: Task 5

  **References**:
  - `Scribe/Scribe/Sources/UI/RecordButtonView.swift` - Existing record button
  - `Scribe/Scribe/Sources/UI/RecordingListView.swift` - Pattern for @State usage
  - `Scribe/Scribe/Sources/Bluetooth/DeviceConnectionManager.swift` - ConnectionState enum

  **Acceptance Criteria**:
  - [ ] Record button starts BleAudioRecorder when tapped
  - [ ] Button state changes to "recording" visually
  - [ ] Button stops recording when tapped again
  - [ ] Button disabled when device not connected

  **QA Scenarios**:
  ```
  Scenario: Record button interaction
    Tool: Simulator launch
    Preconditions: App launched, device connected (mock or real)
    Steps:
      1. View RecordingListView
      2. Tap record button
      3. Observe button state changes to "recording"
      4. Wait 2 seconds
      5. Tap record button again
      6. Verify BleAudioRecorder.state == .stopped
    Expected Result: Button state toggles correctly
    Failure Indicators: Button doesn't respond, state doesn't change
    Evidence: .sisyphus/evidence/task-07-button-state.mp4
  ```

  **Commit**: YES
  - Message: `feat(ui): connect RecordButtonView to BleAudioRecorder`
  - Files: `Scribe/Scribe/Sources/UI/RecordButtonView.swift`

- [x] 8. Create SwiftData Recording Entry on Recording Stop

  **What to do**:
  - In BleAudioRecorder.stopRecording(), after saving M4A file:
    - Create Recording SwiftData entry
    - Set fields: id (UUID), title ("Recording {timestamp}"), duration, createdAt, audioFilePath, categoryTag ("#NOTE")
  - Use modelContext from environment
  - Save to SwiftData
  - Trigger RecordingListView refresh

  **Must NOT do**:
  - DO NOT create multiple entries for same recording
  - DO NOT block main thread with SwiftData operations

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []
  
  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 3, after Tasks 5, 7)
  - **Blocks**: Task 9
  - **Blocked By**: Tasks 5, 7

  **References**:
  - `Scribe/Scribe/Sources/Models/Recording.swift` - SwiftData model
  - `Scribe/Scribe/Sources/UI/RecordingListView.swift` - Pattern for modelContext.insert()

  **Acceptance Criteria**:
  - [ ] Recording entry created in SwiftData after stopRecording()
  - [ ] Entry contains correct file path
  - [ ] Entry contains accurate duration
  - [ ] Entry appears in RecordingListView immediately

  **QA Scenarios**:
  ```
  Scenario: SwiftData entry creation
    Tool: Simulator
    Steps:
      1. Start recording
      2. Wait 3 seconds
      3. Stop recording
      4. Check SwiftData for new Recording entry
      5. Verify entry.audioFilePath matches saved file
      6. Verify entry.duration > 0
    Expected Result: Entry exists with correct data
    Evidence: .sisyphus/evidence/task-08-swiftdata-entry.txt
  ```

  **Commit**: YES
  - Message: `feat(data): create Recording SwiftData entry on recording stop`
  - Files: `Scribe/Scribe/Sources/Audio/BleAudioRecorder.swift`

- [x] 9. Display Recordings in RecordingListView

  **What to do**:
  - Verify RecordingListView uses @Query for SwiftData Recording entries
  - Ensure new recordings appear without manual refresh
  - Update RecordingCardView to show duration, title, date correctly
  - Connect tap gesture to navigate to RecordingDetailView

  **Must NOT do**:
  - DO NOT change card layout significantly
  - DO NOT add sorting controls (use default sort)
  - DO NOT implement swipe-to-delete (already exists)

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: [`frontend-ui-ux`]
  
  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 3, after Task 8)
  - **Blocks**: Task 10
  - **Blocked By**: Task 8

  **References**:
  - `Scribe/Scribe/Sources/UI/RecordingListView.swift` - Main list view
  - `Scribe/Scribe/Sources/UI/RecordingCardView.swift` - Card component
  - `Scribe/Scribe/Sources/UI/RecordingDetailView.swift` - Detail view for playback

  **Acceptance Criteria**:
  - [ ] RecordingListView shows all SwiftData Recording entries
  - [ ] New recordings appear immediately after creation
  - [ ] RecordingCardView shows: title, duration, createdAt, categoryTag
  - [ ] Tapping card navigates to RecordingDetailView

  **QA Scenarios**:
  ```
  Scenario: Recording list display
    Tool: Simulator
    Steps:
      1. Launch app
      2. Create 2 test recordings
      3. Navigate to RecordingListView
      4. Verify 2 recordings displayed
      5. Tap first recording
      6. Verify navigation to RecordingDetailView
    Expected Result: Recordings display correctly
    Failure Indicators: List empty, wrong data, navigation fails
    Evidence: .sisyphus/evidence/task-09-list-display.mp4
  ```

  **Commit**: YES
  - Message: `feat(ui): display recordings in RecordingListView`
  - Files: `Scribe/Scribe/Sources/UI/RecordingListView.swift`, `Scribe/Scribe/Sources/UI/RecordingCardView.swift`

- [x] 10. Connect Recording Playback to AudioPlayer
- [x] 11. Handle Bluetooth Disconnect During Recording
- [x] 12. Update DeviceSettingsView Recording State Display

  **What to do**:
  - Show recording state in DeviceSettingsView when device is connected
  - Display indicator when recording is in progress
  - Show duration counter during recording
  - Update connection state badge to show "Recording" when active

  **Must NOT do**:
  - DO NOT add full recording UI to settings view
  - DO NOT duplicate RecordButtonView functionality
  - DO NOT modify connection logic

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: [`frontend-ui-ux`]
  
  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 4, after Task 7)
  - **Blocks**: None
  - **Blocked By**: Task 7

  **References**:
  - `Scribe/Scribe/Sources/UI/DeviceSettingsView.swift` - Settings view
  - `Scribe/Scribe/Sources/Audio/BleAudioRecorder.swift` - Recording state

  **Acceptance Criteria**:
  - [ ] DeviceSettingsView shows "Recording" state when BleAudioRecorder.state == .recording
  - [ ] Duration counter updates in real-time
  - [ ] State clears when recording stops

  **QA Scenarios**:
  ```
  Scenario: Recording state display
    Tool: Simulator
    Steps:
      1. Open DeviceSettingsView
      2. Start recording from RecordButtonView
      3. Verify "Recording" indicator appears in settings
      4. Verify duration counter increments
      5. Stop recording
      6. Verify indicator clears
    Expected Result: State displayed correctly
    Failure Indicators: No state shown, counter frozen
    Evidence: .sisyphus/evidence/task-12-state-display.mp4
  ```

  **Commit**: YES
  - Message: `feat(ui): update DeviceSettingsView recording state display`
  - Files: `Scribe/Scribe/Sources/UI/DeviceSettingsView.swift`

---

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read the plan end-to-end. For each "Must Have": verify implementation exists. For each "Must NOT Have": search codebase for forbidden patterns. Check evidence files exist in .sisyphus/evidence/. Compare deliverables against plan.
  
  **Verification**:
  - Must Have: Opus decoder in AudioStreamReceiver
  - Must Have: M4A files in Documents/Recordings/
  - Must Have: SwiftData Recording entries visible
  - Must Have: AudioPlayer plays recordings
  - Must Have: Disconnect handling Graceful
  
  Output: `Must Have [5/5] | Must NOT Have [6/6] | Tasks [12/12] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `xcodebuild build` and check for compilation errors. Review all changed files for: `as any`/`@ts-ignore`, empty catches, console.log in prod, commented-out code, unused imports. Check AI slop: excessive comments, over-abstraction, generic names.
  
  Output: `Build [PASS/FAIL] | Lint [N/A] | Files [N clean/N issues] | VERDICT`

- [ ] F3. **Manual QA in Simulator** — `unspecified-high`
  Launch app in iPhone 15 Plus simulator. Execute EVERY QA scenario from EVERY task. Test cross-feature: record → disconnect → reconnect → record again. Test edge: empty recording, rapid record/stop. Save screenshots/evidence.
  
  Output: `Scenarios [N/N pass] | Integration [N/N] | Edge Cases [N tested] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do", read actual diff (git diff). Verify 1:1 — everything in spec was built, nothing beyond spec was built. Check "Must NOT do" compliance. Flag unaccounted changes.
  
  Output: `Tasks [N/N compliant] | Contamination [CLEAN/N issues] | Unaccounted [CLEAN/N files] | VERDICT`

---

## Commit Strategy

- **1**: `feat(audio): add SwiftOpus package dependency`
- **4**: `feat(audio): implement Opus decoder in AudioStreamReceiver`
- **5**: `feat(audio): create BleAudioRecorder service for live recording`
- **7**: `feat(ui): connect RecordButtonView to BleAudioRecorder`
- **8**: `feat(data): create Recording SwiftData entry on recording stop`
- **9**: `feat(ui): display recordings in RecordingListView`
- **10**: `feat(audio): connect recording playback to AudioPlayer`
- **11**: `fix(audio): handle Bluetooth disconnect during recording`

---

## Success Criteria

### Verification Commands
```bash
# Build the app
xcodebuild -workspace Scribe.xcworkspace -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' build

# Check recordings directory
ls ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Documents/Recordings/
```

### Final Checklist
- [ ] SwiftOpus package added andbuilding
- [ ] Opus decoder produces PCM output
- [ ] M4A files created in Documents/Recordings/
- [ ] SwiftData entries visible in RecordingListView
- [ ] AudioPlayer plays recordings correctly
- [ ] Bluetooth disconnect stops recording gracefully