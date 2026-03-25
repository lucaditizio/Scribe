# Scribe

A privacy-first AI voice memo app for iPhone 15 Plus. Scribe captures high-quality audio, generates diarized transcripts, structured meeting notes, and mind maps — entirely on-device using a strictly sequential ML pipeline designed to fit within 6 GB of RAM.

---

## Table of Contents

- [Vision](#vision)
- [Hardware Target](#hardware-target)
- [Architecture Overview](#architecture-overview)
- [Project Structure](#project-structure)
- [ML Model Stack](#ml-model-stack)
- [Inference Pipeline](#inference-pipeline)
- [Audio Engine](#audio-engine)
- [Data Model](#data-model)
- [UI Layer](#ui-layer)
- [Design System](#design-system)
- [Feature Roadmap](#feature-roadmap)

---

## Vision

Scribe is a premium, privacy-first alternative to the Plaud/AI DVR ecosystem. Every recording is processed locally — no data leaves the device. The app is designed around a clean Plaud-inspired UI with a prominent record button, card-based recording list, and a rich detail view for playback and AI-generated notes.

---

## Hardware Target

| Property | Spec |
|---|---|
| Device | iPhone 15 Plus |
| RAM | 6 GB |
| Processor | A16 Bionic (16-core Neural Engine) |
| Input | External 2.4 GHz wireless mic via USB-C receiver |

### Memory Management Strategy

**Strictly Sequential Batch Processing.** No two large ML models coexist in RAM. Each pipeline stage loads its model, runs inference, then nullifies all references (triggering `deinit`) before the next stage begins. This keeps peak usage within safe bounds on a 6 GB device.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                     SwiftUI Layer                   │
│  RecordingListView → RecordingDetailView            │
│  AgentGeneratingView  WaveformView  MindMapView     │
└───────────────┬─────────────────────────────────────┘
                │ @Observable bindings
┌───────────────▼─────────────────────────────────────┐
│               Service / Orchestration Layer         │
│  AudioRecorder   AudioPlayer   WaveformAnalyzer     │
│  InferencePipeline (orchestrates ML stages)         │
└───────────────┬─────────────────────────────────────┘
                │ Sequential load → run → unload
┌───────────────▼─────────────────────────────────────┐
│               ML Layer                              │
│  DiarizationService  (FluidAudio / OfflineDiarizer) │
│  TranscriptionService (FluidAudio / Parakeet ASR)   │
│  LLMService           (llama.cpp / Llama 3.2-3B)    │
└───────────────┬─────────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────┐
│               Persistence Layer                     │
│  SwiftData  ·  Recording  @Model                    │
│  Audio files: .m4a  in  Documents/                  │
└─────────────────────────────────────────────────────┘
```

---

## Project Structure

```
Scribe/
├── PLAN.md                         # Product vision, model stack, phased roadmap
├── README.md
└── Scribe/
    └── Scribe/
        ├── ScribeApp.swift          # @main entry point; SwiftData ModelContainer
        ├── Assets.xcassets/
        └── Sources/
            ├── Audio/
            │   ├── AudioRecorder.swift   # AVAudioEngine-based recorder; USB-C Plug & Play
            │   ├── AudioPlayer.swift     # Playback; 1×/1.5×/2× speed; ±15 s skip
            │   ├── AudioConverter.swift  # Converts .m4a → [Float32] at 16 kHz for ASR
            │   └── WaveformAnalyzer.swift # AVAssetReader; downsamples to 50 bars
            ├── ML/
            │   ├── InferencePipeline.swift # Orchestrator: diarize → transcribe → summarize
            │   └── LLMService.swift        # Llama 3.2-3B; single-pass & map-refine strategies
            ├── Models/
            │   └── Recording.swift         # SwiftData @Model
            └── UI/
                ├── RecordingListView.swift  # Home screen; card list; record button
                ├── RecordingDetailView.swift # Playback + Transcript/Summary/Mind Map tabs
                ├── RecordingCardView.swift   # Card component for list
                ├── RecordButtonView.swift    # Animated red circular record button
                ├── AgentGeneratingView.swift # iOS 18 mesh-gradient "Generating" screen
                ├── DashboardHeaderView.swift # Usage meters (Plaud-style header)
                └── Theme.swift              # Centralized color palette & card style
```

---

## ML Model Stack

| Stage | Model | Framework | Precision | Peak RAM |
|---|---|---|---|---|
| **Speaker Diarization** | TitaNet-Small (via FluidAudio `OfflineDiarizer`) | CoreML | FP16 (ANE) | ~0.8 GB |
| **ASR Transcription** | NVIDIA Parakeet-TDT-0.6B-v3 (via FluidAudio `AsrManager`) | CoreML | Mixed (ANE) | ~1.3 GB |
| **Summarization** | Llama-3.2-3B-Instruct-Q4\_K\_M.gguf (via llama.cpp Swift) | llama.cpp | 4-bit | ~2.1 GB |

Models are loaded on-demand and immediately set to `nil` after use. Peak combined usage never exceeds ~2.1 GB at any single point.

---

## Inference Pipeline

`InferencePipeline` (`Sources/ML/InferencePipeline.swift`) is the central `@Observable` orchestrator. It drives four sequential stages:

### Stage 1 — Diarization
`DiarizationService` uses `OfflineDiarizerManager` with a clustering threshold of `0.35` and a 1–8 speaker bound. Produces `[SpeakerSegment]` with `speakerId`, `start`, and `end` timestamps. Falls back to a single "Speaker 1" segment on failure.

### Stage 2 — Audio Loading
`AudioConverter.convertToFloat32` decodes the `.m4a` file into a `[Float]` buffer at 16 kHz, used as the ASR input.

### Stage 3 — Segmented Transcription
`TranscriptionService` wraps `AsrManager` (Parakeet). The float buffer is sliced per diarization segment and transcribed individually. Output is assembled as `[Speaker N - MM:SS]\n<text>` blocks. Segments shorter than 0.5 seconds are silently skipped.

### Stage 4 — LLM Summarization
`LLMService` runs Llama-3.2-3B with a custom Llama 3 chat template. It auto-routes by transcript length:

- **Single-pass** (≤ 25,000 chars / ~35 min): one synthesis prompt produces the full `MeetingSummary` JSON.
- **Map → Refine** (> 25,000 chars): the transcript is split into 12,000-char chunks with 10% overlap, each chunk yielding a mini-summary, then a final synthesis pass merges them.

The model is downloaded from Hugging Face on first use and cached in `Documents/`.

#### Structured Output

`LLMService` decodes the model's raw output into:

```swift
struct MeetingSummary: Codable {
    let title: String           // 2-4 word auto-generated title
    let meetingNotes: [TopicSection] // [{ topic, bullets }]
    let actionItems: String     // Markdown bullet list with speaker owners
    let mindMapNodes: [MindMapNode]  // Recursive JSON tree
}
```

---

## Audio Engine

### `AudioRecorder`
- Format: **MPEG-4 AAC, 48 kHz, mono, High Quality**
- Session category: `.playAndRecord` with `.allowBluetooth` and `.defaultToSpeaker`
- **USB-C Plug & Play**: listens for `AVAudioSession.routeChangeNotification` and automatically sets the preferred input to any arriving `usbAudio` or `headsetMic` port
- Haptic feedback (`UIImpactFeedbackGenerator`) on every record start/stop
- Files saved as `<UUID>.m4a` in the app's `Documents/` directory

### `AudioPlayer`
- Wraps `AVAudioPlayer` with an `@Observable` state
- Playback speed cycling: **1.0× → 1.5× → 2.0× → 1.0×**
- Skip: **±15 seconds**
- Seek: scrubbing via `WaveformView` progress tap
- Session deactivated cleanly on finish or dismiss

### `WaveformAnalyzer`
- Uses `AVAssetReader` to decode raw PCM (Int16) from the audio file on a detached background task
- Downsamples to **50 bars** by peak-per-bin, then normalizes to `[0.05, 1.0]`
- Drives the animated `WaveformView` bar chart in `RecordingDetailView`

---

## Data Model

`Recording` (`Sources/Models/Recording.swift`) is the single SwiftData `@Model`:

| Property | Type | Notes |
|---|---|---|
| `id` | `String` (unique) | UUID; also the filename stem of the `.m4a` file |
| `title` | `String` | Auto-set by LLM; editable |
| `createdAt` | `Date` | |
| `duration` | `TimeInterval` | |
| `audioFilePath` | `String` | Relative path inside `Documents/` |
| `categoryTag` | `String` | Default `#NOTE`; e.g. `#MEETING`, `#INTERVIEW` |
| `rawTranscript` | `String?` | Diarized, speaker-tagged transcript |
| `meetingNotes` | `String?` | JSON-encoded `[TopicSection]` |
| `actionItems` | `String?` | Markdown bullet list |
| `mindMapJSON` | `Data?` | JSON-encoded `[MindMapNode]` |

The `ModelContainer` is initialized in `ScribeApp` with on-disk persistence and injected via `.modelContainer()`.

---

## UI Layer

### `RecordingListView`
Home screen. Displays all recordings as `RecordingCardView` cards sorted by `createdAt`. A prominent **red circular record button** (`RecordButtonView`) is pinned to the bottom center. Tapping it creates a new `Recording` in SwiftData and starts `AudioRecorder`.

### `RecordingDetailView`
Split-panel detail view:

- **Top panel**: `WaveformView` (real-time progress bar), playback controls (skip, play/pause, speed), and a scrubber
- **Bottom panel**: segmented picker switching between **Summary**, **Transcript**, and **Mind Map** tabs
- **Floating CTA**: "Generate Transcript" button (red capsule) appears when no transcript exists and inference is idle

#### Transcript Tab
`TranscriptInteractiveView` parses the `[Speaker N - MM:SS]` format into structured segments. Tapping a speaker label opens a **Rename Participant** alert that globally replaces the speaker ID in both the transcript and action items.

#### Summary Tab
Renders `[TopicSection]` as headed lists with speaker-attributed action items below.

#### Mind Map Tab
`MindMapView` recursively renders `[MindMapNode]` into an indented tree with branch connectors.

### `AgentGeneratingView`
iOS 18+ animated mesh-gradient "Generating" screen displayed during inference. Uses a `ProgressView` overlay with the current pipeline step description.

---

## Design System

`Theme.swift` defines all visual tokens used throughout the app:

| Token | Value |
|---|---|
| `scribeRed` | `rgb(0.9, 0.2, 0.2)` — primary accent |
| `obsidian` | `rgb(0.1, 0.1, 0.11)` — dark mode background |
| `cornerRadius` | `20 pt` (squircle cards) |
| `shadowRadius` | `10 pt` |
| Color scheme | Dark mode forced via `.preferredColorScheme(.dark)` in `ScribeApp` |

The `.scribeCardStyle(scheme:)` view modifier applies consistent card styling (background, rounded corners, shadow) across all panel components.

---

## Feature Roadmap

| Phase | Status | Description |
|---|---|---|
| 1 — Core UI & Audio | ✅ | Recording list, card UI, `AVAudioEngine`, USB-C Plug & Play, SwiftData |
| 2 — Playback & Inference | ✅ | Waveform visualization, playback controls, diarization + ASR pipeline |
| 3 — Meeting Mode & Agent | ✅ | Llama-3.2 summarization, action items, mind map, mesh-gradient generating view |
| 4 — Apple Notes Export | 🔜 | `AppIntent` to export a Markdown-formatted note per recording to Apple Notes |
