# Scribe — Complete Rebuild from Scratch (VIPER Architecture)

## TL;DR

> **Quick Summary**: Rebuild the entire Scribe iOS app from scratch using VIPER clean architecture (full granularity, strict View passivity, Router per module), eliminating all code quality issues while preserving exact UI look/feel, proprietary BLE SLink microphone protocol, and enhancing the ML pipeline with VAD, Swiss German ASR, and config-driven model swapping.
>
> **Deliverables**:
> - Complete iOS app (single Xcode target, ~60+ Swift files in VIPER module structure)
> - 8 VIPER modules: RecordingList, RecordingDetail, WaveformPlayback, Transcript, Summary, MindMap, AgentGenerating, DeviceSettings
> - Shared Services layer: BLE, Audio, ML, Recording
> - Core layer: Entities, Protocols, Config, Infrastructure
> - BLE SLink protocol preserved exactly (proprietary, reverse-engineered)
> - Unified Opus audio format for both internal and BLE microphones
> - ML pipeline: VAD → Language Detection → Swiss German Whisper ASR → Diarization → LLM Summary
> - Config-driven model swapping via PipelineConfig
> - Pixel-perfect UI match (Theme.swift, all animations, dark mode)
> - TDD test suite with 70%+ domain coverage
> - Updated README with current architecture
>
> **Estimated Effort**: Large
> **Parallel Execution**: YES — 6 waves
> **Critical Path**: Scaffolding → Core → Services → VIPER Modules → Views → App Wiring

---

## Context

### Original Request
User wants to rebuild Scribe from scratch because "the current application was pasted together over different, uncoordinated steps." Key concerns: code quality, clean file structure (eliminate Scribe/Scribe/Scribe nesting), unified audio format, optimized ML pipeline with VAD and language detection, while preserving UI look/feel and proprietary BLE logic.

### Interview Summary

**Key Discussions**:
- **Architecture**: VIPER clean architecture (The Book of VIPER, Rambler&Co adaptation) with full granularity modules, strict View passivity, and Router per module
- **Audio format**: Opus for both internal and BLE microphones (unified)
- **VAD**: FluidAudio's built-in VAD
- **ASR**: Swiss German Whisper CoreML (jlnslv/whisper-large-v3-turbo-swiss-german-coreml) as primary, fallback to general model
- **Language detection**: Use Whisper's built-in language confidence as classifier
- **Model swapping**: Config-driven via PipelineConfig
- **Module decomposition**: 8 modules (RecordingList, RecordingDetail, WaveformPlayback, Transcript, Summary, MindMap, AgentGenerating, DeviceSettings)
- **View passivity**: Strict — View ONLY renders Presenter state and forwards user actions. Zero business logic in View.
- **Router strategy**: Dedicated Router per module for navigation
- **Test strategy**: TDD with clear Xcode build/test strategy; human-in-the-loop for verification
- **Target iOS**: iOS 18+
- **Target device**: iPhone 15 Plus
- **Apple Notes export**: Removed from scope
- **BLE serial**: Hardcoded "129950" for now, architecture for dynamic extraction later
- **Local models**: Used for some tasks — tasks must be small (1-3 files), categories kept low
- **File exclusivity**: NO two parallel subagents may edit the same file

**Research Findings**:
- 23 current Swift files, triple nesting, 133 print statements, 1 test file
- BLE SLink: 8-step init, custom GATT services, Opus 16kHz mono, 4 source files
- ML pipeline: 4 sequential stages, peak ~2.1GB RAM on 6GB device
- UI: Theme.swift (5 colors), scribeCardStyle, dark mode forced, 6 main views
- Dependencies: FluidAudio, LLM.swift, swift-huggingface, swift-transformers, swift-opus, yyjson
- VIPER (Rambler&Co): Module = View + Interactor + Presenter + Entity + Router + Assembly; View passive; Interactor holds no state; Services injected into Interactors; ModuleInput/ModuleOutput for inter-module communication; DataDisplayManager for table/collection logic
- Xcode build: `xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus'` verified working

### Metis Review

**Identified Gaps (addressed)**:
- Missing acceptance criteria for ML stages → Added timeout, cancellation, progress tracking
- Scope creep risks → Explicitly locked out: real-time transcription, recording editing, export formats beyond current
- TDD concerns for BLE → Protocol-based mocking strategy defined
- VIPER layering → Full module structure with Assembly, Interactor, Presenter, Router per module
- Edge cases → BLE disconnect mid-recording, empty transcripts, app backgrounding during pipeline
- Guardrails → Zero print statements, no force unwraps, no empty catch blocks, max 400 lines per file
- File exclusivity → Explicit file lists per task, verified no overlap within parallel waves
- Local model task sizing → Tasks scoped to 1-3 files, categories kept at quick/unspecified-low where possible

---

## Work Objectives

### Core Objective
Rebuild Scribe from scratch with VIPER architecture, preserving all existing functionality while dramatically improving code quality, unifying audio format, and enhancing the ML pipeline.

### Concrete Deliverables
- ~60+ Swift files in VIPER module structure under single Xcode target
- 8 VIPER modules with full stacks (Assembly, Interactor, Presenter, Router, View)
- Shared Services layer (BLE, Audio, ML, Recording)
- Core layer (Entities, Protocols, Config, Infrastructure)
- BLE SLink protocol (exact copy of proprietary logic)
- Unified Opus audio recording pipeline
- Enhanced ML pipeline with VAD and Swiss German ASR
- Pixel-perfect UI match
- TDD test suite
- Updated README

### Definition of Done
- [ ] `xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' build` succeeds with zero errors
- [ ] `xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' test` passes all tests
- [ ] Zero print statements in production code
- [ ] Zero force unwraps (`!`) in production code
- [ ] Zero empty catch blocks
- [ ] All files under 400 lines
- [ ] All public APIs have documentation comments
- [ ] All magic numbers extracted to Config files
- [ ] BLE connection works with real hardware (human verification)
- [ ] Recording → ML pipeline → transcript/summary/mind map works end-to-end (human verification)
- [ ] All VIPER modules follow strict View passivity — no business logic in View layer

### Must Have
- Exact UI look/feel (colors, fonts, icons, animations, dark mode)
- Proprietary BLE SLink protocol (8-step init, custom GATT, Opus decode)
- Dual recording (internal mic + BLE mic) with unified Opus format
- ML pipeline: VAD → Language Detection → ASR → Diarization → LLM Summary
- Config-driven model swapping
- Speaker renaming post-diarization
- Overview screen with all recordings
- VIPER Architecture: 8 modules, each with Assembly + Interactor + Presenter + Router + View
- VIPER Strictness: View is passive (zero business logic), Interactor holds no state, Router handles navigation
- VIPER Communication: ModuleInput/ModuleOutput protocols for inter-module data passing
- TDD: Every module and service has unit tests
- Human-in-the-loop verification for integration and visual checks

### Must NOT Have (Guardrails)

**VIPER Architecture Violations:**
- **NO business logic in View** — View only renders Presenter state and forwards user actions to Presenter
- **NO direct service access from Presenter** — services accessed only through Interactor
- **NO direct service access from View** — View communicates only with Presenter
- **NO navigation logic in Presenter** — Presenter calls Router methods for all navigation
- **NO state in Interactor** — Interactor holds only dependencies (services + weak output reference)
- **NO framework-specific types crossing Interactor boundary** — Interactor returns plain Swift types, not CoreBluetooth/AVFoundation types
- **NO cross-module direct dependencies** — modules communicate only via ModuleInput/ModuleOutput protocols
- **NO View creating its own Presenter** — Assembly wires the entire module

**Code Quality:**
- **NO print statements** — use OSLog/ScribeLogger throughout
- **NO force unwraps** (`!`) — use guard/let or throw errors
- **NO empty catch blocks** — every catch must handle meaningfully
- **NO files over 400 lines** — split if approaching limit
- **NO magic numbers** — all constants in Config files

**Scope Boundaries:**
- **NO real-time transcription** — post-recording processing only
- **NO recording editing/trimming** — out of scope
- **NO Apple Notes export** — explicitly removed
- **NO file sync from device storage** — out of scope
- **NO cloud sync/sharing** — 100% on-device
- **NO modification of SLink protocol logic** — copy as-is, wrap behind protocols
- **NO BLE characteristic UUID changes** — E49A3001, E49A3003, F0F1-F0F4 are read-only
- **NO Core/Entity layer imports** of SwiftUI, CoreBluetooth, AVFoundation, or any framework

**Parallel Execution Safety:**
- **NO two parallel subagents editing the same file** — file exclusivity enforced per wave

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES (Xcode test target, XCTest)
- **Automated tests**: TDD (RED → GREEN → REFACTOR for every task)
- **Framework**: XCTest (iOS native, Xcode-integrated)
- **Test framework for new code**: Swift Testing framework (iOS 18+ compatible) where applicable
- **TDD workflow**: Each task creates failing test first, then minimal implementation, then refactor

### Human-in-the-Loop Policy
Human verification is wanted and valued. The user will guide, help, and check throughout.
- **TDD using unit tests** is always the first step for verification
- **Agent-executed QA scenarios** complement but do not replace human verification
- **BLE connection with real hardware** requires human manual verification
- **UI pixel-perfect match** benefits from human visual spot-checks
- **Integration testing** uses agent-executed scenarios with human review of results
- **Final Verification Wave** presents consolidated results to user for explicit approval

### Agent-Executed QA Policy
Every task MUST include agent-executed QA scenarios. Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **Build verification**: `xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' build`
- **Test verification**: `xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' test`
- **Frontend/UI**: XCUITest or screenshot comparison for native iOS
- **BLE**: Human verification required for real hardware (documented in QA scenarios)
- **ML Pipeline**: Integration tests with mock model outputs, smoke tests with real models on device

### TDD Agent Workflow Rules
1. **Build command is ALWAYS**: `xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus'`
2. **Test command is ALWAYS**: `xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' test`
3. **SourceKit-LSP errors are informational only** — agents must verify with actual xcodebuild, not LSP diagnostics
4. **If xcodebuild succeeds but LSP shows errors** — trust xcodebuild, ignore LSP
5. **If xcodebuild fails** — fix the build error, do not chase LSP ghosts
6. **Each test file must import XCTest** and be part of the ScribeTests target

---

## Execution Strategy

### VIPER Module Structure (Canonical Pattern)

Every VIPER module follows this structure. Each task creating a module must adhere to it:

```
Modules/{ModuleName}/
  Assembly/
    {ModuleName}Assembly.swift      — Creates and wires all module components
  Interactor/
    {ModuleName}Interactor.swift    — Business logic facade over Services
    {ModuleName}InteractorInput.swift   — Protocol: Presenter → Interactor
    {ModuleName}InteractorOutput.swift  — Protocol: Interactor → Presenter
  Presenter/
    {ModuleName}Presenter.swift     — @Observable mediator, holds module state
    {ModuleName}ViewOutput.swift    — Protocol: View → Presenter (user actions)
    {ModuleName}ViewInput.swift     — Protocol: Presenter → View (display updates)
    {ModuleName}ModuleInput.swift   — Protocol: External → Module (configuration)
    {ModuleName}ModuleOutput.swift  — Protocol: Module → External (results)
    {ModuleName}State.swift         — Plain state object (if state is complex)
  Router/
    {ModuleName}Router.swift        — Navigation between modules
    {ModuleName}RouterInput.swift   — Protocol: Presenter → Router
  View/
    {ModuleName}View.swift          — SwiftUI view (passive, renders Presenter state)
    {ModuleName}CellObject.swift    — Cell model for lists (if applicable)
```

**Reference binding conventions:**
- View holds **strong** reference to Presenter (called `output`)
- Presenter holds **weak** reference to View (called `view`)
- Presenter holds **strong** reference to Interactor (called `interactor`)
- Presenter holds **strong** reference to Router (called `router`)
- Interactor holds **weak** reference to Presenter (called `output`)
- Interactor holds **strong** references to Services

**Method naming conventions:**
- Action methods (imperative): `obtainRecordings()`, `processRecording()`, `startScan()`
- Completion methods (did prefix): `didObtainRecordings()`, `didProcessRecording()`, `didFailWithError()`
- Router methods: `openRecordingDetail()`, `closeCurrentModule()`, `embedWaveformPlayback()`

### Parallel Execution Waves

```
Wave 1 (Start Immediately — Foundation, 7 tasks):
├── Task 1: Project scaffolding + Xcode project + SPM + VIPER folder structure [quick]
├── Task 2: Config layer (PipelineConfig, AudioConfig, BluetoothConfig, FeatureFlags) [quick]
├── Task 3: Infrastructure layer (ScribeLogger, Extensions, SwiftDataModelContainer) [quick]
├── Task 4: Core entities (Recording, Transcript, MeetingSummary, MindMapNode, AudioSample, RecordingSource) [quick]
├── Task 5: Core protocols (Service protocols + VIPER base protocols) [quick]
├── Task 6: Shared UI — Theme + Design Tokens + Spacing + Typography [quick]
└── Task 7: AppAssembly skeleton + service registration [quick]

Wave 2 (After Wave 1 — BLE + Audio Services, 8 tasks):
├── Task 8: BLE — SLink Protocol files (copy as-is, wrap behind protocol) [quick]
├── Task 9: BLE — Device Scanner (BluetoothDevice, BluetoothDeviceScanner) [unspecified-low]
├── Task 10: BLE — Connection Manager (DeviceConnectionManager, ConnectionStateMachine, SLinkInitOrchestrator, KeepAliveService) [unspecified-high]
├── Task 11: BLE — Audio Stream Receiver + Opus Decoder [unspecified-low]
├── Task 12: Audio — Internal Mic Recorder + Opus Encoder [unspecified-high]
├── Task 13: Audio — Unified Recorder + Recording Orchestrator [unspecified-low]
├── Task 14: Audio — Player + Waveform Analyzer + Audio Converter [unspecified-low]
└── Task 15: Recording Repository (SwiftData) [quick]

Wave 3 (After Wave 2 — ML Services, 5 tasks):
├── Task 16: ML — VAD Service [unspecified-low]
├── Task 17: ML — Language Detector [unspecified-low]
├── Task 18: ML — Swiss German Whisper ASR + Fallback ASR [unspecified-high]
├── Task 19: ML — Diarization Service [unspecified-low]
└── Task 20: ML — LLM Summarization + Inference Pipeline + Progress Tracker [unspecified-high]

Wave 4 (After Wave 3 — VIPER Module Stacks, 8 tasks):
├── Task 21: RecordingListModule stack [unspecified-low]
├── Task 22: RecordingDetailModule stack [unspecified-low]
├── Task 23: WaveformPlaybackModule stack [quick]
├── Task 24: TranscriptModule stack [unspecified-low]
├── Task 25: SummaryModule stack [quick]
├── Task 26: MindMapModule stack [quick]
├── Task 27: AgentGeneratingModule stack [quick]
└── Task 28: DeviceSettingsModule stack [unspecified-low]

Wave 5 (After Wave 4 — Views, 6 tasks):
├── Task 29: RecordingListModule Views (ListView, CardView, RecordButtonView) [visual-engineering]
├── Task 30: RecordingDetail + WaveformPlayback Views [visual-engineering]
├── Task 31: Transcript + Summary Views [visual-engineering]
├── Task 32: MindMap View [visual-engineering]
├── Task 33: AgentGenerating View [visual-engineering]
└── Task 34: DeviceSettings Views [visual-engineering]

Wave 6 (After Wave 5 — App Wiring + Integration, 3 tasks):
├── Task 35: App Wiring (ScribeApp.swift + AppAssembly + NavigationStack) [unspecified-low]
├── Task 36: Integration — Error handling + edge cases + end-to-end tests [unspecified-high]
└── Task 37: Documentation — README + code documentation [writing]

Wave FINAL (After ALL tasks — 4 parallel reviews, then user okay):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Real manual QA (unspecified-high)
└── Task F4: Scope fidelity check (deep)
→ Present results → Get explicit user okay
```

### Dependency Matrix

| Task | Blocked By | Blocks |
|------|-----------|--------|
| 1-7 | None | 8-20 |
| 8 | 5 | 10, 11 |
| 9 | 5 | 10 |
| 10 | 5, 8, 9 | 13, 28 |
| 11 | 5, 8 | 13 |
| 12 | 2, 5 | 13 |
| 13 | 5, 10, 11, 12 | 21, 35 |
| 14 | 2, 5 | 23, 35 |
| 15 | 4, 5 | 21, 22, 35 |
| 16 | 2, 5 | 20 |
| 17 | 2, 5 | 18, 20 |
| 18 | 2, 5, 17 | 20 |
| 19 | 2, 5 | 20 |
| 20 | 5, 16, 17, 18, 19 | 24, 27, 35 |
| 21 | 4, 5, 6, 15 | 29, 35 |
| 22 | 4, 5, 6, 15 | 30, 35 |
| 23 | 5, 6, 14 | 30, 35 |
| 24 | 5, 6, 20 | 31, 35 |
| 25 | 4, 5, 6 | 31, 35 |
| 26 | 4, 5, 6 | 32, 35 |
| 27 | 5, 6, 20 | 33, 35 |
| 28 | 5, 6, 10 | 34, 35 |
| 29 | 21 | 35 |
| 30 | 22, 23 | 35 |
| 31 | 24, 25 | 35 |
| 32 | 26 | 35 |
| 33 | 27 | 35 |
| 34 | 28 | 35 |
| 35 | 13, 14, 15, 20, 21-34 | 36, 37 |
| 36 | 35 | F1-F4 |
| 37 | 36 | F1-F4 |

