# PLAN.md: Scribe (Plaud-Inspired Privacy-First AI Voice Memo Architect)

## 1. Project Vision
Build **Scribe**, a premium, privacy-first alternative to the Plaud/AI DVR ecosystem. The app captures high-quality audio from an external 2.4GHz wireless microphone (USB-C receiver), provides a professional Plaud-style UI for playback, and generates multilingual transcription, speaker diarization, and structured meeting summaries locally on the iPhone 15 Plus. Every recording is exported as a uniquely formatted note to Apple Notes.

## 2. Technical Hardware Constraints
* **Target Device:** iPhone 15 Plus (6 GB RAM).
* **Processor:** A16 Bionic (16-core Neural Engine).
* **Input:** External USB-C Receiver (2.4GHz Wireless Mic).
* **Memory Management Strategy:** **Strictly Sequential Batch Processing**. To avoid system jetsam (crashes) on 6GB RAM, models must load, process, and completely unload before the next model loads. No two large models may coexist in RAM.

## 3. Local AI Model Stack
| Component | Model | Framework | Precision | RAM Estimate |
| :--- | :--- | :--- | :--- | :--- |
| **ASR (Transcription)** | `NVIDIA Parakeet-TDT-0.6B-v3` (Multilingual + Auto-Detect) | FluidAudio / CoreML | Mixed (ANE) | ~1.3 GB |
| **Diarization (Speaker ID)** | CoreML optimized Speaker Embedding Model (TitaNet-Small) | CoreML | FP16 (ANE) | ~0.8 GB |
| **LLM (Summarization)** | `Llama-3.2-3B-Instruct` | MLX Swift / CoreML | 4-bit (SpinQuant) | ~2.1 GB |

## 4. Feature Roadmap

### Phase 1: Plaud Core UI & Audio Capture
* **Audio Engine:** Implement `AVAudioEngine` for 48kHz mono recording. Handle USB-C "Plug & Play" events for the external receiver.
* **UI View 1 (All Notes List):** * Card-based list with title, date/time, and duration.
    * Use Plaud-style category tags (e.g., #MEETING, #NOTE, #INTERVIEW).
    * Bottom navigation bar with a prominent **Red Circular Record Button** in the center.
* **Persistence:** SwiftData for recording metadata and file management.

### Phase 2: Playback & Sequential Inference
* **UI View 2 (Detail Detail View):** * Top panel: Waveform visualization with playback controls (speed 1x/1.5x/2x, 15s skip).
    * Bottom panel: Segmented control to toggle between "Transcript," "Summary," and "Mind Map."
* **Inference Pipeline (Batch Process):**
    1. `Load Parakeet` -> Transcribe -> `Unload Parakeet`.
    2. `Load Diarizer` -> Speaker timestamping -> `Unload Diarizer`.
    3. Generate segmented transcript (e.g., "Speaker 1 [00:12]: ...").

### Phase 3: Meeting Mode & Agent Logic
* **Generating State:** Implement the Plaud-style "Generating" view with mesh gradients and a progress indicator.
* **Meeting Mode Agent (Llama 3.2):**
    * **Participant Resolution:** Auto-detect names in text or provide a UI to map "Speaker 1" to a name.
    * **Structured Output:** Generate "Besprechungsnotizen" (Summary) and "Nächste Schritte" (Action Items with owners).
* **Mind Map:** Generate JSON for a visual node-based tree in the third tab.

### Phase 4: Apple Notes & System Integration
* **App Intent:** Build a "Save Scribe to Notes" Intent.
* **Export Logic:** Create a **new unique note** for every recording.
* **Formatting:** Format the note in Markdown: 
    * Header: Title & Metadata.
    * Body: Meeting Summary & Action Items.
    * Footer: Full Diarized Transcript.

## 5. Design & Vibe (Plaud Aesthetic, see image_1 through image_3)
* **Aesthetics:** Clean white backgrounds in light mode; Deep Obsidian in dark mode. Squircle-shaped cards and subtle drop shadows.
* **Dashboard:** Mock-up usage meters for "Minutes Used" vs "Total" to replicate the Pro/Starter feel.
* **Interaction:** Haptic feedback on all AI triggers and recording states.

## 6. Antigravity Agent Instructions
* **Read and prioritize this PLAN.md** before every instruction.
* Follow the Plaud design language found in the attached screenshots exclusively.
* Strictly enforce memory safety by ensuring `deinit` clears model buffers before subsequent pipeline stages to stabilize the 6GB RAM environment.