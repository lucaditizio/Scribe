# BleAudioRecorder Implementation Learnings

## Date: 2026-04-04

### Implementation Summary
Created BleAudioRecorder service for live BLE audio recording with the following key features:

### Key Patterns Used
1. **@Observable + @MainActor**: Combined for SwiftUI compatibility and thread safety
2. **Notification-based audio data flow**: Subscribes to `.audioCharacteristicDidUpdate` notifications from DeviceConnectionManager
3. **OpusAudioDecoder integration**: Reuses existing decoder from AudioStreamReceiver for Opus → PCM conversion
4. **AVAssetWriter for M4A encoding**: Converts accumulated Float PCM samples to M4A/AAC format

### Audio Pipeline
```
BLE Notification → OpusAudioDecoder.decode() → [Float] buffer → 
Int16 PCM conversion → AVAssetWriter → M4A file in Documents/Recordings/
```

### Important Technical Details

1. **Sample Rate**: 16kHz (matches OpusAudioDecoder configuration)
2. **Channels**: Mono (1 channel)
3. **PCM Format**: Float32 in [-1.0, 1.0] from decoder, converted to Int16 for encoding
4. **AAC Settings**: 128 kbps, high quality, 16kHz sample rate
5. **File Naming**: `Recording_YYYY-MM-DD_HH-mm-ss.m4a`

### Concurrency Handling
- All @Observable properties accessed on MainActor
- Background audio processing done via Task { @MainActor }
- AVAssetWriter operations performed on dedicated serial queue
- Disconnect handling triggers automatic recording stop with partial file save

### Build Warnings Addressed
- Fixed AVAssetWriterInput initialization (not optional, removed guard let)
- Fixed dangling buffer pointer using withUnsafeBytes
- Addressed @MainActor isolation for notification handlers

### Dependencies
- RecordingsStorage: Directory management
- OpusAudioDecoder: Opus packet decoding
- DeviceConnectionManager: Audio characteristic notifications

---

## Task 9: Recording List Display (2026-04-04)

### Implementation Status
**Already Complete** - All acceptance criteria were implemented in previous tasks.

### Key Findings

1. **@Query Auto-Refresh**
   - SwiftData's @Query property wrapper automatically observes ModelContext changes
   - When `modelContext.insert(newRecording)` and `modelContext.save()` are called, @Query detects the change
   - No manual refresh or state management needed
   - List updates automatically when new recordings are added

2. **RecordingListView Pattern**
   ```swift
   @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
   ```
   - Sorted by createdAt in reverse order (newest first)
   - Works with SwiftData ModelContainer injected in ScribeApp

3. **RecordingCardView Pattern**
   - Displays: title, duration (formatted), createdAt (date + time), categoryTag
   - Uses `.scribeCardStyle(scheme: colorScheme)` for consistent styling
   - Wrapped in NavigationLink for navigation to RecordingDetailView

4. **Navigation Pattern**
   ```swift
   NavigationLink(destination: RecordingDetailView(recording: recording)) {
       RecordingCardView(recording: recording)
   }
   ```
   - Passes Recording object to RecordingDetailView
   - RecordingDetailView uses `@Bindable var recording: Recording` for SwiftUI binding

### Build Verification
- Build succeeded with `xcodebuild -project Scribe.xcodeproj -scheme Scribe`
- LSP errors in other files (DeviceConnectionManager, AudioStreamReceiver) are pre-existing and unrelated

### Dependencies
- Task 8: SwiftData entry creation ✅
- Task 7: RecordButtonView integration ✅
- Task 5: BleAudioRecorder service ✅

---

## Task 10: Recording Playback (2026-04-04)

### Implementation Status
**Already Complete** - All acceptance criteria were implemented in previous tasks.

### Key Findings

1. **AudioPlayer Integration**
   - RecordingDetailView already has `@State private var audioPlayer = AudioPlayer()`
   - `.onAppear` calls `audioPlayer.load(recording: recording)` (line 239)
   - File URL is correctly constructed: `Documents/` + `recording.audioFilePath`

2. **Playback Controls Already Wired**
   - Play/pause: `audioPlayer.togglePlayback()` (line 58)
   - Skip backward 15s: `audioPlayer.skipBackward()` (line 53)
   - Skip forward 15s: `audioPlayer.skipForward()` (line 64)
   - Speed cycling: `audioPlayer.cycleSpeed()` with display (lines 69-76)

3. **AudioPlayer.load(recording:) Implementation** (AudioPlayer.swift:15-42)
   - Constructs file URL from `recording.audioFilePath`
   - Sets up AVAudioSession for playback
   - Initializes AVAudioPlayer with AAC/M4A support
   - Sets `duration = audioPlayer?.duration ?? recording.duration`

4. **File Path Pattern**
   - Recording.audioFilePath stores relative path (e.g., "Recordings/UUID.m4a")
   - AudioPlayer constructs: `DocumentsDirectory.appendingPathComponent(recording.audioFilePath)`

### Build Verification
- Build succeeded: `** BUILD SUCCEEDED **`
- No modifications needed - integration was already complete

### Dependencies
- Task 9: Recording list display ✅
- Task 6: M4A file storage in Documents/Recordings/ ✅
- Task 3: AudioPlayer with M4A/AAC support ✅