### Agent Dispatch Summary

- **Wave 1**: 7 tasks — T1-T7 → `quick`
- **Wave 2**: 8 tasks — T8 → `quick`, T9 → `unspecified-low`, T10 → `unspecified-high`, T11 → `unspecified-low`, T12 → `unspecified-high`, T13 → `unspecified-low`, T14 → `unspecified-low`, T15 → `quick`
- **Wave 3**: 5 tasks — T16 → `unspecified-low`, T17 → `unspecified-low`, T18 → `unspecified-high`, T19 → `unspecified-low`, T20 → `unspecified-high`
- **Wave 4**: 8 tasks — T21-T22 → `unspecified-low`, T23 → `quick`, T24 → `unspecified-low`, T25-T27 → `quick`, T28 → `unspecified-low`
- **Wave 5**: 6 tasks — T29-T34 → `visual-engineering`
- **Wave 6**: 3 tasks — T35 → `unspecified-low`, T36 → `unspecified-high`, T37 → `writing`
- **FINAL**: 4 tasks — F1 → `oracle`, F2 → `unspecified-high`, F3 → `unspecified-high`, F4 → `deep`

### File Exclusivity Per Wave

> NO two parallel subagents may edit the same file. Each wave is verified for file-level exclusivity.

- **Wave 1**: All tasks create files in distinct directories (project root, Config/, Infrastructure/, Core/Entities/, Core/Protocols/, SharedUI/, App/). No overlap. ✅
- **Wave 2**: BLE tasks (T8-T11) in Services/BLEService/ but distinct files; Audio tasks (T12-T14) in Services/AudioService/ distinct files; T15 in Services/RecordingService/. No overlap. ✅
- **Wave 3**: All ML tasks in Services/MLService/ but distinct files (VADService, LanguageDetector, WhisperCoreMLService, DiarizationService, LLMService+Pipeline). No overlap. ✅
- **Wave 4**: Each module task in its own Modules/{ModuleName}/ directory. No overlap. ✅
- **Wave 5**: Each view task in its own module's View/ directory. T30 spans RecordingDetail+WaveformPlayback View dirs; T31 spans Transcript+Summary View dirs. No overlap between tasks. ✅
- **Wave 6**: T35 touches App/ + module Assembly files; T36 creates new test files; T37 touches README.md. No overlap. ✅

---

## TODOs

- [ ] 1. Project Scaffolding + Xcode Project + SPM + VIPER Folder Structure

  **What to do**:
  - Create new Xcode project at `Scribe/` (replacing nested Scribe/Scribe/Scribe structure)
  - Single target named "Scribe" with iOS 18.0 deployment target
  - Create `ScribeTests` test target with XCTest
  - Configure VIPER folder structure: `App/`, `Modules/`, `Services/`, `Core/`, `SharedUI/`
  - Create module subdirectories for all 8 modules: `Modules/RecordingListModule/`, `Modules/RecordingDetailModule/`, `Modules/WaveformPlaybackModule/`, `Modules/TranscriptModule/`, `Modules/SummaryModule/`, `Modules/MindMapModule/`, `Modules/AgentGeneratingModule/`, `Modules/DeviceSettingsModule/`
  - Each module directory has subdirectories: `Assembly/`, `Interactor/`, `Presenter/`, `Router/`, `View/`
  - Create service subdirectories: `Services/BLEService/`, `Services/AudioService/`, `Services/MLService/`, `Services/RecordingService/`
  - Create core subdirectories: `Core/Entities/`, `Core/Protocols/`, `Core/Config/`, `Core/Infrastructure/`, `Core/Infrastructure/Extensions/`
  - Add SPM dependencies: FluidAudio, LLM.swift, swift-huggingface, swift-transformers, swift-opus, yyjson
  - Create placeholder `ScribeApp.swift` with @main and SwiftData ModelContainer
  - Verify: `xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' build` succeeds
  - Write first test: `ScribeTests/App/ScribeAppTests.swift` — verify app launches

  **Must NOT do**:
  - Do NOT create multiple targets or SPM packages
  - Do NOT add dependencies beyond the 6 listed
  - Do NOT implement any features — scaffolding only

  **Files Modified**:
  - `Scribe.xcodeproj/project.pbxproj` (project file)
  - `Scribe/ScribeApp.swift` (placeholder)
  - `ScribeTests/App/ScribeAppTests.swift` (first test)
  - All empty directory placeholder files

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Straightforward project setup with known structure
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2-7)
  - **Blocks**: Tasks 8-20
  - **Blocked By**: None

  **References**:

  **Pattern References** (existing code to follow):
  - `Scribe/Scribe.xcodeproj/project.pbxproj` — current target config, SPM dependency versions
  - `Scribe/Scribe/Sources/ScribeApp.swift` — app entry point pattern with SwiftData ModelContainer

  **External References**:
  - The Book of VIPER: `module-structure.md` — VIPER module directory layout (Assembly/Interactor/Presenter/Router/View)
  - The Book of VIPER: `code-style.md` — folder naming conventions (no "Module" suffix in folder names)

  **WHY Each Reference Matters**:
  - project.pbxproj: reuse existing SPM dependency URLs and version pins
  - ScribeApp.swift: copy the SwiftData ModelContainer setup pattern
  - VIPER module-structure: canonical directory layout for each module
  - VIPER code-style: naming conventions for directories and files

  **Acceptance Criteria**:

  - [ ] Xcode project builds: `xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' build` succeeds
  - [ ] Test target runs: `xcodebuild test` passes with 1 test
  - [ ] All 8 module directories exist with Assembly/Interactor/Presenter/Router/View subdirectories
  - [ ] All 4 service directories exist (BLEService, AudioService, MLService, RecordingService)
  - [ ] All core directories exist (Entities, Protocols, Config, Infrastructure)
  - [ ] SharedUI/ directory exists
  - [ ] SPM dependencies resolve: FluidAudio, LLM.swift, swift-huggingface, swift-transformers, swift-opus, yyjson
  - [ ] No nested Scribe/Scribe/Scribe directories

  **QA Scenarios**:

  ```
  Scenario: Xcode project builds from scratch
    Tool: Bash (xcodebuild)
    Preconditions: Clean project directory
    Steps:
      1. Run: xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' clean build
      2. Verify exit code is 0
    Expected Result: Build succeeds with zero errors
    Failure Indicators: Exit code non-zero, "BUILD FAILED" in output
    Evidence: .sisyphus/evidence/task-1-build-success.txt

  Scenario: VIPER folder structure is correct
    Tool: Bash (ls)
    Preconditions: Project created
    Steps:
      1. Verify Modules/ contains 8 module directories
      2. Verify each module has Assembly/, Interactor/, Presenter/, Router/, View/
      3. Verify Services/ contains BLEService/, AudioService/, MLService/, RecordingService/
      4. Verify Core/ contains Entities/, Protocols/, Config/, Infrastructure/
    Expected Result: All directories present
    Failure Indicators: Missing directory
    Evidence: .sisyphus/evidence/task-1-folder-structure.txt
  ```

  **Commit**: YES (groups with 1)
  - Message: `chore(scaffold): create VIPER Xcode project with SPM dependencies`
  - Files: all scaffold files

---

- [ ] 2. Config Layer (PipelineConfig, AudioConfig, BluetoothConfig, FeatureFlags)

  **What to do**:
  - Create `Core/Config/PipelineConfig.swift` — model paths, thresholds, chunk sizes
    - Swiss German Whisper CoreML URL: `jlnslv/whisper-large-v3-turbo-swiss-german-coreml`
    - Fallback ASR model config
    - Diarization clustering threshold: 0.35, speaker bounds: min 1, max 8
    - Single-pass threshold: 25,000 chars, chunk size: 12,000, overlap: 1,200
  - Create `Core/Config/AudioConfig.swift` — format, sample rates, encoding
    - Unified format: Opus, 16kHz, mono, frame size: 320 samples
  - Create `Core/Config/BluetoothConfig.swift` — device serials, UUIDs, timeouts
    - Service UUID: E49A3001-F69A-11E8-8EB2-F2801F1B9FD1
    - Audio characteristic: E49A3003-F69A-11E8-8EB2-F2801F1B9FD1
    - Command: F0F1, File transfer: F0F2/F0F3/F0F4, Battery: 2A19
    - Device serial: "129950", connection timeout: 10s, SLink timeout: 5s
    - Known device names: LA518, LA519, L027, L813-L817, MAR-2518
    - RSSI threshold: -70 dBm
  - Create `Core/Config/FeatureFlags.swift` — feature toggles
  - Write tests: verify all config values are accessible and non-nil

  **Must NOT do**:
  - Do NOT implement business logic
  - Do NOT use UserDefaults or dynamic loading

  **Files Modified**:
  - `Core/Config/PipelineConfig.swift`
  - `Core/Config/AudioConfig.swift`
  - `Core/Config/BluetoothConfig.swift`
  - `Core/Config/FeatureFlags.swift`
  - `ScribeTests/Config/ConfigTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple struct creation with known values
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3-7)
  - **Blocks**: Tasks 10, 12, 14, 16-19
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - Current magic numbers scattered in: `DeviceConnectionManager.swift`, `SLinkProtocol.swift`, `InferencePipeline.swift`, `LLMService.swift`

  **WHY Each Reference Matters**:
  - Extract ALL hardcoded values from these files into named constants here

  **Acceptance Criteria**:

  - [ ] All 4 config files created
  - [ ] Zero magic numbers in config values — all extracted to named constants
  - [ ] Config structs are immutable (let properties only)
  - [ ] Tests verify all config values

  **QA Scenarios**:

  ```
  Scenario: All config values are accessible
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create ConfigTests.swift
      2. Test PipelineConfig.swissGermanWhisperURL is non-empty
      3. Test AudioConfig.sampleRate equals 16000
      4. Test BluetoothConfig.serviceUUID is valid UUID string
      5. Run: xcodebuild test -only-testing:ScribeTests/ConfigTests
    Expected Result: All config tests pass
    Failure Indicators: Any test failure
    Evidence: .sisyphus/evidence/task-2-config-tests.txt
  ```

  **Commit**: YES (groups with 1)
  - Message: `feat(config): extract all magic numbers to centralized config layer`

---

- [ ] 3. Infrastructure Layer (ScribeLogger, Extensions, SwiftDataModelContainer)

  **What to do**:
  - Create `Core/Infrastructure/Logging/ScribeLogger.swift` — replace all 133 print statements
    - Use os.Logger with subsystem "com.scribe.app"
    - Log levels: debug, info, warning, error, fault
    - Category-based logging: ble, audio, ml, ui, pipeline
  - Create `Core/Infrastructure/Extensions/Date+Formatting.swift` — date formatting
  - Create `Core/Infrastructure/Extensions/String+Validation.swift` — string validation
  - Create `Core/Infrastructure/Extensions/TimeInterval+Formatting.swift` — duration formatting
    - Extract duplicated formatDuration() into shared extension
  - Create `Core/Infrastructure/Persistence/SwiftDataModelContainer.swift` — SwiftData setup
  - Write tests: Logger, extensions, ModelContainer

  **Must NOT do**:
  - Do NOT implement business logic
  - Do NOT create custom logging frameworks beyond os.Logger wrapper

  **Files Modified**:
  - `Core/Infrastructure/Logging/ScribeLogger.swift`
  - `Core/Infrastructure/Extensions/Date+Formatting.swift`
  - `Core/Infrastructure/Extensions/String+Validation.swift`
  - `Core/Infrastructure/Extensions/TimeInterval+Formatting.swift`
  - `Core/Infrastructure/Persistence/SwiftDataModelContainer.swift`
  - `ScribeTests/Infrastructure/LoggerTests.swift`
  - `ScribeTests/Infrastructure/ExtensionTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple utility and extension creation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 4-7)
  - **Blocks**: All tasks needing logging, extensions, persistence
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - Current print statements: grep across all source files — 133 instances to replace
  - Current duplicated formatDuration: `RecordingListView.swift:151`, `RecordingCardView.swift:55`
  - Current empty catch: `AudioRecorder.swift:139`

  **WHY Each Reference Matters**:
  - 133 print statements: ScribeLogger must cover all log levels these represent
  - formatDuration duplication: this extension replaces both instances
  - Empty catch: understand what was being silently swallowed

  **Acceptance Criteria**:

  - [ ] ScribeLogger with os.Logger replaces all print patterns
  - [ ] formatDuration extracted to shared extension
  - [ ] SwiftData ModelContainer initializes with on-disk persistence
  - [ ] All extension methods have unit tests

  **QA Scenarios**:

  ```
  Scenario: Logger outputs at all levels
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create LoggerTests.swift
      2. Test all log levels execute without crash
      3. Run: xcodebuild test -only-testing:ScribeTests/LoggerTests
    Expected Result: All logger tests pass
    Evidence: .sisyphus/evidence/task-3-logger-tests.txt

  Scenario: Duration formatting works correctly
    Tool: Bash (xcodebuild test)
    Steps:
      1. Test TimeInterval(0) → "0:00", TimeInterval(65) → "1:05", TimeInterval(3661) → "1:01:01"
      2. Run: xcodebuild test -only-testing:ScribeTests/ExtensionTests
    Expected Result: All formatting tests pass
    Evidence: .sisyphus/evidence/task-3-extension-tests.txt
  ```

  **Commit**: YES (groups with 1)
  - Message: `feat(infra): add logger, extensions, and persistence setup`

---

- [ ] 4. Core Entities (Recording, Transcript, MeetingSummary, MindMapNode, AudioSample, RecordingSource)

  **What to do**:
  - Create `Core/Entities/Recording.swift` — SwiftData @Model
    - id, title, createdAt, duration, audioFilePath, categoryTag, rawTranscript, meetingNotes, actionItems, mindMapJSON, micSource
  - Create `Core/Entities/Transcript.swift` — SpeakerSegment + Transcript value types
  - Create `Core/Entities/MeetingSummary.swift` — MeetingSummary, TopicSection (Codable)
  - Create `Core/Entities/MindMapNode.swift` — MindMapNode recursive Codable type
  - Create `Core/Entities/AudioSample.swift` — AudioSample value type
  - Create `Core/Entities/RecordingSource.swift` — enum: internal vs BLE
  - Write tests: entity creation, encoding/decoding, equality

  **Must NOT do**:
  - Do NOT import SwiftUI, CoreBluetooth, AVFoundation
  - Do NOT add business logic

  **Files Modified**:
  - `Core/Entities/Recording.swift`
  - `Core/Entities/Transcript.swift`
  - `Core/Entities/MeetingSummary.swift`
  - `Core/Entities/MindMapNode.swift`
  - `Core/Entities/AudioSample.swift`
  - `Core/Entities/RecordingSource.swift`
  - `ScribeTests/Entities/EntityTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Plain data type creation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1-3, 5-7)
  - **Blocks**: Tasks 15, 21, 22, 25, 26
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - Current Recording: `Scribe/Scribe/Sources/Models/Recording.swift` — SwiftData @Model properties
  - Current LLM structs: `LLMService.swift` — MeetingSummary, TopicSection, MindMapNode

  **WHY Each Reference Matters**:
  - Recording.swift: exact property names and types for SwiftData compatibility
  - LLMService.swift: Codable struct shapes must match LLM JSON output format

  **Acceptance Criteria**:

  - [ ] All 6 entity files created with correct properties
  - [ ] Core entities have ZERO external framework imports (only Foundation)
  - [ ] MeetingSummary, TopicSection, MindMapNode are Codable
  - [ ] All entities have unit tests

  **QA Scenarios**:

  ```
  Scenario: Domain entities are pure Swift
    Tool: Bash (xcodebuild test)
    Steps:
      1. Verify no framework imports in Core/Entities/ (only Foundation)
      2. Test MeetingSummary encodes/decodes to JSON round-trip
      3. Test MindMapNode recursive encoding/decoding
      4. Run: xcodebuild test -only-testing:ScribeTests/EntityTests
    Expected Result: All entity tests pass, zero framework imports
    Evidence: .sisyphus/evidence/task-4-entity-tests.txt
  ```

  **Commit**: YES (groups with 1)
  - Message: `feat(core): create pure Swift entity types`

---

- [ ] 5. Core Protocols (Service Protocols + VIPER Base Protocols)

  **What to do**:
  - Create `Core/Protocols/ServiceProtocols.swift` — all service interfaces:
    - AudioRecorderProtocol, AudioPlayerProtocol, DiarizationServiceProtocol
    - TranscriptionServiceProtocol, SummarizationServiceProtocol
    - VADServiceProtocol, LanguageDetectionProtocol
    - BluetoothDeviceScannerProtocol, AudioStreamProtocol, RecordingRepositoryProtocol
  - LanguageDetectionProtocol returns LanguageConfidence { language, confidence, isSwissGerman }
  - Create `Core/Protocols/VIPERProtocols.swift` — VIPER base protocols:
    - ModuleInput — base protocol for module configuration from outside
    - ModuleOutput — base protocol for module result communication
    - AssemblyProtocol — base protocol for module factories
  - Write tests: protocol conformance, mock implementations

  **Must NOT do**:
  - Do NOT implement any protocol — define interfaces only
  - Do NOT import external frameworks (only Foundation)

  **Files Modified**:
  - `Core/Protocols/ServiceProtocols.swift`
  - `Core/Protocols/VIPERProtocols.swift`
  - `ScribeTests/Protocols/ServiceProtocolMocks.swift`
  - `ScribeTests/Protocols/VIPERProtocolTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Protocol definitions are straightforward interface declarations
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1-4, 6, 7)
  - **Blocks**: Tasks 8-28 (all service and module tasks)
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - Current service patterns: `AudioRecorder.swift`, `DeviceConnectionManager.swift`, `InferencePipeline.swift`
  - The Book of VIPER: `module-structure.md` — ModuleInput/ModuleOutput purpose and usage
  - The Book of VIPER: `code-style.md` — method naming conventions (imperative verbs for actions, `did` prefix for completions)

  **WHY Each Reference Matters**:
  - Service patterns: existing method signatures inform protocol definitions
  - VIPER ModuleInput/Output: canonical pattern for inter-module communication
  - VIPER code-style: method naming ensures consistency across all modules

  **Acceptance Criteria**:

  - [ ] All 10 service protocol files defined in single ServiceProtocols.swift
  - [ ] VIPERProtocols.swift defines ModuleInput, ModuleOutput, AssemblyProtocol
  - [ ] All protocols are framework-agnostic (only Foundation imports)
  - [ ] Mock implementations exist in test target for all service protocols

  **QA Scenarios**:

  ```
  Scenario: All protocols compile without framework imports
    Tool: Bash (xcodebuild)
    Steps:
      1. Verify Core/Protocols/ has no imports beyond Foundation
      2. Run: xcodebuild -scheme Scribe build
    Expected Result: Build succeeds with zero errors
    Failure Indicators: Build failure, framework import found
    Evidence: .sisyphus/evidence/task-5-protocol-build.txt
  ```

  **Commit**: YES (groups with 1)
  - Message: `feat(core): define all service and VIPER base protocols`

