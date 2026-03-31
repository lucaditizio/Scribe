# Scribe Application Enhancement - Implementation Plan

## Project Overview

**Project Name:** Scribe  
**Hardware Target:** iPhone 15 Plus (6GB RAM, A16 Bionic)  
**Current State:** On-device recording, transcription, and summarization app using FluidAudio (Parakeet ASR + OfflineDiarizer), Llama.cpp for LLM inference  
**Goal:** Add external Bluetooth microphone integration, real-time VAD-based noise suppression, improved speaker diarization, and modular ML pipeline

---

## Architecture Context

### Current Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  SwiftUI Layer                                             │
│  RecordingListView → RecordingDetailView                   │
└─────────────────────────┬─────────────────────────────────┘
                          │
┌─────────────────────────▼─────────────────────────────────┐
│  Service Layer                                             │
│  AudioRecorder (AVAudioRecorder, 48kHz mono)              │
│  AudioConverter (48kHz → 16kHz Float32 for ASR)           │
│  InferencePipeline (orchestrator)                          │
└─────────────────────────┬─────────────────────────────────┘
                          │
┌─────────────────────────▼─────────────────────────────────┐
│  ML Layer (FluidAudio)                                     │
│  OfflineDiarizer (TitaNet-Small)                          │
│  AsrManager (Parakeet-TDT-0.6B)                           │
│  LLMService (Llama-3.2-3B via llama.cpp)                 │
└─────────────────────────────────────────────────────────────┘
```

### AI DVR Link Context (Source for Bluetooth Protocol)

The AI DVR Link Flutter app (in `/AI_DVR_Link/`) contains:
- **Bluetooth Framework:** RxBluetoothKit (Flutter plugin `flutter_ble_lib`)
- **Voice Engine:** Custom `AIDvrLinkVoiceEnginePlugin` 
- **Audio Codec:** Opus codec via `AIDvrLinkOpusPlugin`
- **Device Identifiers Found:** `19CAEEngine_2MicPhone`, `MlpAES2MicTV`

---

## Implementation Plan

### Phase 1: External Bluetooth Microphone Integration

#### Goal
Enable Scribe to connect to the external Bluetooth microphone (same device used with AI DVR Link app), supporting both live recording and syncing saved recordings from the device's flash storage.

#### Dependencies to Add
- **CoreBluetooth** (iOS native framework - no external dependency needed)
- **RxBluetoothKit** (if needed for reactive Bluetooth operations - same as AI DVR Link)

#### Implementation Steps

**Step 1.1: Bluetooth Device Scanner Service**
- **File:** `Sources/Bluetooth/BluetoothDeviceScanner.swift`
- **Purpose:** Discover BLE devices, filter by manufacturer-specific identifiers
- **Implementation:**
  - Use CoreBluetooth `CBCentralManager` to scan for devices
  - Filter for device names matching patterns from AI DVR Link (e.g., "LA518", "LA519", "L027")
  - Implement `BluetoothDevice` model with properties: `id`, `name`, `rssi`, `isConnected`
  - Add signal strength monitoring for connection quality

**Step 1.2: Bluetooth Device Connection Manager**
- **File:** `Sources/Bluetooth/DeviceConnectionManager.swift`
- **Purpose:** Handle pairing, connection state, reconnection logic
- **Implementation:**
  - Connect to selected device via CoreBluetooth
  - Discover services and characteristics
  - Handle connection state changes (connected, disconnected, failed)
  - Implement automatic reconnection on unexpected disconnect
  - Persist last connected device ID in UserDefaults

**Step 1.3: Audio Stream Receiver (Live Recording)**
- **File:** `Sources/Bluetooth/AudioStreamReceiver.swift`
- **Purpose:** Receive real-time audio from external mic via BLE notifications
- **Implementation:**
  - Identify BLE characteristics for audio data (need to reverse-engineer from AI DVR Link)
  - Subscribe to audio notifications/indications
  - Handle Opus-decompressed audio frames
  - Write incoming audio to temporary buffer/file
  - Support pause/resume streaming

**Step 1.4: Device File Sync (Saved Recordings)**
- **File:** `Sources/Bluetooth/DeviceFileSyncService.swift`
- **Purpose:** Enumerate and download recordings stored on external mic's flash
- **Implementation:**
  - Implement BLE protocol for file listing (discover recordings)
  - Transfer audio files from device to iPhone
  - Support progress tracking for large file transfers
  - Handle file format conversion if needed

**Step 1.5: Microphone Settings UI**
- **File:** `Sources/UI/DeviceSettingsView.swift`
- **Purpose:** Frontend for device pairing and management
- **Implementation:**
  - Device scanning and selection UI
  - Connection status indicator
  - Battery level display (if available via BLE)
  - "Sync Recordings" button for file transfer
  - Settings for audio quality preferences

---

### Phase 2: Voice Activity Detection (VAD) - Real-time Pipeline

#### Goal
Integrate Silero VAD (already included in FluidAudio) into the real-time recording pipeline to detect speech segments and trigger noise suppression.

#### Dependencies
- **FluidAudio** - Already in use, contains `VadManager` for Silero VAD

#### Implementation Steps

**Step 2.1: VAD Service Wrapper**
- **File:** `Sources/Audio/VADService.swift`
- **Purpose:** Wrap FluidAudio's VadManager for real-time use
- **Implementation:**
  - Initialize `VadManager` with appropriate config (16kHz, 256ms chunks)
  - Implement streaming API for chunk-by-chunk processing
  - Configure thresholds: `defaultThreshold: 0.75`, `minSpeechDuration: 0.25s`
  - Return speech probability and speech start/end events

**Step 2.2: Real-time VAD Processor**
- **File:** `Sources/Audio/RealTimeVADProcessor.swift`
- **Purpose:** Process audio chunks from recorder in real-time
- **Implementation:**
  - Receive audio chunks from AudioRecorder (or Bluetooth stream)
  - Feed chunks to VADService (downsampled to 16kHz)
  - Emit speech segment events to downstream processors
  - Track speech/silence state with hysteresis

**Step 2.3: VAD State Manager**
- **File:** `Sources/Audio/VADStateManager.swift`
- **Purpose:** Manage VAD state across recording session
- **Implementation:**
  - Track current state: `idle`, `speechDetected`, `silence`
  - Provide callbacks for state changes
  - Buffer audio during silence for gapless recording

---

### Phase 3: Noise Suppression (Koala by Picovoice)

#### Goal
Implement real-time noise suppression that activates when VAD detects speech, reducing background noise like hums.

#### Dependencies to Add
- **Koala iOS SDK** - Via CocoaPods or SPM from Picovoice
  - Requires: Picovoice account and access key
  - Minimum iOS 16.0+

#### Implementation Steps

**Step 3.1: Koala Noise Suppression Service**
- **File:** `Sources/Audio/KoalaNoiseSuppressor.swift`
- **Purpose:** Wrap Picovoice Koala SDK for real-time noise suppression
- **Implementation:**
  - Initialize Koala with access key (placeholder for user's key)
  - Configure for real-time streaming mode
  - Process audio chunks (16kHz mono, 16-bit PCM)
  - Output denoised audio chunks
  - Handle frame sizes appropriate for Koala (typically 512 samples)

**Step 3.2: VAD-Triggered NS Pipeline**
- **File:** `Sources/Audio/VADTriggeredNoiseSuppressor.swift`
- **Purpose:** Activate noise suppression only when voice is detected
- **Implementation:**
  - Connect VAD output to Koala input
  - When VAD probability > threshold: enable NS, pass audio through
  - When VAD probability < threshold: could bypass NS or keep minimal processing
  - Implement smooth transition (no clicks/pops)

**Step 3.3: NS Configuration UI**
- **File:** `Sources/UI/NoiseSuppressionSettingsView.swift`
- **Purpose:** Allow user to configure NS behavior
- **Implementation:**
  - Enable/disable toggle
  - Sensitivity level (if Koala supports)
  - "Activate on voice detection" toggle (default: on)

---

### Phase 4: Speaker Diarization Replacement

#### Goal
Replace current FluidAudio diarization with the dedicated speaker-diarization-coreml package (or verify if FluidAudio's implementation is sufficient).

#### Dependencies
- **FluidAudio** - Already in use (contains diarization)
- May need to add: `FluidInference/speaker-diarization-coreml` if newer model available

#### Implementation Steps

**Step 4.1: Verify Diarization Model Version**
- Check FluidAudio's current diarization model version
- Compare with `speaker-diarization-coreml` on HuggingFace
- Determine if replacement provides significant improvement

**Step 4.2: Enhanced Diarization Service (if needed)**
- **File:** `Sources/ML/EnhancedDiarizationService.swift`
- **Purpose:** Use newer/better diarization model
- **Implementation:**
  - Load `speaker-diarization-coreml` model directly if newer
  - Configure for optimal speaker count detection (1-8 speakers)
  - Implement segment refinement if needed

**Step 4.3: Integrate with InferencePipeline**
- **File:** `Sources/ML/InferencePipeline.swift`
- **Modification:**
  - Replace `DiarizationService` with new implementation
  - Ensure output format compatibility with transcription stage

---

### Phase 5: Modular ML Pipeline Architecture

#### Goal
Create a modular, replaceable audio processing pipeline with proper sample rate handling and component isolation.

#### Architecture Design

```
┌────────────────────────────────────────────────────────────────────┐
│                        INPUT SOURCE                                 │
│   (iPhone Microphone OR External Bluetooth Mic)                   │
└────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌────────────────────────────────────────────────────────────────────┐
│                  AUDIO PREPROCESSOR CHAIN                          │
│  ┌─────────────────┐    ┌─────────────────┐    ┌───────────────┐  │
│  │ SampleRateConverter│ -> │ AudioBuffer   │ -> │ FormatAdapter │  │
│  │ (48kHz→16kHz)   │    │ (Ring Buffer)  │    │ (Float32)     │  │
│  └─────────────────┘    └─────────────────┘    └───────────────┘  │
└────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌────────────────────────────────────────────────────────────────────┐
│                   REAL-TIME PROCESSING BRANCH                      │
│  ┌─────────────┐    ┌──────────────────┐    ┌─────────────────┐   │
│  │   VAD      │ -> │ NoiseSuppressor  │ -> │ Audio Recorder │   │
│  │ (Silero)   │    │ (Koala)          │    │ (.m4a file)    │   │
│  └─────────────┘    └──────────────────┘    └─────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌────────────────────────────────────────────────────────────────────┐
│                  POST-PROCESSING PIPELINE                          │
│  ┌─────────────┐    ┌────────────────┐    ┌─────────────────────┐   │
│  │  VAD       │ -> │ Speaker        │ -> │   ASR              │   │
│  │ (Segment)  │    │ Diarization    │    │ (Parakeet)         │   │
│  └─────────────┘    └────────────────┘    └─────────────────────┘   │
│         │                   │                       │                 │
│         └───────────────────┴───────────────────────┘                 │
│                           │                                         │
│                           ▼                                         │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                    LLM Summarization                           │ │
│  │                    (Llama 3.2-3B)                              │ │
│  └────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

