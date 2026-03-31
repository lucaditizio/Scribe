# Implementation Prompt for qwen3.5-35B-A3B

---

## MANDATORY WORKFLOW - READ FIRST

You must follow this exact workflow for every single phase. Do not skip any steps.

```
1. Read IMPLEMENTATION_PLAN.md completely
2. Read TASK_LIST.md completely  
3. Implement the current phase
4. Write tests for your implementation
5. Run tests and verify they pass
6. ONLY THEN inform the user the phase is complete
7. Proceed to next phase
```

**STRICT RULE:** You must not inform the user about phase completion until tests have passed. If tests fail, fix the implementation until they pass.

---

## Context

You are implementing enhancements to the Scribe iOS application. Scribe is an on-device recording, transcription, and summarization app for iPhone 15 Plus (6GB RAM).

**Current Stack:**
- SwiftUI + SwiftData
- FluidAudio (Parakeet ASR, OfflineDiarizer, Silero VAD)
- Llama.cpp (Llama 3.2-3B) via LLM.swift
- AVFoundation for audio recording

**Project Location:** `/Users/lucaditizio/github/Scribe/`

**Main App Target:** `Scribe/Scribe/Scribe.xcodeproj`

---

## Files You Must Read Before Starting

1. **`/Users/lucaditizio/github/Scribe/IMPLEMENTATION_PLAN.md`** - Full architectural plan
2. **`/Users/lucaditizio/github/Scribe/TASK_LIST.md`** - Condensed task list with file locations
3. **Existing source files in `Scribe/Scribe/Sources/`** - Understand current implementation

---

## Phase Execution Rules

### Phase 1: External Bluetooth Microphone
- Tasks 1.1-1.5
- Implement in order
- Write tests after completing all 5 tasks in this phase
- Run tests → Fix if needed → Only then report completion

### Phase 2: Voice Activity Detection (Real-time)
- Tasks 2.1-2.3
- Tests required after phase completion
- Same workflow: implement → test → report

### Phase 3: Noise Suppression (Koala)
- Tasks 3.1-3.3
- Note: You may need to mock Koala if access key is not available
- Document any mocking needed

### Phase 4: Speaker Diarization
- Tasks 4.1-4.2
- First verify model version as instructed in Task 4.1

### Phase 5: Modular Pipeline
- Tasks 5.1-5.6
- This is the foundation - test thoroughly

---

## Testing Requirements

For each phase, you must:

1. **Write unit tests** for new services/classes
2. **Write UI tests** for new views
3. **Run the test suite** using:
   ```bash
   cd Scribe/Scribe
   xcodebuild test -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:YOUR_TEST_TARGET
   ```
4. **Verify all tests pass**
5. **Fix any test failures** before reporting completion

---

## Important Constraints

1. **Memory Management:** Maintain sequential processing - load model → process → unload → next stage
2. **Target Peak RAM:** <2.1GB for ML pipeline
3. **Sample Rate:** 16kHz for ML processing (downsample early in pipeline)
4. **iOS Version:** iOS 18.0+ (from Info.plist)

---

## Code Style

- Follow existing code conventions in the project
- Use SwiftUI for new views
- Use @Observable for new state management
- Add proper error handling
- Include documentation comments

---

## Commands to Run

### Build the project:
```bash
cd Scribe/Scribe
xcodebuild build -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

### Run tests:
```bash
cd Scribe/Scribe
xcodebuild test -scheme Scribe -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

---

## START YOUR WORK

Begin with Phase 1. Read the required files, then implement Tasks 1.1-1.5. Write tests, run them, fix any issues, then report completion to the user.

**Remember: Tests must pass before you inform the user about phase completion.**