---

- [ ] 6. Shared UI — Theme + Design Tokens + Spacing + Typography

  **What to do**:
  - Create `SharedUI/Theme/Theme.swift` — exact match of current design tokens
    - Colors: scribeRed (rgb(0.9, 0.2, 0.2)), obsidian (rgb(0.1, 0.1, 0.11))
    - cardBackgroundLight (white), cardBackgroundDark (rgb(0.15, 0.15, 0.16))
    - accentGray (gray.opacity(0.3))
    - cornerRadius: 20pt, shadowRadius: 10pt
    - shadowOpacityLight: 0.05, shadowOpacityDark: 0.2
    - .scribeCardStyle(scheme:) view modifier
  - Create `SharedUI/Theme/Spacing.swift` — extract all hardcoded spacing values
    - recordButtonClearance: 100pt, safeAreaPadding: 24pt
    - recordButtonSize: 80x80pt, stopIconSize: 24x24pt
    - waveformHeight: 100pt, controlSpacing: 40pt
    - All other hardcoded values from current views
  - Create `SharedUI/Theme/Typography.swift` — font definitions
    - All system font styles used across views
  - Write tests: color values, spacing constants, modifier application

  **Must NOT do**:
  - Do NOT change any color values — exact match required
  - Do NOT add new design tokens not used in current UI

  **Files Modified**:
  - `SharedUI/Theme/Theme.swift`
  - `SharedUI/Theme/Spacing.swift`
  - `SharedUI/Theme/Typography.swift`
  - `ScribeTests/SharedUI/ThemeTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Direct copy of existing design tokens
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1-5, 7)
  - **Blocks**: Tasks 21-28 (all module and view tasks)
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - Current Theme: `Theme.swift` (34 lines) — exact copy of colors and card style
  - Current hardcoded values: all UI views — extract to Spacing.swift

  **WHY Each Reference Matters**:
  - Theme.swift: exact color values and scribeCardStyle modifier to preserve pixel-perfect match
  - Hardcoded values across views: all must be extracted to Spacing.swift to eliminate magic numbers

  **Acceptance Criteria**:

  - [ ] Theme.swift matches current colors exactly
  - [ ] All 20+ hardcoded values extracted to Spacing.swift
  - [ ] .scribeCardStyle modifier works identically
  - [ ] Dark mode forced via .preferredColorScheme(.dark)

  **QA Scenarios**:

  ```
  Scenario: Theme colors match current implementation
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create ThemeTests
      2. Verify scribeRed = rgb(0.9, 0.2, 0.2)
      3. Verify obsidian = rgb(0.1, 0.1, 0.11)
      4. Run: xcodebuild test -only-testing:ScribeTests/ThemeTests
    Expected Result: All color values match
    Evidence: .sisyphus/evidence/task-6-theme-tests.txt
  ```

  **Commit**: YES (groups with 1)
  - Message: `feat(ui): implement theme and design tokens with exact match`

---

- [ ] 7. AppAssembly Skeleton + Service Registration

  **What to do**:
  - Create `App/AppAssembly.swift` — root VIPER assembly that:
    - Creates and registers all Service implementations against their protocols
    - Provides factory methods for each VIPER module (calls module Assembly)
    - Injects services into module Interactors via module Assemblies
  - Create `App/ServiceRegistry.swift` — holds all service instances
    - BLEService, AudioService, MLService, RecordingService instances
    - Services are created here, injected into Interactors by Assemblies
  - Write tests: AppAssembly creates all services, resolves all modules

  **Must NOT do**:
  - Do NOT implement any service — only register placeholders/stubs
  - Do NOT use global singletons — all DI through Assembly chain

  **Files Modified**:
  - `App/AppAssembly.swift`
  - `App/ServiceRegistry.swift`
  - `ScribeTests/App/AppAssemblyTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Skeleton DI setup with stubs
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1-6)
  - **Blocks**: Tasks 21-28, 35
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - The Book of VIPER: `module-structure.md` — Assembly pattern for wiring module components
  - The Book of VIPER: `code-style.md` — Assembly method naming (`view{ModuleName}Module`, `presenter{ModuleName}Module`)

  **WHY Each Reference Matters**:
  - VIPER Assembly pattern: canonical approach for dependency injection in VIPER
  - Assembly naming conventions: consistency across all 8 module assemblies

  **Acceptance Criteria**:

  - [ ] AppAssembly creates all service stubs
  - [ ] AppAssembly has factory method for each of the 8 modules
  - [ ] ServiceRegistry holds all service protocol references
  - [ ] Tests verify assembly creates all components

  **QA Scenarios**:

  ```
  Scenario: AppAssembly creates all module factories
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create AppAssemblyTests
      2. Verify each module factory returns a View
      3. Verify all service stubs are registered
      4. Run: xcodebuild test -only-testing:ScribeTests/AppAssemblyTests
    Expected Result: All module factories and services resolve
    Evidence: .sisyphus/evidence/task-7-assembly-tests.txt
  ```

  **Commit**: YES (groups with 1)
  - Message: `feat(app): create AppAssembly skeleton with service registration`

---

- [ ] 8. BLE Service — SLink Protocol Files (Copy As-Is, Wrap Behind Protocol)

  **What to do**:
  - Copy SLink protocol logic from current codebase WITHOUT modification
  - Create `Services/BLEService/SLink/SLinkProtocol.swift` — packet structure, checksum, serialization
  - Create `Services/BLEService/SLink/SLinkPacketParser.swift` — parse incoming data into packets
  - Create `Services/BLEService/SLink/SLinkConnectionState.swift` — state machine enum
  - Create `Services/BLEService/SLink/SLinkCommand.swift` — command enum (0x0202, 0x0203, etc.)
  - Create `Services/BLEService/SLink/SLinkConstants.swift` — UUIDs, magic bytes, checksum mask
  - Wrap behind AudioStreamProtocol and BluetoothDeviceScannerProtocol from Core/Protocols
  - 8-step init sequence preserved exactly: Handshake → Serial → DeviceInfo → Configure → Status → 0x0218 → 0x020A → 0x0217
  - Checksum algorithm: CRC-16 variant with XOR 0x5F00
  - Write tests: packet parsing, serialization, checksum validation

  **Must NOT do**:
  - Do NOT modify any SLink protocol logic — copy as-is
  - Do NOT change BLE characteristic UUIDs
  - Do NOT modify the 8-step init sequence

  **Files Modified**:
  - `Services/BLEService/SLink/SLinkProtocol.swift`
  - `Services/BLEService/SLink/SLinkPacketParser.swift`
  - `Services/BLEService/SLink/SLinkConnectionState.swift`
  - `Services/BLEService/SLink/SLinkCommand.swift`
  - `Services/BLEService/SLink/SLinkConstants.swift`
  - `ScribeTests/Services/BLE/SLinkPacketParserTests.swift`
  - `ScribeTests/Services/BLE/SLinkChecksumTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Copy existing logic and wrap behind protocols — no new design needed
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 9-15 in Wave 2)
  - **Parallel Group**: Wave 2
  - **Blocks**: Tasks 10, 11
  - **Blocked By**: Task 5

  **References**:

  **Pattern References**:
  - Current SLink: `Scribe/Scribe/Scribe/Sources/Bluetooth/SLinkProtocol.swift` (472 lines) — copy logic verbatim
  - Current DeviceConnectionManager: `DeviceConnectionManager.swift` (676 lines) — extract SLink parts
  - Current constants: UUIDs, magic bytes, checksum from SLinkProtocol.swift

  **WHY Each Reference Matters**:
  - SLinkProtocol.swift: proprietary protocol — must be preserved exactly, byte-for-byte
  - DeviceConnectionManager.swift: contains SLink init sequence mixed with connection logic — extract SLink parts only

  **Acceptance Criteria**:

  - [ ] SLink protocol files created with exact logic from current codebase
  - [ ] 8-step init sequence preserved exactly
  - [ ] Checksum algorithm matches current implementation
  - [ ] All SLink types wrapped behind domain protocols from Core/Protocols
  - [ ] Unit tests for packet parsing and checksum

  **QA Scenarios**:

  ```
  Scenario: SLink packet parsing produces correct output
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create SLinkPacketParserTests
      2. Feed raw Data matching current packet format: [0x80, 0x08, command, length, payload..., checksum]
      3. Verify parsed packet has correct command, payload, checksum
      4. Run: xcodebuild test -only-testing:ScribeTests/SLinkPacketParserTests
    Expected Result: Packet parsing matches current behavior
    Evidence: .sisyphus/evidence/task-8-packet-parsing-tests.txt

  Scenario: Checksum algorithm matches current implementation
    Tool: Bash (xcodebuild test)
    Steps:
      1. Test checksum with known input data from current SLinkProtocol.swift
      2. Compare output with current checksum result
      3. Run: xcodebuild test -only-testing:ScribeTests/SLinkChecksumTests
    Expected Result: Checksum matches exactly
    Evidence: .sisyphus/evidence/task-8-checksum-tests.txt
  ```

  **Commit**: YES (groups with 8)
  - Message: `feat(ble): extract SLink protocol with exact proprietary logic`

---

- [ ] 9. BLE Service — Device Scanner (BluetoothDevice, BluetoothDeviceScanner)

  **What to do**:
  - Create `Services/BLEService/BluetoothDevice.swift` — value type (name, identifier, rssi, battery)
  - Create `Services/BLEService/BluetoothDeviceScanner.swift` — implements BluetoothDeviceScannerProtocol
    - CoreBluetooth CBCentralManager wrapper
    - Known device name filtering: LA518, LA519, L027, L813-L817, MAR-2518
    - RSSI threshold: -70 dBm, scan timeout: 10s (from BluetoothConfig)
  - Replace all print statements with ScribeLogger
  - Write tests: scanner discovery with mocked CoreBluetooth

  **Must NOT do**:
  - Do NOT modify SLink protocol logic (handled in Task 8)
  - Do NOT use print statements

  **Files Modified**:
  - `Services/BLEService/BluetoothDevice.swift`
  - `Services/BLEService/BluetoothDeviceScanner.swift`
  - `ScribeTests/Services/BLE/BluetoothDeviceScannerTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: CoreBluetooth wrapper with known filter criteria
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 8, 10-15 in Wave 2)
  - **Parallel Group**: Wave 2
  - **Blocks**: Task 10
  - **Blocked By**: Task 5

  **References**:

  **Pattern References**:
  - Current BluetoothDevice: `BluetoothDevice.swift` — device value type properties
  - Current BluetoothDeviceScanner logic in: `DeviceConnectionManager.swift` — scan and filter logic

  **WHY Each Reference Matters**:
  - BluetoothDevice.swift: reuse value type properties (name, identifier, rssi, battery)
  - DeviceConnectionManager.swift: extract scan/filter logic from the 676-line god class

  **Acceptance Criteria**:

  - [ ] BluetoothDevice is a value type with name, identifier, rssi, battery
  - [ ] BluetoothDeviceScanner filters by known device names and RSSI threshold
  - [ ] All print statements replaced with ScribeLogger
  - [ ] Unit tests with mocked CoreBluetooth

  **QA Scenarios**:

  ```
  Scenario: Device scanner discovers known devices
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create BluetoothDeviceScannerTests with MockCBCentralManager
      2. Mock peripheral with name "LA518" and RSSI -65 — verify included
      3. Mock peripheral with name "Unknown" — verify excluded
      4. Mock peripheral with name "LA518" and RSSI -80 — verify excluded (below threshold)
      5. Run: xcodebuild test -only-testing:ScribeTests/BluetoothDeviceScannerTests
    Expected Result: Only known devices above RSSI threshold returned
    Evidence: .sisyphus/evidence/task-9-scanner-tests.txt
  ```

  **Commit**: YES (groups with 8)
  - Message: `feat(ble): implement device scanner with name and RSSI filtering`

---