#### Implementation Steps

**Step 5.1: Audio Preprocessing Protocol**
- **File:** `Sources/Audio/Protocols/AudioProcessor.swift`
- **Purpose:** Define protocol for all audio processors
- **Implementation:**
  ```swift
  protocol AudioProcessor {
      var inputSampleRate: Double { get }
      var outputSampleRate: Double { get }
      func process(_ samples: [Float]) async throws -> [Float]
      func flush() async throws -> [Float]
  }
  ```

**Step 5.2: Sample Rate Converter**
- **File:** `Sources/Audio/SampleRateConverter.swift`
- **Purpose:** Modular downsampling service (48kHz → 16kHz)
- **Implementation:**
  - Use AVFoundation's `AVAudioConverter` for high-quality resampling
  - Configurable input/output sample rates
  - Support for both real-time and offline processing
  - Position: FIRST in the pipeline (before VAD)

**Step 5.3: Audio Buffer (Ring Buffer)**
- **File:** `Sources/Audio/AudioRingBuffer.swift`
- **Purpose:** Thread-safe buffer for streaming audio
- **Implementation:**
  - Lock-free ring buffer for real-time audio
  - Configurable buffer size
  - Support multiple consumers (VAD, NS, recorder)

**Step 5.4: Format Adapter**
- **File:** `Sources/Audio/FormatAdapter.swift`
- **Purpose:** Convert between audio formats (Int16 ↔ Float32, mono ↔ stereo)
- **Implementation:**
  - Convert PCM formats for different ML model requirements
  - Normalize amplitude

