# Scribe Implementation - Task List for qwen3.5-35B-A3B

## Quick Reference

- **Target Device:** iPhone 15 Plus (6GB RAM, A16 Bionic)
- **Current Stack:** SwiftUI + SwiftData + FluidAudio + Llama.cpp
- **Goal:** Add Bluetooth mic integration, VAD-triggered noise suppression, modular ML pipeline

---

## Phase 1: External Bluetooth Microphone

### Task 1.1: BLE Device Scanner
```
File: Sources/Bluetooth/BluetoothDeviceScanner.swift
- Implement CBCentralManager-based device discovery
- Filter by device names: LA518, LA519, L027, L813, L815, L816, L817, MAR-2518
- Return BluetoothDevice struct with id, name, rssi
```

### Task 1.2: Device Connection Manager
```
File: Sources/Bluetooth/DeviceConnectionManager.swift
- CoreBluetooth connection to selected device
- Service/characteristic discovery
- Connection state management + auto-reconnect
- Persist last device in UserDefaults
```

### Task 1.3: Live Audio Stream Receiver
```
File: Sources/Bluetooth/AudioStreamReceiver.swift
- Subscribe to BLE audio notifications
- Decode Opus audio frames (see AIDvrLinkOpusPlugin in AI_DVR_Link)
- Write to buffer for real-time processing
- Support pause/resume
```

### Task 1.4: Device File Sync
```
File: Sources/Bluetooth/DeviceFileSyncService.swift
- Enumerate recordings on mic flash storage via BLE
- Transfer files to iPhone Documents/
- Progress tracking for large files
```

### Task 1.5: Device Settings UI
```
File: Sources/UI/DeviceSettingsView.swift
- Device scan/pair UI
- Connection status indicator
- "Sync Recordings" button
- Battery display (if available)
```

---

## Phase 2: Voice Activity Detection (Real-time)

### Task 2.1: VAD Service Wrapper
```
File: Sources/Audio/VAD/VADService.swift
- Wrap FluidAudio VadManager (Silero VAD v6)
- Configure: 16kHz, 256ms chunks, threshold 0.75
- Implement streaming process() for real-time chunks
- Return VadResult with probability and speech events
```

### Task 2.2: Real-time VAD Processor
```
File: Sources/Audio/VAD/RealTimeVADProcessor.swift
- Receive audio chunks from recorder
- Downsample to 16kHz using SampleRateConverter
- Feed to VADService
- Emit speech start/end events
```

### Task 2.3: VAD State Manager
```
File: Sources/Audio/VAD/VADStateManager.swift
- Track states: idle, speechDetected, silence
- Provide state change callbacks
- Buffer audio during silence states
```

---

## Phase 3: Noise Suppression (Koala)

### Task 3.1: Koala Integration
```
File: Sources/Audio/NoiseSuppression/KoalaNoiseSuppressor.swift
- Initialize Picovoice Koala SDK (use placeholder key: "YOUR_ACCESS_KEY")
- Configure: 16kHz mono, streaming mode
- Process 512-sample chunks
- Output denoised Float32 audio
```

### Task 3.2: VAD-Triggered NS
```
File: Sources/Audio/NoiseSuppression/VADTriggeredNoiseSuppressor.swift
- Connect VAD probability output to Koala enable/disable
- When VAD > threshold: enable NS, pass audio through
- When VAD < threshold: bypass or minimal processing
- Smooth transitions (no clicks)
```

### Task 3.3: NS Settings UI
```
File: Sources/UI/NoiseSuppressionSettingsView.swift
- Enable/disable toggle
- Sensitivity level
- "Activate on voice" toggle
```

---

## Phase 4: Speaker Diarization

### Task 4.1: Model Version Check
```
Action: Compare FluidAudio/OfflineDiarizer model version
       with FluidInference/speaker-diarization-coreml on HuggingFace
Result: Determine if replacement provides improvement
```

### Task 4.2: Enhanced Diarization Service
```
File: Sources/ML/EnhancedDiarizationService.swift
(if newer model available):
- Load speaker-diarization-coreml model directly
- Configure: minSpeakers=1, maxSpeakers=8
- Return SpeakerSegment[] with timestamps
- Integrate with InferencePipeline
```

---

## Phase 5: Modular Pipeline

### Task 5.1: AudioProcessor Protocol
```
File: Sources/Audio/Protocols/AudioProcessor.swift
protocol AudioProcessor {
    var inputSampleRate: Double { get }
    var outputSampleRate: Double { get }
    func process(_ samples: [Float]) async throws -> [Float]
    func flush() async throws -> [Float]
}
```

### Task 5.2: SampleRateConverter
```
File: Sources/Audio/SampleRateConverter.swift
- Use AVAudioConverter for high-quality resampling
- Configurable: 48000 → 16000 (or other rates)
- Implement AudioProcessor protocol
- FIRST processor in pipeline (before VAD)
```

### Task 5.3: Ring Buffer
```
File: Sources/Audio/AudioRingBuffer.swift
- Thread-safe lock-free ring buffer
- Configurable size for streaming
- Multiple consumer support
```

### Task 5.4: Format Adapter
```
File: Sources/Audio/FormatAdapter.swift
- Convert Int16 ↔ Float32 PCM
- Mono/stereo handling
- Implement AudioProcessor protocol
```

### Task 5.5: Pipeline Orchestrator
```
File: Sources/Audio/AudioPipelineOrchestrator.swift
- Register processors in order: SRC → VAD → NS → Recorder
- Handle flow control between stages
- Enable/disable stages at runtime
- Provide metrics
```

### Task 5.6: Processor Registry
```
File: Sources/Audio/ProcessorRegistry.swift
- Register processors by type identifier
- Allow runtime swapping (e.g., VAD implementations)
- Persist configuration
```

---

## Integration: Update InferencePipeline

```
File: Sources/ML/InferencePipeline.swift (MODIFY)
Changes:
1. Replace DiarizationService with EnhancedDiarizationService
2. Ensure AudioConverter uses new SampleRateConverter
3. Add VAD segmentation for cleaner ASR input
4. Maintain sequential load → process → unload pattern
```

---

## Architecture Summary

```
INPUT → [SampleRateConverter: 48kHz→16kHz] → [VAD: Silero] → [NS: Koala] → [Recorder]
                                              ↑
                                              │
INPUT → [SampleRateConverter] → [VAD Segment] → [Diarization] → [ASR: Parakeet] → [LLM]
```

---

## Dependencies

### Already Available
- FluidAudio (VAD, Diarization, ASR)
- LLM.swift (Llama inference)
- SwiftData, AVFoundation

### To Add
- Picovoice Koala SDK (CocoaPods/SPM)
  - Requires access key: user will provide
- CoreBluetooth (native iOS framework)

---

## Memory Constraint

Maintain strict sequential processing:
- Only ONE ML model in RAM at a time
- Load model → process → unload → next stage
- Target peak <2.1GB for entire pipeline

---

*Execute tasks in order. Test each phase before proceeding to next.*