- [ ] 10. BLE Service — Connection Manager (DeviceConnectionManager, ConnectionStateMachine, SLinkInitOrchestrator, KeepAliveService)

  **What to do**:
  - Create `Services/BLEService/DeviceConnectionManager.swift` — split from current 676-line god class
    - Coordinates scanner, connection state machine, SLink init, and keep-alive
    - Implements connection lifecycle: scan → connect → init → keep-alive → disconnect
  - Create `Services/BLEService/ConnectionStateMachine.swift` — connection state management
    - States: disconnected, connecting, connected, initializing, initialized, error, reconnecting
    - Max reconnection attempts: 5
  - Create `Services/BLEService/SLinkInitOrchestrator.swift` — 8-step init sequence
    - Delegates to SLinkProtocol from Task 8 for actual packet exchange
    - Timeout per step: from BluetoothConfig.sLinkTimeout
  - Create `Services/BLEService/KeepAliveService.swift` — heartbeat every 3s
  - Connection timeout: 10s (from BluetoothConfig)
  - Last connected device ID in UserDefaults
  - Replace all 62 print statements with ScribeLogger
  - Write tests: connection state machine, SLink init orchestration

  **Must NOT do**:
  - Do NOT create a single 676-line file — split into focused services
  - Do NOT modify SLink protocol logic (handled in Task 8)
  - Do NOT use print statements

  **Files Modified**:
  - `Services/BLEService/DeviceConnectionManager.swift`
  - `Services/BLEService/ConnectionStateMachine.swift`
  - `Services/BLEService/SLinkInitOrchestrator.swift`
  - `Services/BLEService/KeepAliveService.swift`
  - `ScribeTests/Services/BLE/ConnectionStateMachineTests.swift`
  - `ScribeTests/Services/BLE/SLinkInitOrchestratorTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: BLE connection management is complex with state machines and timeouts
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 11-15 in Wave 2)
  - **Parallel Group**: Wave 2
  - **Blocks**: Tasks 13, 28
  - **Blocked By**: Tasks 5, 8, 9

  **References**:

  **Pattern References**:
  - Current DeviceConnectionManager: `DeviceConnectionManager.swift` (676 lines) — split logic into 4 focused files
  - Current tests: `BluetoothDeviceTests.swift` (33 tests) — reuse test patterns

  **WHY Each Reference Matters**:
  - DeviceConnectionManager.swift: the 676-line god class that must be decomposed — study all responsibilities before splitting
  - BluetoothDeviceTests.swift: existing test patterns for mocking CoreBluetooth

  **Acceptance Criteria**:

  - [ ] No file exceeds 400 lines
  - [ ] All print statements replaced with ScribeLogger
  - [ ] ConnectionStateMachine handles all 7 states
  - [ ] SLinkInitOrchestrator executes 8-step sequence with timeouts
  - [ ] KeepAliveService sends heartbeat every 3s
  - [ ] Unit tests with mocked CoreBluetooth

  **QA Scenarios**:

  ```
  Scenario: ConnectionStateMachine transitions correctly
    Tool: Bash (xcodebuild test)
    Steps:
      1. Test transitions: disconnected → connecting → connected → initializing → initialized
      2. Test error transition from any state
      3. Test reconnection attempt limit (max 5)
      4. Run: xcodebuild test -only-testing:ScribeTests/ConnectionStateMachineTests
    Expected Result: All state transitions correct
    Evidence: .sisyphus/evidence/task-10-state-machine-tests.txt

  Scenario: SLinkInitOrchestrator completes 8-step init
    Tool: Bash (xcodebuild test)
    Steps:
      1. Mock SLinkProtocol responses for each of 8 steps
      2. Verify orchestrator calls each step in sequence
      3. Verify timeout triggers error on delayed response
      4. Run: xcodebuild test -only-testing:ScribeTests/SLinkInitOrchestratorTests
    Expected Result: Init sequence completes or times out correctly
    Evidence: .sisyphus/evidence/task-10-init-orchestrator-tests.txt
  ```

  **Commit**: YES (groups with 8)
  - Message: `feat(ble): implement connection manager with state machine and SLink init`

---

- [ ] 11. BLE Service — Audio Stream Receiver + Opus Decoder

  **What to do**:
  - Create `Services/BLEService/AudioStreamReceiver.swift` — implements AudioStreamProtocol
    - Subscribes to audio characteristic notifications (E49A3003)
    - Strips Opus headers (0xFF 0xF3 0x48 0xC4 or 0xFF 0xF3)
    - Decodes via swift-opus to Float32 PCM at 16kHz mono
    - Circular buffer management for audio frames
    - Frame size: 320 samples (20ms at 16kHz)
  - Create `Services/BLEService/OpusAudioDecoder.swift` — swift-opus wrapper
    - Decode Opus packets to Float32 PCM
    - Handle decoder initialization and reset
  - Replace all 12 print statements with ScribeLogger
  - Write tests: Opus decoding, header stripping, buffer management

  **Must NOT do**:
  - Do NOT modify Opus decoding logic
  - Do NOT use print statements

  **Files Modified**:
  - `Services/BLEService/AudioStreamReceiver.swift`
  - `Services/BLEService/OpusAudioDecoder.swift`
  - `ScribeTests/Services/BLE/OpusAudioDecoderTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Audio decoding wrapper — copy existing logic
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 9-10, 12-15 in Wave 2)
  - **Parallel Group**: Wave 2
  - **Blocks**: Task 13
  - **Blocked By**: Tasks 5, 8

  **References**:

  **Pattern References**:
  - Current AudioStreamReceiver: `AudioStreamReceiver.swift` (320 lines) — copy logic
  - Current Opus header stripping: lines handling 0xFF 0xF3 prefix

  **WHY Each Reference Matters**:
  - AudioStreamReceiver.swift: existing buffer management and characteristic subscription logic
  - Header stripping: exact byte patterns for Opus frame detection

  **Acceptance Criteria**:

  - [ ] AudioStreamReceiver subscribes to correct characteristic
  - [ ] Opus headers stripped correctly (both 2-byte and 4-byte variants)
  - [ ] swift-opus decodes to Float32 PCM at 16kHz mono
  - [ ] Circular buffer manages audio frames
  - [ ] All print statements replaced with ScribeLogger

  **QA Scenarios**:

  ```
  Scenario: Opus decoder produces correct Float32 output
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create OpusAudioDecoderTests with known Opus packet data
      2. Decode and verify output is Float32 array at 16kHz
      3. Run: xcodebuild test -only-testing:ScribeTests/OpusAudioDecoderTests
    Expected Result: Decoded output matches expected Float32 samples
    Evidence: .sisyphus/evidence/task-11-opus-decoder-tests.txt

  Scenario: Header stripping handles both formats
    Tool: Bash (xcodebuild test)
    Steps:
      1. Test with 0xFF 0xF3 0x48 0xC4 prefix — verify stripped correctly
      2. Test with 0xFF 0xF3 prefix — verify stripped correctly
      3. Run: xcodebuild test -only-testing:ScribeTests/OpusAudioDecoderTests
    Expected Result: Both header formats stripped correctly
    Evidence: .sisyphus/evidence/task-11-header-strip-tests.txt
  ```

  **Commit**: YES (groups with 8)
  - Message: `feat(ble): implement audio stream receiver with Opus decode`

---

- [ ] 12. Audio Service — Internal Mic Recorder + Opus Encoder

  **What to do**:
  - Create `Services/AudioService/InternalMicRecorder.swift` — implements AudioRecorderProtocol
    - AVAudioEngine-based recording
    - Output format: Opus, 16kHz, mono (unified with BLE)
    - Session category: .playAndRecord with .allowBluetooth and .defaultToSpeaker
    - USB-C Plug & Play: AVAudioSession.routeChangeNotification for usbAudio/headsetMic
    - Haptic feedback on start/stop
    - Files saved as <UUID>.caf in Documents/
  - Create `Services/AudioService/OpusEncoder.swift` — Opus encoding for internal mic
    - Encode Float32 PCM to Opus packets
    - Use swift-opus or AVAudioConverter with Opus codec
  - Replace all print statements with ScribeLogger
  - Fix empty catch block from current AudioRecorder.swift:139
  - Write tests: recorder lifecycle, Opus encoding, USB-C route detection

  **Must NOT do**:
  - Do NOT save as .m4a/AAC — must be Opus/CAF to match BLE pipeline
  - Do NOT use print statements
  - Do NOT leave empty catch blocks

  **Files Modified**:
  - `Services/AudioService/InternalMicRecorder.swift`
  - `Services/AudioService/OpusEncoder.swift`
  - `ScribeTests/Services/Audio/InternalMicRecorderTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: AVAudioEngine integration with Opus encoding is non-trivial
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 8-11, 13-15 in Wave 2)
  - **Parallel Group**: Wave 2
  - **Blocks**: Task 13
  - **Blocked By**: Tasks 2, 5

  **References**:

  **Pattern References**:
  - Current AudioRecorder: `AudioRecorder.swift` (189 lines) — recording logic
  - Current empty catch: `AudioRecorder.swift:139` — fix pattern with proper error handling
  - Current USB-C detection: routeChangeNotification handling

  **WHY Each Reference Matters**:
  - AudioRecorder.swift: AVAudioEngine setup and session configuration to reuse
  - Empty catch at line 139: must replace with ScribeLogger.error + meaningful handling
  - USB-C detection: route change notification pattern for plug-and-play

  **Acceptance Criteria**:

  - [ ] Internal mic records to Opus/CAF at 16kHz mono
  - [ ] USB-C Plug & Play works (route change detection)
  - [ ] Haptic feedback on start/stop
  - [ ] Empty catch block fixed with proper error handling
  - [ ] All print statements replaced with ScribeLogger

  **QA Scenarios**:

  ```
  Scenario: Internal mic recording produces valid Opus/CAF file
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create InternalMicRecorderTests with simulated AVAudioEngine
      2. Start recording, simulate audio input, stop recording
      3. Verify output file is valid CAF with Opus codec
      4. Run: xcodebuild test -only-testing:ScribeTests/InternalMicRecorderTests
    Expected Result: Valid Opus/CAF file created
    Evidence: .sisyphus/evidence/task-12-recorder-tests.txt

  Scenario: Empty catch blocks are eliminated
    Tool: Bash (grep)
    Steps:
      1. Grep for "catch {" followed by "}" with only whitespace between
      2. Verify zero matches in Services/AudioService/
    Expected Result: Zero empty catch blocks
    Evidence: .sisyphus/evidence/task-12-no-empty-catch.txt
  ```

  **Commit**: YES (groups with 8)
  - Message: `feat(audio): implement internal mic recorder with Opus encoding`

---

- [ ] 13. Audio Service — Unified Recorder + Recording Orchestrator

  **What to do**:
  - Create `Services/AudioService/UnifiedRecorder.swift` — orchestrates recording from either source
    - Accepts AudioRecorderProtocol (internal) and AudioStreamProtocol (BLE) via DI
    - Routes to correct source based on BLE connection state
    - Saves raw Float32 as CAF file (unified format)
    - Records duration, updates Recording entity
  - Create `Services/AudioService/RecordingOrchestrator.swift` — manages recording lifecycle
    - Start: creates Recording, starts correct source
    - Stop: stops source, saves file, updates duration
    - Handles BLE disconnect mid-recording gracefully (falls back to internal or stops cleanly)
  - Replace all print statements with ScribeLogger
  - Write tests: routing logic, BLE disconnect handling, file saving

  **Must NOT do**:
  - Do NOT implement recording logic directly — delegate to internal/BLE recorders
  - Do NOT use print statements

  **Files Modified**:
  - `Services/AudioService/UnifiedRecorder.swift`
  - `Services/AudioService/RecordingOrchestrator.swift`
  - `ScribeTests/Services/Audio/UnifiedRecorderTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Orchestration of two existing services — routing logic
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 14, 15 in Wave 2)
  - **Parallel Group**: Wave 2 (but must wait for T10, T11, T12)
  - **Blocks**: Tasks 21, 35
  - **Blocked By**: Tasks 5, 10, 11, 12

  **References**:

  **Pattern References**:
  - Current UnifiedRecorder: `UnifiedRecorder.swift` (327 lines) — routing logic
  - Current BLE disconnect handling: `DeviceConnectionManager.swift` disconnect callback

  **WHY Each Reference Matters**:
  - UnifiedRecorder.swift: existing routing logic for internal vs BLE source selection
  - Disconnect callback: how BLE disconnection is currently handled mid-recording

  **Acceptance Criteria**:

  - [ ] UnifiedRecorder routes to correct source based on BLE state
  - [ ] BLE disconnect mid-recording handled gracefully (fallback to internal or clean stop)
  - [ ] Output file is always CAF with Opus format
  - [ ] All print statements replaced with ScribeLogger

  **QA Scenarios**:

  ```
  Scenario: UnifiedRecorder routes to BLE when connected
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create UnifiedRecorderTests with MockAudioRecorder and MockAudioStream
      2. Set BLE connection state to connected
      3. Call startRecording(), verify AudioStreamProtocol.startStreaming() called
      4. Run: xcodebuild test -only-testing:ScribeTests/UnifiedRecorderTests
    Expected Result: BLE audio stream started
    Evidence: .sisyphus/evidence/task-13-ble-routing-tests.txt

  Scenario: BLE disconnect mid-recording handled gracefully
    Tool: Bash (xcodebuild test)
    Steps:
      1. Start recording with BLE source
      2. Simulate BLE disconnect notification
      3. Verify recorder stops cleanly and saves partial file
      4. Run: xcodebuild test -only-testing:ScribeTests/UnifiedRecorderTests
    Expected Result: Recording stops cleanly, partial file saved
    Evidence: .sisyphus/evidence/task-13-ble-disconnect-tests.txt
  ```

  **Commit**: YES (groups with 8)
  - Message: `feat(audio): implement unified recorder with BLE disconnect handling`

---

- [ ] 14. Audio Service — Player + Waveform Analyzer + Audio Converter

  **What to do**:
  - Create `Services/AudioService/AudioPlayer.swift` — implements AudioPlayerProtocol
    - Wraps AVAudioPlayer with @Observable state
    - Playback speed: 1.0x → 1.5x → 2.0x → 1.0x
    - Skip: ±15 seconds
    - Seek: via progress tap
    - Session deactivated cleanly on finish/dismiss
  - Create `Services/AudioService/WaveformAnalyzer.swift` — generates waveform data
    - Uses AVAssetReader to decode raw PCM
    - Downsamples to 50 bars by peak-per-bin
    - Normalizes to [0.05, 1.0] range
  - Create `Services/AudioService/AudioConverter.swift` — converts CAF/Opus to Float32 for ASR
    - Handles unified Opus/CAF format from both internal and BLE mics
    - Decodes to [Float32] at 16kHz
    - Proper error handling (no silent failures)
  - Write tests: player lifecycle, speed cycling, waveform generation, format conversion

  **Must NOT do**:
  - Do NOT implement UI — only audio logic
  - Do NOT use print statements
  - Do NOT implement custom codecs — use AVAudioConverter or existing libraries

  **Files Modified**:
  - `Services/AudioService/AudioPlayer.swift`
  - `Services/AudioService/WaveformAnalyzer.swift`
  - `Services/AudioService/AudioConverter.swift`
  - `ScribeTests/Services/Audio/AudioPlayerTests.swift`
  - `ScribeTests/Services/Audio/WaveformAnalyzerTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Audio playback and analysis — copy existing patterns
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 13, 15 in Wave 2)
  - **Parallel Group**: Wave 2
  - **Blocks**: Tasks 23, 35
  - **Blocked By**: Tasks 2, 5

  **References**:

  **Pattern References**:
  - Current AudioPlayer: `AudioPlayer.swift` — playback logic
  - Current WaveformAnalyzer: `WaveformAnalyzer.swift` — 50 bars, peak-per-bin
  - Current AudioConverter: `AudioConverter.swift` — CAF to Float32 conversion

  **WHY Each Reference Matters**:
  - AudioPlayer.swift: playback speed cycling and skip logic
  - WaveformAnalyzer.swift: exact downsampling algorithm (50 bars, peak-per-bin)
  - AudioConverter.swift: format conversion logic — fix CAF-only bug from current code

  **Acceptance Criteria**:

  - [ ] AudioPlayer supports play/pause/seek/speed cycling
  - [ ] WaveformAnalyzer produces 50 normalized bars in [0.05, 1.0]
  - [ ] AudioConverter decodes Opus/CAF to [Float32] at 16kHz
  - [ ] Proper error handling for invalid files (no silent failures)

  **QA Scenarios**:

  ```
  Scenario: AudioPlayer speed cycling works correctly
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create AudioPlayerTests
      2. Verify speed cycles: 1.0 → 1.5 → 2.0 → 1.0
      3. Run: xcodebuild test -only-testing:ScribeTests/AudioPlayerTests
    Expected Result: Speed cycles correctly
    Evidence: .sisyphus/evidence/task-14-player-tests.txt

  Scenario: AudioConverter decodes Opus/CAF correctly
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create AudioConverterTests with test CAF file
      2. Verify output is [Float32] at 16kHz
      3. Verify error thrown for invalid file path
      4. Run: xcodebuild test -only-testing:ScribeTests/AudioConverterTests
    Expected Result: Correct Float32 output, proper error handling
    Evidence: .sisyphus/evidence/task-14-converter-tests.txt
  ```

  **Commit**: YES (groups with 8)
  - Message: `feat(audio): implement player, waveform analyzer, and audio converter`

---

- [ ] 15. Recording Repository (SwiftData)

  **What to do**:
  - Create `Services/RecordingService/RecordingRepository.swift` — implements RecordingRepositoryProtocol
    - save, fetchAll, delete, update methods
    - SwiftData ModelContext operations
    - Proper error handling (no silent failures)
  - Write tests: CRUD operations with in-memory ModelContainer

  **Must NOT do**:
  - Do NOT add business logic — pure data access only
  - Do NOT use print statements

  **Files Modified**:
  - `Services/RecordingService/RecordingRepository.swift`
  - `ScribeTests/Services/Recording/RecordingRepositoryTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Standard CRUD repository pattern
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 13, 14 in Wave 2)
  - **Parallel Group**: Wave 2
  - **Blocks**: Tasks 21, 22, 35
  - **Blocked By**: Tasks 4, 5

  **References**:

  **Pattern References**:
  - Current SwiftData usage: `ScribeApp.swift` — ModelContainer setup
  - Current Recording model: `Models/Recording.swift`

  **WHY Each Reference Matters**:
  - ScribeApp.swift: SwiftData ModelContainer initialization pattern
  - Recording.swift: entity properties that the repository must persist

  **Acceptance Criteria**:

  - [ ] RecordingRepository implements all 4 protocol methods (save, fetchAll, update, delete)
  - [ ] Errors are thrown, not swallowed
  - [ ] Tests use in-memory ModelContainer

  **QA Scenarios**:

  ```
  Scenario: RecordingRepository CRUD operations work
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create RecordingRepositoryTests with in-memory ModelContainer
      2. Test save, fetchAll, update, delete
      3. Run: xcodebuild test -only-testing:ScribeTests/RecordingRepositoryTests
    Expected Result: All CRUD operations work correctly
    Evidence: .sisyphus/evidence/task-15-repository-tests.txt
  ```

  **Commit**: YES (groups with 8)
  - Message: `feat(data): implement RecordingRepository with SwiftData`

---