**Step 5.5: Pipeline Orchestrator**
- **File:** `Sources/Audio/AudioPipelineOrchestrator.swift`
- **Purpose:** Wire together all pipeline components
- **Implementation:**
  - Register processors in desired order
  - Handle flow control between processors
  - Support enabling/disabling individual stages
  - Provide metrics/monitoring

**Step 5.6: Processor Registry**
- **File:** `Sources/Audio/ProcessorRegistry.swift`
- **Purpose:** Enable runtime swapping of processors
- **Implementation:**
  - Register processors by type/identifier
  - Allow hot-swapping (e.g., different VAD implementations)
  - Support configuration persistence

---

## Task Breakdown Summary

### Phase 1: External Microphone (Tasks 1.1 - 1.5)
1. `BluetoothDeviceScanner.swift` - BLE device discovery
2. `DeviceConnectionManager.swift` - Connection handling
3. `AudioStreamReceiver.swift` - Live audio streaming via BLE
4. `DeviceFileSyncService.swift` - File transfer from mic flash storage
5. `DeviceSettingsView.swift` - Device pairing UI

### Phase 2: VAD Integration (Tasks 2.1 - 2.3)
1. `VADService.swift` - Wrap FluidAudio VadManager
2. `RealTimeVADProcessor.swift` - Real-time VAD processing
3. `VADStateManager.swift` - VAD state tracking