- [ ] 16. ML Service — VAD Service

  **What to do**:
  - Create `Services/MLService/VAD/VADService.swift` — implements VADServiceProtocol
    - Uses FluidAudio's built-in VAD
    - hasSpeech(audioURL:) returns Bool
    - Loads model, runs inference, nullifies after use (sequential memory management)
  - Create `Services/MLService/VAD/VADConfig.swift` — VAD-specific config (threshold, window size)
  - Write tests: VAD detection with silent and speech audio samples (mocked)

  **Must NOT do**:
  - Do NOT implement custom VAD — use FluidAudio only
  - Do NOT coexist with other ML models in RAM

  **Files Modified**:
  - `Services/MLService/VAD/VADService.swift`
  - `Services/MLService/VAD/VADConfig.swift`
  - `ScribeTests/Services/ML/VADServiceTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: FluidAudio VAD integration — wrap existing API
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 17-19 in Wave 3)
  - **Parallel Group**: Wave 3
  - **Blocks**: Task 20
  - **Blocked By**: Tasks 2, 5

  **References**:

  **Pattern References**:
  - Current InferencePipeline: `InferencePipeline.swift` — model loading and nullification pattern
  - FluidAudio VAD API: check FluidAudio documentation for VAD methods

  **WHY Each Reference Matters**:
  - InferencePipeline.swift: sequential load→run→nil pattern for memory management
  - FluidAudio API: exact method signatures for VAD

  **Acceptance Criteria**:

  - [ ] VADService detects speech in audio with voice
  - [ ] VADService returns false for silent audio
  - [ ] Model is nullified after use (memory management)

  **QA Scenarios**:

  ```
  Scenario: VAD detects speech correctly
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create VADServiceTests with mock audio (speech and silence)
      2. Test hasSpeech() returns true for speech mock
      3. Test hasSpeech() returns false for silence mock
      4. Run: xcodebuild test -only-testing:ScribeTests/VADServiceTests
    Expected Result: VAD correctly identifies speech vs silence
    Evidence: .sisyphus/evidence/task-16-vad-tests.txt
  ```

  **Commit**: YES (groups with 16)
  - Message: `feat(ml): implement VAD service using FluidAudio`

---

- [ ] 17. ML Service — Language Detector

  **What to do**:
  - Create `Services/MLService/ASR/LanguageDetector.swift` — implements LanguageDetectionProtocol
    - Uses Whisper's built-in language detection output
    - Returns LanguageConfidence { language, confidence, isSwissGerman }
    - Threshold for Swiss German detection (configurable in PipelineConfig)
  - Write tests: language detection with mock Whisper output

  **Must NOT do**:
  - Do NOT implement custom language detection — use Whisper's built-in capability

  **Files Modified**:
  - `Services/MLService/ASR/LanguageDetector.swift`
  - `ScribeTests/Services/ML/LanguageDetectorTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Wraps Whisper's existing language confidence output
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 16, 18, 19 in Wave 3)
  - **Parallel Group**: Wave 3
  - **Blocks**: Tasks 18, 20
  - **Blocked By**: Tasks 2, 5

  **References**:

  **Pattern References**:
  - swift-huggingface package: model download and caching API
  - Whisper language detection output format

  **WHY Each Reference Matters**:
  - swift-huggingface: how to access Whisper's language confidence scores
  - Output format: structure of language detection results from CoreML Whisper

  **Acceptance Criteria**:

  - [ ] LanguageDetector returns LanguageConfidence with isSwissGerman flag
  - [ ] Configurable Swiss German detection threshold
  - [ ] Unit tests with mock Whisper output

  **QA Scenarios**:

  ```
  Scenario: LanguageDetector identifies Swiss German
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create LanguageDetectorTests with mock Whisper output
      2. Test Swiss German input returns isSwissGerman=true with high confidence
      3. Test English input returns isSwissGerman=false
      4. Run: xcodebuild test -only-testing:ScribeTests/LanguageDetectorTests
    Expected Result: Language detection works correctly
    Evidence: .sisyphus/evidence/task-17-language-detection-tests.txt
  ```

  **Commit**: YES (groups with 16)
  - Message: `feat(ml): implement language detector using Whisper confidence`

---

- [ ] 18. ML Service — Swiss German Whisper ASR + Fallback ASR

  **What to do**:
  - Create `Services/MLService/ASR/WhisperCoreMLService.swift` — implements TranscriptionServiceProtocol
    - Loads Swiss German Whisper CoreML model from HuggingFace (jlnslv/whisper-large-v3-turbo-swiss-german-coreml)
    - Transcribes [Float32] samples to text
    - Model loaded from HuggingFace on first use, cached in Documents/
  - Create `Services/MLService/ASR/FallbackASRService.swift` — fallback transcription
    - Uses Parakeet (FluidAudio) or general Whisper model
    - Activated when language is NOT Swiss German (by LanguageDetector)
  - Sequential memory management: load → run → nil for each model
  - Write tests: ASR transcription (with mock models)

  **Must NOT do**:
  - Do NOT load multiple models simultaneously (sequential memory management)
  - Do NOT implement custom ASR — use Whisper CoreML or FluidAudio Parakeet

  **Files Modified**:
  - `Services/MLService/ASR/WhisperCoreMLService.swift`
  - `Services/MLService/ASR/FallbackASRService.swift`
  - `ScribeTests/Services/ML/WhisperCoreMLServiceTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: CoreML Whisper integration with HuggingFace model loading is complex
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 16, 17, 19 in Wave 3)
  - **Parallel Group**: Wave 3
  - **Blocks**: Task 20
  - **Blocked By**: Tasks 2, 5, 17

  **References**:

  **Pattern References**:
  - Current TranscriptionService: `InferencePipeline.swift` — Parakeet transcription pattern
  - swift-huggingface package: model download and caching

  **WHY Each Reference Matters**:
  - InferencePipeline.swift: existing ASR integration pattern with sequential memory management
  - swift-huggingface: model download API for HuggingFace-hosted CoreML models

  **Acceptance Criteria**:

  - [ ] WhisperCoreMLService transcribes audio to text
  - [ ] FallbackASRService activates for non-Swiss-German audio
  - [ ] Model downloaded from HuggingFace on first use
  - [ ] Sequential memory management (load → run → nil)

  **QA Scenarios**:

  ```
  Scenario: WhisperCoreMLService transcription works
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create WhisperCoreMLServiceTests with mock CoreML model output
      2. Verify transcription returns text from Float32 audio input
      3. Run: xcodebuild test -only-testing:ScribeTests/WhisperCoreMLServiceTests
    Expected Result: Transcription produces text output
    Evidence: .sisyphus/evidence/task-18-whisper-tests.txt

  Scenario: FallbackASRService activates when not Swiss German
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create FallbackASRServiceTests with mock Parakeet output
      2. Verify FallbackASRService returns transcription for non-Swiss-German audio
      3. Run: xcodebuild test -only-testing:ScribeTests/FallbackASRServiceTests
    Expected Result: Fallback transcription works
    Evidence: .sisyphus/evidence/task-18-fallback-tests.txt
  ```

  **Commit**: YES (groups with 16)
  - Message: `feat(ml): implement Swiss German Whisper ASR with fallback`

---

- [ ] 19. ML Service — Diarization Service

  **What to do**:
  - Create `Services/MLService/Diarization/DiarizationService.swift` — implements DiarizationServiceProtocol
    - Uses FluidAudio's OfflineDiarizerManager (TitaNet-Small)
    - Config: clusteringThreshold 0.35, minSpeakers 1, maxSpeakers 8 (from PipelineConfig)
    - Input: audio file URL
    - Output: [SpeakerSegment] with speakerId, start, end
    - Falls back to single "Speaker 1" segment on failure
    - Model nullified after use (sequential memory management)
  - Write tests: diarization with multi-speaker audio (mocked)

  **Must NOT do**:
  - Do NOT implement custom diarization — use FluidAudio only
  - Do NOT coexist with other ML models in RAM

  **Files Modified**:
  - `Services/MLService/Diarization/DiarizationService.swift`
  - `ScribeTests/Services/ML/DiarizationServiceTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: FluidAudio diarization integration — wrap existing API
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 16-18 in Wave 3)
  - **Parallel Group**: Wave 3
  - **Blocks**: Task 20
  - **Blocked By**: Tasks 2, 5

  **References**:

  **Pattern References**:
  - Current DiarizationService: `InferencePipeline.swift` lines 36-67
  - FluidAudio OfflineDiarizerManager API

  **WHY Each Reference Matters**:
  - InferencePipeline.swift: existing diarization integration with TitaNet-Small
  - OfflineDiarizerManager: exact API for configuration and result handling

  **Acceptance Criteria**:

  - [ ] DiarizationService produces [SpeakerSegment] from audio
  - [ ] Fallback to single speaker on failure
  - [ ] Config-driven thresholds from PipelineConfig
  - [ ] Model nullified after use

  **QA Scenarios**:

  ```
  Scenario: Diarization produces speaker segments
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create DiarizationServiceTests with mock audio
      2. Verify output contains multiple SpeakerSegment entries
      3. Verify fallback to "Speaker 1" on error
      4. Run: xcodebuild test -only-testing:ScribeTests/DiarizationServiceTests
    Expected Result: Diarization produces correct segments, fallback works
    Evidence: .sisyphus/evidence/task-19-diarization-tests.txt
  ```

  **Commit**: YES (groups with 16)
  - Message: `feat(ml): implement diarization service with FluidAudio`

---

- [ ] 20. ML Service — LLM Summarization + Inference Pipeline + Progress Tracker

  **What to do**:
  - Create `Services/MLService/Summarization/LLMService.swift` — implements SummarizationServiceProtocol
    - Uses llama.cpp via LLM.swift package
    - Model: Llama-3.2-3B-Instruct-Q4_K_M.gguf from HuggingFace (bartowski)
    - Downloaded on first use, cached in Documents/
    - Single-pass (≤25,000 chars) or Map→Refine (>25,000 chars)
    - Chunk size: 12,000 chars, overlap: 1,200 chars (from PipelineConfig)
    - Output: MeetingSummary (title, meetingNotes, actionItems, mindMapNodes)
    - Custom Llama 3 chat template
    - Model nullified after use
  - Create `Services/MLService/Pipeline/InferencePipeline.swift` — orchestrates full ML pipeline
    - Stage 1: VAD (hasSpeech?) — skip pipeline if no speech detected
    - Stage 2: Language Detection (isSwissGerman?) — route to correct ASR model
    - Stage 3: ASR (Swiss German Whisper or Fallback) — transcribe audio
    - Stage 4: Diarization (FluidAudio TitaNet) — identify speakers
    - Stage 5: Summarization (Llama 3.2-3B) — generate summary and mind map
    - Sequential model loading: load → run → nil for each stage
    - Supports cancellation via Task.checkCancellation()
    - Timeout per stage (configurable, default 60s)
  - Create `Services/MLService/Pipeline/ProgressTracker.swift` — observable progress reporting
    - Current stage, stage count, stage descriptions, percentage complete
  - Write tests: pipeline orchestration, cancellation, error handling, LLM summarization (mocked)

  **Must NOT do**:
  - Do NOT implement custom LLM inference — use LLM.swift only
  - Do NOT load multiple models simultaneously
  - Do NOT implement ML logic directly in pipeline — delegate to services

  **Files Modified**:
  - `Services/MLService/Summarization/LLMService.swift`
  - `Services/MLService/Pipeline/InferencePipeline.swift`
  - `Services/MLService/Pipeline/ProgressTracker.swift`
  - `ScribeTests/Services/ML/LLMServiceTests.swift`
  - `ScribeTests/Services/ML/InferencePipelineTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: LLM integration with map-refine strategy and 5-stage pipeline orchestration
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on Tasks 16-19)
  - **Parallel Group**: Wave 3 (sequential within wave)
  - **Blocks**: Tasks 24, 27, 35
  - **Blocked By**: Tasks 5, 16, 17, 18, 19

  **References**:

  **Pattern References**:
  - Current LLMService: `LLMService.swift` (363 lines) — split and improve
  - Current prompt templates: `LLMService.swift` lines 58-132
  - Current map-refine logic: chunk splitting with 10% overlap
  - Current InferencePipeline: `InferencePipeline.swift` (211 lines) — orchestration pattern
  - Current sequential memory management: model nullification pattern

  **WHY Each Reference Matters**:
  - LLMService.swift: existing Llama.cpp integration, prompt templates, and map-refine strategy
  - InferencePipeline.swift: existing stage orchestration and cancellation pattern

  **Acceptance Criteria**:

  - [ ] LLMService generates MeetingSummary from transcript
  - [ ] Single-pass for short transcripts, Map→Refine for long
  - [ ] InferencePipeline executes all 5 stages sequentially
  - [ ] VAD skips pipeline if no speech detected
  - [ ] Language detection routes to correct ASR model
  - [ ] Cancellation works mid-pipeline
  - [ ] Progress reporting works
  - [ ] Each stage has timeout and error handling
  - [ ] Sequential memory management (load → run → nil)

  **QA Scenarios**:

  ```
  Scenario: LLMService generates summary from short transcript
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create LLMServiceTests with mocked LLM output
      2. Pass short transcript (<25,000 chars)
      3. Verify MeetingSummary has title, meetingNotes, actionItems, mindMapNodes
      4. Run: xcodebuild test -only-testing:ScribeTests/LLMServiceTests
    Expected Result: Summary generated correctly with single-pass
    Evidence: .sisyphus/evidence/task-20-llm-short-tests.txt

  Scenario: Pipeline skips processing when no speech detected
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create InferencePipelineTests with mocked VAD returning false
      2. Call process(recording:)
      3. Verify ASR, Diarization, Summarization are NOT called
      4. Run: xcodebuild test -only-testing:ScribeTests/InferencePipelineTests
    Expected Result: Pipeline exits early after VAD
    Evidence: .sisyphus/evidence/task-20-vad-skip-tests.txt

  Scenario: Pipeline cancellation works mid-process
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create InferencePipelineTests with slow mock services
      2. Call process(recording:) within Task
      3. Cancel Task after stage 2
      4. Verify stages 3-5 are NOT called
      5. Run: xcodebuild test -only-testing:ScribeTests/InferencePipelineTests
    Expected Result: Pipeline cancels cleanly
    Evidence: .sisyphus/evidence/task-20-cancellation-tests.txt
  ```

  **Commit**: YES (groups with 16)
  - Message: `feat(ml): implement LLM service and inference pipeline with VAD and language detection`

---

- [ ] 21. RecordingListModule Stack

  **What to do**:
  - Create full VIPER stack for RecordingListModule in `Modules/RecordingListModule/`:
  - `Assembly/RecordingListAssembly.swift` — wires Presenter, Interactor, Router, View
  - `Interactor/RecordingListInteractor.swift` + `RecordingListInteractorInput.swift` + `RecordingListInteractorOutput.swift`
    - Business logic: fetch recordings, delete recording, obtain mic source status
    - Holds: RecordingRepositoryProtocol, UnifiedRecorder (via protocol)
    - Weak `output` ref to Presenter
  - `Presenter/RecordingListPresenter.swift` + `RecordingListViewOutput.swift` + `RecordingListViewInput.swift` + `RecordingListModuleInput.swift` + `RecordingListModuleOutput.swift` + `RecordingListState.swift`
    - @Observable: holds recording list state, mic source, loading state
    - Receives View events (didTapRecord, didTapRecording, didTapSettings, didDeleteRecording)
    - Calls Interactor for data, Router for navigation
    - State: recordings array, isRecording, micSource
  - `Router/RecordingListRouter.swift` + `RecordingListRouterInput.swift`
    - openRecordingDetail(with:), openDeviceSettings(), openAgentGenerating()
  - Write tests: Interactor with mocked services, Presenter with mocked Interactor, Assembly wiring

  **Must NOT do**:
  - Do NOT implement View — that's Task 29
  - Do NOT put business logic in Presenter — Presenter only mediates
  - Do NOT access services directly from Presenter — only through Interactor

  **Files Modified**:
  - `Modules/RecordingListModule/Assembly/RecordingListAssembly.swift`
  - `Modules/RecordingListModule/Interactor/RecordingListInteractor.swift`
  - `Modules/RecordingListModule/Interactor/RecordingListInteractorInput.swift`
  - `Modules/RecordingListModule/Interactor/RecordingListInteractorOutput.swift`
  - `Modules/RecordingListModule/Presenter/RecordingListPresenter.swift`
  - `Modules/RecordingListModule/Presenter/RecordingListViewOutput.swift`
  - `Modules/RecordingListModule/Presenter/RecordingListViewInput.swift`
  - `Modules/RecordingListModule/Presenter/RecordingListModuleInput.swift`
  - `Modules/RecordingListModule/Presenter/RecordingListModuleOutput.swift`
  - `Modules/RecordingListModule/Presenter/RecordingListState.swift`
  - `Modules/RecordingListModule/Router/RecordingListRouter.swift`
  - `Modules/RecordingListModule/Router/RecordingListRouterInput.swift`
  - `ScribeTests/Modules/RecordingList/RecordingListInteractorTests.swift`
  - `ScribeTests/Modules/RecordingList/RecordingListPresenterTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: VIPER module stack follows canonical pattern; business logic is list CRUD
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 22-28 in Wave 4)
  - **Parallel Group**: Wave 4
  - **Blocks**: Tasks 29, 35
  - **Blocked By**: Tasks 4, 5, 6, 15

  **References**:

  **Pattern References**:
  - The Book of VIPER: `module-structure.md` — canonical module structure with all layers
  - The Book of VIPER: `code-style.md` — InteractorInput/Output, ViewInput/Output, RouterInput method naming conventions
  - The Book of VIPER: `testing.md` — how to test each VIPER component independently with protocol mocks

  **WHY Each Reference Matters**:
  - module-structure.md: canonical Assembly/Interactor/Presenter/Router/View wiring pattern
  - code-style.md: method naming (imperative for actions, `did` prefix for completions)
  - testing.md: mock-based testing strategy for each component

  **Acceptance Criteria**:

  - [ ] Full VIPER stack created (Assembly, Interactor+protocols, Presenter+protocols, Router+protocol)
  - [ ] Interactor accesses RecordingRepository and UnifiedRecorder via protocols only
  - [ ] Presenter is @Observable, holds state, mediates between View and Interactor
  - [ ] Router handles all navigation (detail, settings, generating)
  - [ ] Assembly wires all components correctly
  - [ ] Unit tests for Interactor and Presenter with mocked dependencies

  **QA Scenarios**:

  ```
  Scenario: RecordingListInteractor fetches recordings
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create RecordingListInteractorTests with MockRecordingRepository
      2. Call obtainRecordings(), verify repository.fetchAll() called
      3. Verify output.didObtainRecordings() called with results
      4. Run: xcodebuild test -only-testing:ScribeTests/RecordingListInteractorTests
    Expected Result: Interactor fetches and returns recordings
    Evidence: .sisyphus/evidence/task-21-interactor-tests.txt

  Scenario: RecordingListPresenter updates state on view load
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create RecordingListPresenterTests with MockInteractor
      2. Call didTriggerViewReady(), verify interactor.obtainRecordings() called
      3. Verify Presenter state updates with recordings
      4. Run: xcodebuild test -only-testing:ScribeTests/RecordingListPresenterTests
    Expected Result: Presenter mediates view load to fetch data
    Evidence: .sisyphus/evidence/task-21-presenter-tests.txt
  ```

  **Commit**: YES (groups with 21)
  - Message: `feat(modules): implement RecordingListModule VIPER stack`

---

- [ ] 22. RecordingDetailModule Stack

  **What to do**:
  - Create full VIPER stack for RecordingDetailModule in `Modules/RecordingDetailModule/`:
  - `Assembly/RecordingDetailAssembly.swift` — wires all components, embeds sub-modules
  - `Interactor/RecordingDetailInteractor.swift` + protocols
    - Business logic: fetch recording details, update recording, coordinate sub-modules
    - Holds: RecordingRepositoryProtocol
    - Receives recording ID via ModuleInput, loads full recording
  - `Presenter/RecordingDetailPresenter.swift` + protocols + `RecordingDetailState.swift`
    - @Observable: holds recording, selected tab, loading state
    - Coordinates sub-module communication via ModuleInput/ModuleOutput
    - State: recording, selectedTab (summary/transcript/mindmap), isProcessing
  - `Router/RecordingDetailRouter.swift` + `RecordingDetailRouterInput.swift`
    - embedWaveformPlayback(), embedTranscript(), embedSummary(), embedMindMap()
  - Write tests: Interactor, Presenter, Assembly

  **Must NOT do**:
  - Do NOT implement View — that's Task 30
  - Do NOT put business logic in Presenter
  - Do NOT access services directly from Presenter

  **Files Modified**:
  - `Modules/RecordingDetailModule/Assembly/RecordingDetailAssembly.swift`
  - `Modules/RecordingDetailModule/Interactor/RecordingDetailInteractor.swift`
  - `Modules/RecordingDetailModule/Interactor/RecordingDetailInteractorInput.swift`
  - `Modules/RecordingDetailModule/Interactor/RecordingDetailInteractorOutput.swift`
  - `Modules/RecordingDetailModule/Presenter/RecordingDetailPresenter.swift`
  - `Modules/RecordingDetailModule/Presenter/RecordingDetailViewOutput.swift`
  - `Modules/RecordingDetailModule/Presenter/RecordingDetailViewInput.swift`
  - `Modules/RecordingDetailModule/Presenter/RecordingDetailModuleInput.swift`
  - `Modules/RecordingDetailModule/Presenter/RecordingDetailModuleOutput.swift`
  - `Modules/RecordingDetailModule/Presenter/RecordingDetailState.swift`
  - `Modules/RecordingDetailModule/Router/RecordingDetailRouter.swift`
  - `Modules/RecordingDetailModule/Router/RecordingDetailRouterInput.swift`
  - `ScribeTests/Modules/RecordingDetail/RecordingDetailInteractorTests.swift`
  - `ScribeTests/Modules/RecordingDetail/RecordingDetailPresenterTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: VIPER module stack; detail screen coordinates sub-modules
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 21, 23-28 in Wave 4)
  - **Parallel Group**: Wave 4
  - **Blocks**: Tasks 30, 35
  - **Blocked By**: Tasks 4, 5, 6, 15

  **References**:

  **Pattern References**:
  - The Book of VIPER: `compound-modules.md` — how parent modules embed and coordinate sub-modules via ModuleInput/ModuleOutput

  **WHY Each Reference Matters**:
  - compound-modules.md: canonical pattern for RecordingDetail as container module with embedded sub-modules (Transcript, Summary, MindMap, WaveformPlayback)

  **Acceptance Criteria**:

  - [ ] Full VIPER stack created
  - [ ] ModuleInput accepts recording ID for configuration
  - [ ] Presenter coordinates sub-module communication via ModuleInput/ModuleOutput
  - [ ] Router handles sub-module embedding
  - [ ] Unit tests for Interactor and Presenter

  **QA Scenarios**:

  ```
  Scenario: RecordingDetailInteractor loads recording by ID
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create tests with MockRecordingRepository
      2. Call configureWith(recordingId:), verify repository fetch called
      3. Run: xcodebuild test -only-testing:ScribeTests/RecordingDetailInteractorTests
    Expected Result: Recording loaded correctly
    Evidence: .sisyphus/evidence/task-22-interactor-tests.txt
  ```

  **Commit**: YES (groups with 21)
  - Message: `feat(modules): implement RecordingDetailModule VIPER stack`

---

- [ ] 23. WaveformPlaybackModule Stack

  **What to do**:
  - Create VIPER stack in `Modules/WaveformPlaybackModule/`:
  - `Assembly/WaveformPlaybackAssembly.swift`
  - `Interactor/WaveformPlaybackInteractor.swift` + protocols
    - Business logic: play/pause/seek, speed cycling, waveform data
    - Holds: AudioPlayerProtocol, WaveformAnalyzerProtocol
    - Methods: obtainWaveformData(), playAudio(), pauseAudio(), seekTo(), cycleSpeed()
  - `Presenter/WaveformPlaybackPresenter.swift` + protocols + `WaveformPlaybackState.swift`
    - @Observable: playback state (isPlaying, currentTime, duration, speed, waveformBars)
    - Forwards playback actions to Interactor, receives results
  - No Router (embedded sub-module, no independent navigation)
  - Write tests: Interactor with mocked AudioPlayer, Presenter

  **Must NOT do**:
  - Do NOT implement View — that's Task 30
  - Do NOT put playback logic in Presenter

  **Files Modified**:
  - `Modules/WaveformPlaybackModule/Assembly/WaveformPlaybackAssembly.swift`
  - `Modules/WaveformPlaybackModule/Interactor/WaveformPlaybackInteractor.swift`
  - `Modules/WaveformPlaybackModule/Interactor/WaveformPlaybackInteractorInput.swift`
  - `Modules/WaveformPlaybackModule/Interactor/WaveformPlaybackInteractorOutput.swift`
  - `Modules/WaveformPlaybackModule/Presenter/WaveformPlaybackPresenter.swift`
  - `Modules/WaveformPlaybackModule/Presenter/WaveformPlaybackViewOutput.swift`
  - `Modules/WaveformPlaybackModule/Presenter/WaveformPlaybackViewInput.swift`
  - `Modules/WaveformPlaybackModule/Presenter/WaveformPlaybackModuleInput.swift`
  - `Modules/WaveformPlaybackModule/Presenter/WaveformPlaybackState.swift`
  - `ScribeTests/Modules/WaveformPlayback/WaveformPlaybackInteractorTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple delegation module — wraps AudioPlayer and WaveformAnalyzer
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 21-22, 24-28 in Wave 4)
  - **Parallel Group**: Wave 4
  - **Blocks**: Tasks 30, 35
  - **Blocked By**: Tasks 5, 6, 14

  **Acceptance Criteria**:

  - [ ] Full VIPER stack created (no Router for embedded module)
  - [ ] Interactor wraps AudioPlayer and WaveformAnalyzer via protocols
  - [ ] Presenter is @Observable with playback state
  - [ ] ModuleInput accepts audio file URL for configuration
  - [ ] Unit tests for Interactor

  **QA Scenarios**:

  ```
  Scenario: WaveformPlaybackInteractor plays audio
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create tests with MockAudioPlayer
      2. Call playAudio(), verify player.play() called
      3. Call cycleSpeed(), verify speed incremented
      4. Run: xcodebuild test -only-testing:ScribeTests/WaveformPlaybackInteractorTests
    Expected Result: Playback delegation works
    Evidence: .sisyphus/evidence/task-23-playback-tests.txt
  ```

  **Commit**: YES (groups with 21)
  - Message: `feat(modules): implement WaveformPlaybackModule VIPER stack`

---

- [ ] 24. TranscriptModule Stack

  **What to do**:
  - Create VIPER stack in `Modules/TranscriptModule/`:
  - `Assembly/TranscriptAssembly.swift`
  - `Interactor/TranscriptInteractor.swift` + protocols
    - Business logic: parse transcript text into SpeakerSegments, rename speaker across all fields
    - Holds: RecordingRepositoryProtocol
    - Methods: obtainTranscriptSegments(), renameSpeaker(from:to:)
    - renameSpeaker updates rawTranscript, actionItems, AND meetingNotes JSON
  - `Presenter/TranscriptPresenter.swift` + protocols + `TranscriptState.swift`
    - @Observable: parsed segments, selected speaker for rename
    - Handles rename flow: View taps speaker → Presenter asks Interactor to rename
  - No Router (embedded sub-module)
  - Write tests: Interactor rename logic, Presenter mediation

  **Must NOT do**:
  - Do NOT implement View — that's Task 31
  - Do NOT put parsing or rename logic in Presenter

  **Files Modified**:
  - `Modules/TranscriptModule/Assembly/TranscriptAssembly.swift`
  - `Modules/TranscriptModule/Interactor/TranscriptInteractor.swift`
  - `Modules/TranscriptModule/Interactor/TranscriptInteractorInput.swift`
  - `Modules/TranscriptModule/Interactor/TranscriptInteractorOutput.swift`
  - `Modules/TranscriptModule/Presenter/TranscriptPresenter.swift`
  - `Modules/TranscriptModule/Presenter/TranscriptViewOutput.swift`
  - `Modules/TranscriptModule/Presenter/TranscriptViewInput.swift`
  - `Modules/TranscriptModule/Presenter/TranscriptModuleInput.swift`
  - `Modules/TranscriptModule/Presenter/TranscriptState.swift`
  - `ScribeTests/Modules/Transcript/TranscriptInteractorTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Transcript parsing and speaker rename logic
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 21-23, 25-28 in Wave 4)
  - **Parallel Group**: Wave 4
  - **Blocks**: Tasks 31, 35
  - **Blocked By**: Tasks 5, 6, 20

  **References**:

  **Pattern References**:
  - Current transcript parsing: `RecordingDetailView.swift` — TranscriptInteractiveView parsing pattern
  - Current speaker rename: lines 249-267 — fix to include meetingNotes

  **WHY Each Reference Matters**:
  - TranscriptInteractiveView: existing [Speaker N - MM:SS] parsing pattern
  - Speaker rename: current code only updates rawTranscript + actionItems — must also update meetingNotes JSON

  **Acceptance Criteria**:

  - [ ] Full VIPER stack created
  - [ ] Interactor parses [Speaker N - MM:SS] format into SpeakerSegments
  - [ ] renameSpeaker updates rawTranscript, actionItems, AND meetingNotes
  - [ ] ModuleInput accepts recording for configuration
  - [ ] Unit tests for parsing and rename

  **QA Scenarios**:

  ```
  Scenario: RenameSpeaker updates all three fields
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create TranscriptInteractorTests with MockRecordingRepository
      2. Create Recording with rawTranscript, actionItems, meetingNotes containing "Speaker 1"
      3. Call renameSpeaker(from: "Speaker 1", to: "John")
      4. Verify all 3 fields updated in repository
      5. Run: xcodebuild test -only-testing:ScribeTests/TranscriptInteractorTests
    Expected Result: All three fields updated correctly
    Evidence: .sisyphus/evidence/task-24-rename-tests.txt
  ```

  **Commit**: YES (groups with 21)
  - Message: `feat(modules): implement TranscriptModule VIPER stack`

---

- [ ] 25. SummaryModule Stack

  **What to do**:
  - Create VIPER stack in `Modules/SummaryModule/`:
  - `Assembly/SummaryAssembly.swift`
  - `Interactor/SummaryInteractor.swift` + protocols
    - Business logic: obtain summary data, parse TopicSections
    - Holds: RecordingRepositoryProtocol
  - `Presenter/SummaryPresenter.swift` + protocols + `SummaryState.swift`
    - @Observable: topic sections, action items, loading state
  - No Router (embedded sub-module)
  - Write tests: Interactor, Presenter

  **Must NOT do**:
  - Do NOT implement View — that's Task 31

  **Files Modified**:
  - `Modules/SummaryModule/Assembly/SummaryAssembly.swift`
  - `Modules/SummaryModule/Interactor/SummaryInteractor.swift`
  - `Modules/SummaryModule/Interactor/SummaryInteractorInput.swift`
  - `Modules/SummaryModule/Interactor/SummaryInteractorOutput.swift`
  - `Modules/SummaryModule/Presenter/SummaryPresenter.swift`
  - `Modules/SummaryModule/Presenter/SummaryViewOutput.swift`
  - `Modules/SummaryModule/Presenter/SummaryViewInput.swift`
  - `Modules/SummaryModule/Presenter/SummaryModuleInput.swift`
  - `Modules/SummaryModule/Presenter/SummaryState.swift`
  - `ScribeTests/Modules/Summary/SummaryInteractorTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple read-only module — fetch and display summary
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 21-24, 26-28 in Wave 4)
  - **Parallel Group**: Wave 4
  - **Blocks**: Tasks 31, 35
  - **Blocked By**: Tasks 4, 5, 6

  **Acceptance Criteria**:

  - [ ] Full VIPER stack created
  - [ ] Interactor obtains and parses summary from Recording
  - [ ] Presenter is @Observable with summary state

  **QA Scenarios**:

  ```
  Scenario: SummaryInteractor obtains summary data
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create tests with MockRecordingRepository returning recording with meetingNotes
      2. Call obtainSummary(), verify parsed TopicSections returned
      3. Run: xcodebuild test -only-testing:ScribeTests/SummaryInteractorTests
    Expected Result: Summary parsed correctly
    Evidence: .sisyphus/evidence/task-25-summary-tests.txt
  ```

  **Commit**: YES (groups with 21)
  - Message: `feat(modules): implement SummaryModule VIPER stack`

---