### Phase 3: Noise Suppression (Tasks 3.1 - 3.3)
1. `KoalaNoiseSuppressor.swift` - Picovoice Koala integration
2. `VADTriggeredNoiseSuppressor.swift` - VAD-NS coupling
3. `NoiseSuppressionSettingsView.swift` - NS settings UI

### Phase 4: Speaker Diarization (Tasks 4.1 - 4.3)
1. Verify model versions between FluidAudio and speaker-diarization-coreml
2. `EnhancedDiarizationService.swift` - New/improved diarization
3. Update `InferencePipeline.swift` integration

### Phase 5: Modular Pipeline (Tasks 5.1 - 5.6)
1. `AudioProcessor.swift` - Processor protocol definition
2. `SampleRateConverter.swift` - Modular downsampling
3. `AudioRingBuffer.swift` - Thread-safe buffer
4. `FormatAdapter.swift` - Format conversion
5. `AudioPipelineOrchestrator.swift` - Pipeline wiring
6. `ProcessorRegistry.swift` - Runtime processor swapping

---

## Dependencies Summary

### Already in Project
- **FluidAudio** - ASR (Parakeet), Diarization (OfflineDiarizer), VAD (Silero)
- **LLM.swift** - Llama inference
- **SwiftData** - Persistence
- **AVFoundation** - Audio recording/playback

### To Add
- **Picovoice Koala** - Noise suppression (requires access key from user)
- **RxBluetoothKit** - Optional, for reactive BLE (can use CoreBluetooth directly)

---

## Notes for Implementation

1. **Memory Management:** Maintain the sequential loading strategy - load each model, process, then unload before next stage
2. **Sample Rate Strategy:** Downsample to 16kHz early (before VAD) as per user preference - this is optimal for both Silero VAD and Koala
3. **Real-time Latency:** Target <100ms end-to-end for the recording → VAD → NS pipeline
4. **Koala Access Key:** Placeholder in code until user provides their Picovoice access key
5. **BLE Protocol:** Exact characteristics for audio streaming need extraction from AI DVR Link binary (初步识别: custom voice engine plugin with Opus codec)

---

## File Structure After Implementation

```
Scribe/Scribe/Sources/
├── Audio/
│   ├── AudioRecorder.swift (existing, enhanced)
│   ├── AudioConverter.swift (existing)
│   ├── SampleRateConverter.swift (NEW)
│   ├── AudioRingBuffer.swift (NEW)
│   ├── FormatAdapter.swift (NEW)
│   ├── AudioPipelineOrchestrator.swift (NEW)
│   ├── ProcessorRegistry.swift (NEW)
│   ├── Protocols/
│   │   └── AudioProcessor.swift (NEW)
│   ├── VAD/
│   │   ├── VADService.swift (NEW)
│   │   ├── RealTimeVADProcessor.swift (NEW)
│   │   └── VADStateManager.swift (NEW)
│   └── NoiseSuppression/
│       ├── KoalaNoiseSuppressor.swift (NEW)
│       └── VADTriggeredNoiseSuppressor.swift (NEW)
├── Bluetooth/
│   ├── BluetoothDeviceScanner.swift (NEW)
│   ├── DeviceConnectionManager.swift (NEW)
│   ├── AudioStreamReceiver.swift (NEW)
│   └── DeviceFileSyncService.swift (NEW)
├── ML/
│   ├── InferencePipeline.swift (existing, modified)
│   ├── TranscriptionService.swift (existing)
│   ├── EnhancedDiarizationService.swift (NEW or modified)
│   └── LLMService.swift (existing)
├── Models/
│   └── Recording.swift (existing)
└── UI/
    ├── DeviceSettingsView.swift (NEW)
    ├── NoiseSuppressionSettingsView.swift (NEW)
    └── ... (existing)
```

---

*This plan was designed for modular, iterative implementation. Each phase can be developed and tested independently before integration.*