- [ ] 26. MindMapModule Stack

  **What to do**:
  - Create VIPER stack in `Modules/MindMapModule/`:
  - `Assembly/MindMapAssembly.swift`
  - `Interactor/MindMapInteractor.swift` + protocols
    - Business logic: obtain and parse MindMapNode tree
    - Holds: RecordingRepositoryProtocol
  - `Presenter/MindMapPresenter.swift` + protocols + `MindMapState.swift`
    - @Observable: mind map nodes, loading state
  - No Router (embedded sub-module)
  - Write tests: Interactor, Presenter

  **Must NOT do**:
  - Do NOT implement View — that's Task 32

  **Files Modified**:
  - `Modules/MindMapModule/Assembly/MindMapAssembly.swift`
  - `Modules/MindMapModule/Interactor/MindMapInteractor.swift`
  - `Modules/MindMapModule/Interactor/MindMapInteractorInput.swift`
  - `Modules/MindMapModule/Interactor/MindMapInteractorOutput.swift`
  - `Modules/MindMapModule/Presenter/MindMapPresenter.swift`
  - `Modules/MindMapModule/Presenter/MindMapViewOutput.swift`
  - `Modules/MindMapModule/Presenter/MindMapViewInput.swift`
  - `Modules/MindMapModule/Presenter/MindMapModuleInput.swift`
  - `Modules/MindMapModule/Presenter/MindMapState.swift`
  - `ScribeTests/Modules/MindMap/MindMapInteractorTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple read-only module — fetch and display mind map tree
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 21-25, 27-28 in Wave 4)
  - **Parallel Group**: Wave 4
  - **Blocks**: Tasks 32, 35
  - **Blocked By**: Tasks 4, 5, 6

  **Acceptance Criteria**:

  - [ ] Full VIPER stack created
  - [ ] Interactor parses MindMapNode JSON tree
  - [ ] Presenter is @Observable with nodes state

  **QA Scenarios**:

  ```
  Scenario: MindMapInteractor parses node tree
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create tests with MockRecordingRepository returning recording with mindMapJSON
      2. Call obtainMindMap(), verify recursive MindMapNode tree parsed
      3. Run: xcodebuild test -only-testing:ScribeTests/MindMapInteractorTests
    Expected Result: Mind map parsed into tree structure
    Evidence: .sisyphus/evidence/task-26-mindmap-tests.txt
  ```

  **Commit**: YES (groups with 21)
  - Message: `feat(modules): implement MindMapModule VIPER stack`

---

- [ ] 27. AgentGeneratingModule Stack

  **What to do**:
  - Create VIPER stack in `Modules/AgentGeneratingModule/`:
  - `Assembly/AgentGeneratingAssembly.swift`
  - `Interactor/AgentGeneratingInteractor.swift` + protocols
    - Business logic: start ML pipeline, observe progress, cancel pipeline
    - Holds: InferencePipeline (via protocol)
    - Methods: startProcessing(recordingId:), cancelProcessing()
  - `Presenter/AgentGeneratingPresenter.swift` + protocols + `AgentGeneratingState.swift`
    - @Observable: processing stage, progress percentage, isProcessing
    - Receives progress updates from Interactor, updates state for View
  - No Router (presented modally, dismissed by parent)
  - Write tests: Interactor pipeline delegation, Presenter progress tracking

  **Must NOT do**:
  - Do NOT implement View — that's Task 33
  - Do NOT implement pipeline logic — delegate to InferencePipeline service

  **Files Modified**:
  - `Modules/AgentGeneratingModule/Assembly/AgentGeneratingAssembly.swift`
  - `Modules/AgentGeneratingModule/Interactor/AgentGeneratingInteractor.swift`
  - `Modules/AgentGeneratingModule/Interactor/AgentGeneratingInteractorInput.swift`
  - `Modules/AgentGeneratingModule/Interactor/AgentGeneratingInteractorOutput.swift`
  - `Modules/AgentGeneratingModule/Presenter/AgentGeneratingPresenter.swift`
  - `Modules/AgentGeneratingModule/Presenter/AgentGeneratingViewOutput.swift`
  - `Modules/AgentGeneratingModule/Presenter/AgentGeneratingViewInput.swift`
  - `Modules/AgentGeneratingModule/Presenter/AgentGeneratingModuleInput.swift`
  - `Modules/AgentGeneratingModule/Presenter/AgentGeneratingModuleOutput.swift`
  - `Modules/AgentGeneratingModule/Presenter/AgentGeneratingState.swift`
  - `ScribeTests/Modules/AgentGenerating/AgentGeneratingInteractorTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Delegation module — wraps InferencePipeline with progress observation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 21-26, 28 in Wave 4)
  - **Parallel Group**: Wave 4
  - **Blocks**: Tasks 33, 35
  - **Blocked By**: Tasks 5, 6, 20

  **Acceptance Criteria**:

  - [ ] Full VIPER stack created
  - [ ] Interactor delegates to InferencePipeline
  - [ ] Presenter tracks progress and updates state
  - [ ] ModuleOutput reports completion/failure to parent
  - [ ] Cancellation supported

  **QA Scenarios**:

  ```
  Scenario: AgentGeneratingInteractor starts pipeline
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create tests with MockInferencePipeline
      2. Call startProcessing(recordingId:), verify pipeline.process() called
      3. Call cancelProcessing(), verify pipeline.cancel() called
      4. Run: xcodebuild test -only-testing:ScribeTests/AgentGeneratingInteractorTests
    Expected Result: Pipeline delegation works
    Evidence: .sisyphus/evidence/task-27-generating-tests.txt
  ```

  **Commit**: YES (groups with 21)
  - Message: `feat(modules): implement AgentGeneratingModule VIPER stack`

---

- [ ] 28. DeviceSettingsModule Stack

  **What to do**:
  - Create VIPER stack in `Modules/DeviceSettingsModule/`:
  - `Assembly/DeviceSettingsAssembly.swift`
  - `Interactor/DeviceSettingsInteractor.swift` + protocols
    - Business logic: scan for devices, connect/disconnect, obtain connection state
    - Holds: BluetoothDeviceScannerProtocol, DeviceConnectionManagerProtocol
    - Methods: startScan(), connectToDevice(), disconnect()
  - `Presenter/DeviceSettingsPresenter.swift` + protocols + `DeviceSettingsState.swift`
    - @Observable: discovered devices, connection state, isScanning
    - Receives View events (didTapScan, didTapDevice, didTapDisconnect)
  - `Router/DeviceSettingsRouter.swift` + `DeviceSettingsRouterInput.swift`
    - closeCurrentModule()
  - Write tests: Interactor with mocked BLE services, Presenter

  **Must NOT do**:
  - Do NOT implement View — that's Task 34
  - Do NOT put BLE logic in Presenter

  **Files Modified**:
  - `Modules/DeviceSettingsModule/Assembly/DeviceSettingsAssembly.swift`
  - `Modules/DeviceSettingsModule/Interactor/DeviceSettingsInteractor.swift`
  - `Modules/DeviceSettingsModule/Interactor/DeviceSettingsInteractorInput.swift`
  - `Modules/DeviceSettingsModule/Interactor/DeviceSettingsInteractorOutput.swift`
  - `Modules/DeviceSettingsModule/Presenter/DeviceSettingsPresenter.swift`
  - `Modules/DeviceSettingsModule/Presenter/DeviceSettingsViewOutput.swift`
  - `Modules/DeviceSettingsModule/Presenter/DeviceSettingsViewInput.swift`
  - `Modules/DeviceSettingsModule/Presenter/DeviceSettingsModuleInput.swift`
  - `Modules/DeviceSettingsModule/Presenter/DeviceSettingsState.swift`
  - `Modules/DeviceSettingsModule/Router/DeviceSettingsRouter.swift`
  - `Modules/DeviceSettingsModule/Router/DeviceSettingsRouterInput.swift`
  - `ScribeTests/Modules/DeviceSettings/DeviceSettingsInteractorTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: VIPER module stack; BLE service delegation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 21-27 in Wave 4)
  - **Parallel Group**: Wave 4
  - **Blocks**: Tasks 34, 35
  - **Blocked By**: Tasks 5, 6, 10

  **Acceptance Criteria**:

  - [ ] Full VIPER stack created
  - [ ] Interactor accesses BLE services via protocols only
  - [ ] Presenter is @Observable with BLE state
  - [ ] Router handles module dismissal
  - [ ] Unit tests for Interactor and Presenter

  **QA Scenarios**:

  ```
  Scenario: DeviceSettingsInteractor scans for devices
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create tests with MockBluetoothDeviceScanner
      2. Call startScan(), verify scanner.startScan() called
      3. Verify output.didDiscoverDevices() called with results
      4. Run: xcodebuild test -only-testing:ScribeTests/DeviceSettingsInteractorTests
    Expected Result: Scan delegation works
    Evidence: .sisyphus/evidence/task-28-settings-tests.txt
  ```

  **Commit**: YES (groups with 21)
  - Message: `feat(modules): implement DeviceSettingsModule VIPER stack`

---

- [ ] 29. RecordingListModule Views (ListView, CardView, RecordButtonView)

  **What to do**:
  - Create `Modules/RecordingListModule/View/RecordingListView.swift`
    - NavigationStack root, PlainListStyle
    - DashboardHeaderView (placeholder)
    - RecordingCardView per recording, sorted by createdAt
    - Empty state with mic.slash icon
    - Toolbar: mic.badge.plus button (scribeRed)
    - Bottom: mic indicator badge, RecordButtonView
    - Background: dark = Color.black, light = Color.gray.opacity(0.1)
    - **STRICT VIPER**: View reads ALL state from Presenter (output). Zero business logic. User actions call Presenter methods (didTapRecord, didTapRecording, didTapSettings).
  - Create `Modules/RecordingListModule/View/RecordingCardView.swift`
    - scribeCardStyle, title (headline bold, lineLimit 2), duration badge
    - Category tag (scribeRed tinted), date/time
    - Pure rendering — no data transformation
  - Create `Modules/RecordingListModule/View/RecordButtonView.swift`
    - 80x80 outer circle, 70x70 inner circle
    - Outer ring: scribeRed.opacity(0.3), scaleEffect 1.5x when recording
    - Inner: scribeRed (0.8 opacity when recording), shadow radius 10
    - Recording: 24x24 white stop icon; Idle: mic.fill SF Symbol (28pt bold white)
    - Animation: easeInOut 1.5s repeatForever when recording
    - Disabled: opacity 0.5 when not available
    - Calls output.didTapRecord() on tap
  - Write tests: view renders Presenter state correctly

  **Must NOT do**:
  - Do NOT change any visual appearance — exact match required
  - Do NOT put any business logic in View — all logic via Presenter

  **Files Modified**:
  - `Modules/RecordingListModule/View/RecordingListView.swift`
  - `Modules/RecordingListModule/View/RecordingCardView.swift`
  - `Modules/RecordingListModule/View/RecordButtonView.swift`

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Pixel-perfect UI implementation with animations
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 30-34 in Wave 5)
  - **Parallel Group**: Wave 5
  - **Blocks**: Task 35
  - **Blocked By**: Task 21

  **References**:

  **Pattern References**:
  - Current RecordingListView: `RecordingListView.swift` (188 lines)
  - Current RecordingCardView: `RecordingCardView.swift`
  - Current RecordButtonView: `RecordButtonView.swift` — exact animation and layout
  - The Book of VIPER: `module-structure.md` — View is passive, only forwards actions to Presenter

  **WHY Each Reference Matters**:
  - Existing views: pixel-perfect layout, animations, and visual details
  - VIPER module-structure: View MUST NOT contain business logic

  **Acceptance Criteria**:

  - [ ] RecordingListView reads state from Presenter only
  - [ ] All user actions forwarded to Presenter (didTapRecord, didTapRecording, didTapSettings)
  - [ ] RecordingCardView matches current card design exactly
  - [ ] RecordButtonView matches current design exactly (1.5s easeInOut animation)
  - [ ] Zero business logic in View files

  **QA Scenarios**:

  ```
  Scenario: Recording list displays recordings from Presenter state
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create RecordingListViewTests
      2. Set Presenter state with 3 mock recordings
      3. Verify list renders 3 cards
      4. Run: xcodebuild test -only-testing:ScribeTests/RecordingListViewTests
    Expected Result: List displays 3 recordings from Presenter state
    Evidence: .sisyphus/evidence/task-29-list-tests.txt

  Scenario: Record button forwards tap to Presenter
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create RecordButtonViewTests
      2. Tap button, verify output.didTapRecord() called
      3. Run: xcodebuild test -only-testing:ScribeTests/RecordButtonViewTests
    Expected Result: Tap forwarded to Presenter
    Evidence: .sisyphus/evidence/task-29-button-tests.txt

  Human Verification: Visual match of list screen, card design, and record button animation
  ```

  **Commit**: YES (groups with 29)
  - Message: `feat(ui): implement RecordingListModule views with pixel-perfect design`

---

- [ ] 30. RecordingDetail + WaveformPlayback Views

  **What to do**:
  - Create `Modules/RecordingDetailModule/View/RecordingDetailView.swift`
    - ZStack with bottom floating CTA
    - Error banner (if Presenter state has error)
    - Segmented picker: Summary | Transcript | Mind Map
    - ScrollView with selected tab content
    - Embedded WaveformPlaybackView at top
    - **STRICT VIPER**: View reads recording, selectedTab, error from Presenter. User actions (didSelectTab, didTapGenerate) forwarded to Presenter.
  - Create `Modules/WaveformPlaybackModule/View/WaveformPlaybackView.swift`
    - 50 bars, bar spacing 3pt, corner radius 2pt, min height 4pt
    - Played portion: scribeRed, unplayed: secondary.opacity(0.3)
    - Playback controls: skip backward (15s), play/pause (44pt, scribeRed), skip forward (15s), speed capsule
    - **STRICT VIPER**: reads isPlaying, currentTime, duration, speed, waveformBars from Presenter. Actions (didTapPlay, didSkipBack, didSkipForward, didSeek, didCycleSpeed) forwarded.
  - Write tests: views render Presenter state

  **Must NOT do**:
  - Do NOT change any visual appearance or layout
  - Do NOT put playback logic in View

  **Files Modified**:
  - `Modules/RecordingDetailModule/View/RecordingDetailView.swift`
  - `Modules/WaveformPlaybackModule/View/WaveformPlaybackView.swift`

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Complex UI with waveform and playback controls
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 29, 31-34 in Wave 5)
  - **Parallel Group**: Wave 5
  - **Blocks**: Task 35
  - **Blocked By**: Tasks 22, 23

  **References**:

  **Pattern References**:
  - Current RecordingDetailView: `RecordingDetailView.swift` (487 lines)
  - Current WaveformView: embedded in RecordingDetailView

  **Acceptance Criteria**:

  - [ ] RecordingDetailView reads state from Presenter only
  - [ ] WaveformPlaybackView reads playback state from Presenter only
  - [ ] All user actions forwarded to Presenter
  - [ ] Waveform renders 50 bars correctly
  - [ ] Tab switching works via Presenter state
  - [ ] Zero business logic in View files

  **QA Scenarios**:

  ```
  Scenario: Recording detail displays recording from Presenter state
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create RecordingDetailViewTests
      2. Set Presenter state with mock recording
      3. Verify waveform, controls, tabs render
      4. Run: xcodebuild test -only-testing:ScribeTests/RecordingDetailViewTests
    Expected Result: Detail screen renders from Presenter state
    Evidence: .sisyphus/evidence/task-30-detail-tests.txt

  Human Verification: Visual match of detail screen, waveform, and playback controls
  ```

  **Commit**: YES (groups with 29)
  - Message: `feat(ui): implement RecordingDetail and WaveformPlayback views`

---

- [ ] 31. Transcript + Summary Views

  **What to do**:
  - Create `Modules/TranscriptModule/View/TranscriptTabView.swift`
    - Displays speaker segments from Presenter state
    - Tap speaker label → Presenter handles rename flow (didTapSpeaker)
    - Rename alert triggered by Presenter state (showRenameAlert, selectedSpeaker)
    - **STRICT VIPER**: reads segments from Presenter, forwards tap events
  - Create `Modules/SummaryModule/View/SummaryTabView.swift`
    - Renders TopicSections as headed lists
    - Action items as markdown bullet list with speaker attribution
    - Empty state: doc.text.magnifyingglass icon
    - **STRICT VIPER**: reads summary data from Presenter only
  - Write tests: views render Presenter state

  **Must NOT do**:
  - Do NOT put parsing or rename logic in View
  - Do NOT change transcript format or visual appearance

  **Files Modified**:
  - `Modules/TranscriptModule/View/TranscriptTabView.swift`
  - `Modules/SummaryModule/View/SummaryTabView.swift`

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Interactive UI with rename flow
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 29-30, 32-34 in Wave 5)
  - **Parallel Group**: Wave 5
  - **Blocks**: Task 35
  - **Blocked By**: Tasks 24, 25

  **References**:

  **Pattern References**:
  - Current transcript parsing: `RecordingDetailView.swift` — TranscriptInteractiveView
  - Current summary rendering: `RecordingDetailView.swift` — summary tab

  **Acceptance Criteria**:

  - [ ] TranscriptTabView reads segments from Presenter
  - [ ] Speaker tap forwards to Presenter (didTapSpeaker)
  - [ ] Rename alert triggered by Presenter state
  - [ ] SummaryTabView reads TopicSections from Presenter
  - [ ] Zero business logic in View files

  **QA Scenarios**:

  ```
  Scenario: Transcript view forwards speaker tap to Presenter
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create TranscriptTabViewTests
      2. Set Presenter state with segments
      3. Tap speaker label, verify output.didTapSpeaker() called
      4. Run: xcodebuild test -only-testing:ScribeTests/TranscriptTabViewTests
    Expected Result: Tap forwarded to Presenter
    Evidence: .sisyphus/evidence/task-31-transcript-tests.txt

  Human Verification: Visual match of transcript and summary tabs, rename alert behavior
  ```

  **Commit**: YES (groups with 29)
  - Message: `feat(ui): implement Transcript and Summary views`

---

- [ ] 32. MindMap View

  **What to do**:
  - Create `Modules/MindMapModule/View/MindMapView.swift`
    - Recursive tree rendering of MindMapNode from Presenter state
    - Branch connectors between nodes
    - Depth-based styling (at least 2 levels)
    - Empty state: network icon
    - **STRICT VIPER**: reads nodes from Presenter only
  - Write tests: view renders node tree

  **Must NOT do**:
  - Do NOT change mind map rendering logic

  **Files Modified**:
  - `Modules/MindMapModule/View/MindMapView.swift`

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Recursive tree UI component
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 29-31, 33-34 in Wave 5)
  - **Parallel Group**: Wave 5
  - **Blocks**: Task 35
  - **Blocked By**: Task 26

  **References**:

  **Pattern References**:
  - Current MindMapView: `RecordingDetailView.swift` lines 358-399

  **Acceptance Criteria**:

  - [ ] MindMapView reads nodes from Presenter state
  - [ ] Recursive tree renders with branch connectors
  - [ ] Empty state displays correctly

  **QA Scenarios**:

  ```
  Scenario: MindMap renders tree from Presenter state
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create MindMapViewTests
      2. Set Presenter state with mock MindMapNode tree
      3. Verify recursive rendering
      4. Run: xcodebuild test -only-testing:ScribeTests/MindMapViewTests
    Expected Result: Tree renders from Presenter state
    Evidence: .sisyphus/evidence/task-32-mindmap-tests.txt

  Human Verification: Visual match of mind map tree
  ```

  **Commit**: YES (groups with 29)
  - Message: `feat(ui): implement MindMap view`

---

- [ ] 33. AgentGenerating View

  **What to do**:
  - Create `Modules/AgentGeneratingModule/View/AgentGeneratingView.swift`
    - iOS 18+: MeshGradient with scribeRed, indigo, black
    - Fallback: LinearGradient with black, scribeRed.opacity(0.8), indigo
    - Pulsating circles: 140pt, 100pt, 80pt with waveform.circle.fill icon
    - "ARTIFICIAL INTELLIGENCE" text (headline, white 0.7)
    - Progress text (title3, white) with .contentTransition(.numericText())
    - Capsule progress bar (250x6pt, scribeRed)
    - Animations: mesh points 4.0s easeInOut repeatForever, circle pulse 1.5s easeInOut repeatForever
    - **STRICT VIPER**: reads progress stage and percentage from Presenter. User action: didTapCancel forwarded.
  - Write tests: view renders Presenter state

  **Must NOT do**:
  - Do NOT change animation timing or gradient colors

  **Files Modified**:
  - `Modules/AgentGeneratingModule/View/AgentGeneratingView.swift`

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Animated gradient screen with mesh effects
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 29-32, 34 in Wave 5)
  - **Parallel Group**: Wave 5
  - **Blocks**: Task 35
  - **Blocked By**: Task 27

  **References**:

  **Pattern References**:
  - Current AgentGeneratingView: `AgentGeneratingView.swift` — exact animations and layout

  **Acceptance Criteria**:

  - [ ] MeshGradient with correct colors and 4.0s animation
  - [ ] Pulsating circles with 1.5s animation
  - [ ] Progress reads from Presenter state
  - [ ] Cancel forwards to Presenter

  **QA Scenarios**:

  ```
  Scenario: AgentGenerating view reads progress from Presenter
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create AgentGeneratingViewTests
      2. Set Presenter state with progress stage and percentage
      3. Verify progress text matches Presenter state
      4. Run: xcodebuild test -only-testing:ScribeTests/AgentGeneratingViewTests
    Expected Result: Progress text matches Presenter
    Evidence: .sisyphus/evidence/task-33-generating-tests.txt

  Human Verification: Visual match of mesh gradient, circle animations, and progress bar
  ```

  **Commit**: YES (groups with 29)
  - Message: `feat(ui): implement AgentGenerating view with mesh gradient`

---

- [ ] 34. DeviceSettings Views

  **What to do**:
  - Create `Modules/DeviceSettingsModule/View/DeviceSettingsView.swift`
    - ConnectionStatusCard (scribeCardStyle): status dot, device name, Disconnect button
    - DeviceListCard (scribeCardStyle): scan button, device list with RSSI/battery
    - DeviceRow: mic icon, name, RSSI badge, battery, chevron
    - Status colors: connected/green, connecting/yellow, failed/scribeRed, disconnected/secondary
    - ScanButton: triggers 10-second scan
    - **STRICT VIPER**: reads devices, connection state, isScanning from Presenter. Actions (didTapScan, didTapDevice, didTapDisconnect) forwarded.
  - Write tests: view renders Presenter state

  **Must NOT do**:
  - Do NOT change any visual appearance
  - Do NOT modify BLE protocol logic
  - Do NOT wrap @Observable classes in @State (fix current anti-pattern)

  **Files Modified**:
  - `Modules/DeviceSettingsModule/View/DeviceSettingsView.swift`

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Settings UI with BLE state display
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 29-33 in Wave 5)
  - **Parallel Group**: Wave 5
  - **Blocks**: Task 35
  - **Blocked By**: Task 28

  **References**:

  **Pattern References**:
  - Current DeviceSettingsView: `DeviceSettingsView.swift` (341 lines)
  - Current FIX comment: line 9 — @Observable/@State anti-pattern to avoid

  **Acceptance Criteria**:

  - [ ] DeviceSettingsView reads state from Presenter only
  - [ ] @Observable used correctly (no @State wrapping)
  - [ ] Connection status displays correctly from Presenter state
  - [ ] All user actions forwarded to Presenter

  **QA Scenarios**:

  ```
  Scenario: DeviceSettings view renders connection state
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create DeviceSettingsViewTests
      2. Set Presenter state with connected device
      3. Verify status card shows connected (green)
      4. Set Presenter state with discovered devices
      5. Verify device list renders
      6. Run: xcodebuild test -only-testing:ScribeTests/DeviceSettingsViewTests
    Expected Result: Settings view renders from Presenter state
    Evidence: .sisyphus/evidence/task-34-settings-tests.txt

  Human Verification: Visual match of device settings screen, scan flow, connection status
  ```

  **Commit**: YES (groups with 29)
  - Message: `feat(ui): implement DeviceSettings views for BLE pairing`

---

- [ ] 35. App Wiring (ScribeApp.swift + AppAssembly + NavigationStack)

  **What to do**:
  - Update `App/ScribeApp.swift` — @main entry point
    - SwiftData ModelContainer with on-disk persistence
    - AppAssembly setup for root module
    - .preferredColorScheme(.dark)
    - WindowGroup with RecordingListModule View as root
  - Update `App/AppAssembly.swift` — wire real service implementations
    - Replace all service stubs with real implementations from Services/
    - Register all 8 module Assemblies
    - Inject services into module Interactors via module Assemblies
  - Wire navigation: RecordingListModule Router → RecordingDetailModule (push), DeviceSettingsModule (sheet), AgentGeneratingModule (sheet)
  - Wire all ModuleInput/ModuleOutput for inter-module communication
  - Wire sub-module embedding in RecordingDetailModule
  - Write tests: full app assembly creates all modules with real services

  **Must NOT do**:
  - Do NOT implement business logic in App layer
  - Do NOT use global singletons — all DI through Assembly chain

  **Files Modified**:
  - `App/ScribeApp.swift`
  - `App/AppAssembly.swift`
  - `App/ServiceRegistry.swift`
  - `ScribeTests/App/AppAssemblyTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Wiring task — connecting existing components
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on all module stacks and views)
  - **Parallel Group**: Wave 6
  - **Blocks**: Tasks 36, 37
  - **Blocked By**: Tasks 13, 14, 15, 20, 21-34

  **References**:

  **Pattern References**:
  - Current ScribeApp: `ScribeApp.swift` — ModelContainer setup
  - Current navigation: RecordingListView NavigationStack pattern
  - The Book of VIPER: `module-transitions.md` — ModuleInput/ModuleOutput for inter-module data passing

  **WHY Each Reference Matters**:
  - ScribeApp.swift: SwiftData ModelContainer initialization
  - Navigation pattern: NavigationStack push and sheet presentation
  - Module transitions: canonical VIPER approach for passing data between modules

  **Acceptance Criteria**:

  - [ ] ScribeApp launches with SwiftData and VIPER Assembly
  - [ ] AppAssembly provides all 8 module Views with wired dependencies
  - [ ] Navigation works: list → detail, settings sheet, generating sheet
  - [ ] All sub-modules embedded in RecordingDetail
  - [ ] ModuleInput/ModuleOutput communication works
  - [ ] Dark mode forced

  **QA Scenarios**:

  ```
  Scenario: App launches and displays recording list
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create AppAssemblyTests
      2. Verify all module factories return valid Views
      3. Verify all services are real implementations (not stubs)
      4. Run: xcodebuild test -only-testing:ScribeTests/AppAssemblyTests
    Expected Result: All modules and services resolve
    Evidence: .sisyphus/evidence/task-35-assembly-tests.txt

  Scenario: Full app builds and runs
    Tool: Bash (xcodebuild)
    Steps:
      1. Run: xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' build
      2. Verify exit code 0
    Expected Result: BUILD SUCCEEDED
    Evidence: .sisyphus/evidence/task-35-app-build.txt

  Human Verification: App launches, shows recording list, can navigate to detail
  ```

  **Commit**: YES (groups with 35)
  - Message: `feat(app): wire ScribeApp with VIPER Assembly and NavigationStack`

---

- [ ] 36. Integration — Error Handling + Edge Cases + End-to-End Tests

  **What to do**:
  - Create integration tests for full recording lifecycle:
    1. Start recording (internal or BLE)
    2. Stop recording
    3. Recording saved to SwiftData
    4. ML pipeline processes recording
    5. Transcript, summary, mind map generated
    6. UI displays results via VIPER modules
  - Test error scenarios across all layers:
    - BLE disconnect mid-recording
    - ML pipeline failure at each stage
    - Empty recording (no speech detected by VAD)
    - App backgrounded during pipeline
    - Corrupted audio file
    - LLM token limit exceeded
  - Test cancellation:
    - Cancel pipeline mid-process
    - Cancel recording mid-process
  - Test cross-module communication via ModuleInput/ModuleOutput
  - Write integration test suite in `ScribeTests/Integration/`

  **Must NOT do**:
  - Do NOT require real hardware for integration tests
  - Do NOT implement new error handling — test existing implementations

  **Files Modified**:
  - `ScribeTests/Integration/RecordingLifecycleTests.swift`
  - `ScribeTests/Integration/ErrorHandlingTests.swift`
  - `ScribeTests/Integration/ModuleCommunicationTests.swift`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Comprehensive integration and error scenario testing
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on Task 35)
  - **Parallel Group**: Wave 6
  - **Blocks**: Task 37
  - **Blocked By**: Task 35

  **Acceptance Criteria**:

  - [ ] Integration tests cover full recording lifecycle
  - [ ] All error scenarios tested
  - [ ] Cancellation works at all stages
  - [ ] ModuleInput/ModuleOutput communication verified
  - [ ] Mock services provide deterministic results

  **QA Scenarios**:

  ```
  Scenario: Full recording lifecycle works end-to-end
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create IntegrationTests with full mock setup
      2. Start recording → stop → process → verify results
      3. Run: xcodebuild test -only-testing:ScribeTests/IntegrationTests
    Expected Result: Full lifecycle completes successfully
    Evidence: .sisyphus/evidence/task-36-integration-tests.txt

  Scenario: Pipeline handles VAD no-speech gracefully
    Tool: Bash (xcodebuild test)
    Steps:
      1. Create ErrorHandlingTests with VAD returning false
      2. Verify pipeline exits early without error
      3. Run: xcodebuild test -only-testing:ScribeTests/ErrorHandlingTests
    Expected Result: Pipeline exits cleanly
    Evidence: .sisyphus/evidence/task-36-vad-no-speech-tests.txt

  Human Verification: Run app, record audio, process through pipeline, verify output
  ```

  **Commit**: YES (groups with 35)
  - Message: `test(integration): add end-to-end and error handling tests`

---

- [ ] 37. Documentation — README + Code Documentation

  **What to do**:
  - Update README.md with current VIPER architecture:
    - VIPER module structure (8 modules, each with Assembly/Interactor/Presenter/Router/View)
    - Services layer (BLE, Audio, ML, Recording)
    - Core layer (Entities, Protocols, Config, Infrastructure)
    - Updated ML pipeline (VAD → Language Detection → Whisper ASR → Diarization → LLM)
    - Unified Opus audio format
    - Config-driven model swapping
    - SPM dependencies
    - Build and test commands
  - Add documentation comments to all public APIs:
    - All protocols (ServiceProtocols, VIPERProtocols, module-specific protocols)
    - All public methods in Assemblies, Interactors, Presenters, Routers
    - All Services
  - Remove outdated references (PLAN.md, Phase 4 Apple Notes export)

  **Must NOT do**:
  - Do NOT add new features to README
  - Do NOT document internal implementation details — only public API contracts

  **Files Modified**:
  - `README.md`
  - All public API files (documentation comments added inline)

  **Recommended Agent Profile**:
  - **Category**: `writing`
    - Reason: Documentation writing
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on Task 36 for final verification)
  - **Parallel Group**: Wave 6
  - **Blocks**: F1-F4
  - **Blocked By**: Task 36

  **Acceptance Criteria**:

  - [ ] README reflects VIPER architecture accurately
  - [ ] All public APIs have documentation comments
  - [ ] Outdated references removed
  - [ ] Build and test commands documented

  **QA Scenarios**:

  ```
  Scenario: README build commands work
    Tool: Bash (xcodebuild)
    Steps:
      1. Follow README build instructions exactly
      2. Run: xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' build
      3. Verify build succeeds
    Expected Result: Build succeeds following README instructions
    Evidence: .sisyphus/evidence/task-37-readme-build.txt
  ```

  **Commit**: YES (groups with 35)
  - Message: `docs(readme): update architecture documentation for VIPER`

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

> 4 review agents run in PARALLEL. Present consolidated results to user for review and approval.
> Human-in-the-loop: user decides whether to approve, request fixes, or iterate.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read the plan end-to-end. For each "Must Have": verify implementation exists (read file, curl endpoint, run command). For each "Must NOT Have": search codebase for forbidden patterns — reject with file:line if found. Check evidence files exist in .sisyphus/evidence/. Compare deliverables against plan. Verify VIPER guardrails: no business logic in View, no direct service access from Presenter, no state in Interactor.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | VIPER Violations [N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `xcodebuild -scheme Scribe build` + `xcodebuild test`. Review all changed files for: `as!`/`try!`, empty catches, print statements in prod, commented-out code, unused imports. Check AI slop: excessive comments, over-abstraction, generic names (data/result/item/temp). Verify no file exceeds 400 lines. Verify VIPER module structure: each module has Assembly/Interactor/Presenter/Router/View.
  Output: `Build [PASS/FAIL] | Tests [N pass/N fail] | Files [N clean/N issues] | VERDICT`

- [ ] F3. **Real Manual QA** — `unspecified-high`
  Start from clean state. Execute EVERY QA scenario from EVERY task — follow exact steps, capture evidence. Test cross-task integration (features working together, not isolation). Test edge cases: empty state, invalid input, rapid actions. Human verification points: BLE real hardware, UI visual match, end-to-end recording flow. Save to `.sisyphus/evidence/final-qa/`.
  Output: `Scenarios [N/N pass] | Integration [N/N] | Edge Cases [N tested] | Human Checks [N/N] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do", read actual diff (git log/diff). Verify 1:1 — everything in spec was built (no missing), nothing beyond spec was built (no creep). Check "Must NOT do" compliance. Detect cross-task contamination: Task N touching Task M's files. Flag unaccounted changes. Verify VIPER architecture compliance: module boundaries respected, no cross-module direct dependencies.
  Output: `Tasks [N/N compliant] | Contamination [CLEAN/N issues] | Unaccounted [CLEAN/N files] | VIPER Violations [N] | VERDICT`

---

## Commit Strategy

- **Wave 1 (Tasks 1-7)**: `chore(scaffold): create VIPER project structure with core, services, and modules`
- **Wave 2 (Tasks 8-15)**: `feat(services): implement BLE, audio, and recording services`
- **Wave 3 (Tasks 16-20)**: `feat(ml): implement ML pipeline services with VAD and Swiss German ASR`
- **Wave 4 (Tasks 21-28)**: `feat(modules): implement all 8 VIPER module stacks`
- **Wave 5 (Tasks 29-34)**: `feat(ui): implement all module views with pixel-perfect design`
- **Wave 6 (Tasks 35-37)**: `feat(app): wire app, integration, error handling, documentation`

---

## Success Criteria

### Verification Commands
```bash
xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' build  # Expected: BUILD SUCCEEDED
xcodebuild -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Plus' test   # Expected: All tests pass
```

### Final Checklist
- [ ] All "Must Have" features present and working
- [ ] All "Must NOT Have" patterns absent (no print, no force unwrap, no empty catch, no magic numbers, no files > 400 lines)
- [ ] All VIPER guardrails respected (no business logic in View, no direct service access from Presenter, no state in Interactor, no cross-module direct dependencies)
- [ ] All tests pass (TDD throughout)
- [ ] BLE SLink protocol preserved exactly (8-step init, checksum, UUIDs)
- [ ] Unified Opus audio format for both internal and BLE microphones
- [ ] ML pipeline: VAD → Language Detection → Swiss German Whisper ASR → Diarization → LLM Summary
- [ ] Config-driven model swapping works
- [ ] Speaker renaming updates rawTranscript, actionItems, AND meetingNotes
- [ ] UI pixel-perfect match (colors, fonts, icons, animations, dark mode)
- [ ] VIPER Architecture: 8 modules, each with Assembly + Interactor + Presenter + Router + View
- [ ] Zero print statements in production code
- [ ] Zero force unwraps in production code
- [ ] Zero empty catch blocks
- [ ] All public APIs have documentation comments
- [ ] README updated with current VIPER architecture
