import Foundation
import LLM

// MARK: - Structured Output Models

/// A single topic section in meeting notes (Array replaces the old flat String)
struct TopicSection: Codable {
    let topic: String
    let bullets: [String]
}

struct MeetingSummary: Codable {
    let title: String           // 2-4 word title for the recording
    let meetingNotes: [TopicSection]
    let actionItems: String
    let mindMapNodes: [MindMapNode]
}

struct MindMapNode: Codable {
    let id: String
    let text: String
    let children: [MindMapNode]?
}

// MARK: - LLM Service

/// Two-pass meeting summarisation pipeline:
///   • Short transcripts (≤ 25,000 chars / ~35 min): single synthesis pass
///   • Long  transcripts (> 25,000 chars):  Map (extract per chunk) → Refine (synthesize)
class LLMService {

    // MARK: - Model Config

    private static let modelFileName    = "Llama-3.2-3B-Instruct-Q4_K_M.gguf"
    private static let modelDownloadURL = URL(
        string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
    )!

    /// Maximum chars that fit in a single 8192-token context alongside prompts + response
    private static let singlePassThreshold = 25_000
    /// Target chunk size for multi-pass (3,000 tokens ≈ 12,000 chars)
    private static let chunkSize           = 12_000
    /// 10% overlap between chunks to prevent boundary context loss
    private static let chunkOverlap        = 1_200

    // MARK: - Llama 3 Template
    // NOTE: Template.llama() is Llama-2 format — wrong for Llama 3.x.
    private static let llama3Template = Template(
        system: ("<|start_header_id|>system<|end_header_id|>\n\n", "<|eot_id|>"),
        user:   ("<|start_header_id|>user<|end_header_id|>\n\n",   "<|eot_id|>"),
        bot:    ("<|start_header_id|>assistant<|end_header_id|>\n\n", "<|eot_id|>"),
        stopSequence: "<|eot_id|>",
        systemPrompt: nil   // system prompt is injected per-call via the user turn
    )

    // MARK: - Prompts

    private static let extractionSystemPrompt = """
    You are a meeting analyst. Extract the key discussion points from this transcript segment.
    Cover ALL topics mentioned. Format your output as:

    **[Topic Name]**
    - Speaker if clear: concise key point (1 sentence max)
    - key point

    Include up to 6 topics. Be dense but accurate. Only include what is explicitly said — do not infer.
    """

    private static let synthesisSystemPrompt = """
    You are an executive assistant. Synthesise the following sequential meeting segment summaries \
    into a single structured JSON object. Merge duplicate topics, resolve cross-segment threads, \
    and follow these rules strictly:

    - "title": A 2-4 word title summarising the meeting (e.g. "Product Roadmap Q2"). No punctuation.
    - "meetingNotes": array of topic objects. Each has "topic" (string) and "bullets" (string array, \
    1 sentence each). Cover all major topics discussed.
    - "actionItems": Markdown bullet list of ONLY explicitly committed tasks ("we will", "I'll", \
    "let's schedule"). Prefix each item with the speaker acting as the owner using their exact name/ID from the transcript (e.g. "- Speaker 1: task"). If none, use "".
    - "mindMapNodes": hierarchical tree of discussed topics. Each node: id, text, optional children.

    Output ONLY valid JSON — no preamble, no trailing text.

    CRITICAL JSON FORMATTING RULES:
    1. Escape all internal double quotes within strings using \\".
    2. Ensure ALL keys are quoted (e.g. "children": [] NOT children: []).
    3. Do NOT include trailing commas in arrays or objects.
    4. Output ONLY raw valid JSON — no preamble, no trailing text, no Markdown code blocks (```json).

    Required structure:
    {
      "title": "Meeting Title Here",
      "meetingNotes": [
        { "topic": "Topic Name", "bullets": ["point one", "point two"] }
      ],
      "actionItems": "- Speaker 1: task\\n- Speaker 2: task",
      "mindMapNodes": [
        { "id": "1", "text": "Main Topic", "children": [{ "id": "1.1", "text": "Subtopic" }] }
      ]
    }
    """

    private static let singlePassSystemPrompt = """
    You are an executive assistant. Read the following meeting transcript and output a structured \
    JSON object following these rules:

    - "title": A 2-4 word title summarising the meeting (e.g. "AI Diffusion Discussion"). No punctuation.
    - "meetingNotes": array of topic objects. Each has "topic" (string) and "bullets" (string array, \
    1 sentence each). Cover all major topics discussed.
    - "actionItems": Markdown bullet list of ONLY explicitly committed tasks ("we will", "I'll", \
    "let's schedule"). Prefix each item with the speaker acting as the owner using their exact name/ID from the transcript (e.g. "- Speaker 1: task"). If none, use "".
    - "mindMapNodes": hierarchical tree of discussed topics. Each node: id, text, optional children.

    Output ONLY valid JSON — no preamble, no trailing text.

    CRITICAL JSON FORMATTING RULES:
    1. Escape all internal double quotes within strings using \\".
    2. Ensure ALL keys are quoted (e.g. "children": [] NOT children: []).
    3. Do NOT include trailing commas in arrays or objects.
    4. Output ONLY raw valid JSON — no preamble, no trailing text, no Markdown code blocks (```json).

    Required structure:
    {
      "title": "Meeting Title Here",
      "meetingNotes": [
        { "topic": "Topic Name", "bullets": ["point one", "point two"] }
      ],
      "actionItems": "- Speaker 1: task\\n- Speaker 2: task",
      "mindMapNodes": [
        { "id": "1", "text": "Main Topic", "children": [{ "id": "1.1", "text": "Subtopic" }] }
      ]
    }
    """

    // MARK: - Public Interface

    func generateSummary(
        transcript: String,
        progressCallback: @escaping (String, Double) -> Void
    ) async throws -> MeetingSummary {

        // --- 1. Download / cache model ---
        await MainActor.run { progressCallback("Checking model cache...", 0.1) }
        let modelURL = try await downloadModelIfNeeded(progressCallback: progressCallback)

        // --- 2. Load model ---
        await MainActor.run { progressCallback("Loading Neural Engine...", 0.51) }
        guard let llm = LLM(from: modelURL, template: LLMService.llama3Template, maxTokenCount: 8192) else {
            throw NSError(domain: "LLMService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "llama_model_load_from_file returned nil — model file may be corrupt at \(modelURL.path)"
            ])
        }
        print("[LLMService] ✅ Model loaded")

        // --- 3. Route: single-pass or multi-chunk ---
        if transcript.count <= LLMService.singlePassThreshold {
            return try await runSinglePass(transcript: transcript, llm: llm, progressCallback: progressCallback)
        } else {
            return try await runMultiPass(transcript: transcript, llm: llm, progressCallback: progressCallback)
        }
    }

    // MARK: - Single-Pass (≤ 25,000 chars)

    private func runSinglePass(
        transcript: String,
        llm: LLM,
        progressCallback: @escaping (String, Double) -> Void
    ) async throws -> MeetingSummary {
        await MainActor.run { progressCallback("Analyzing transcript...", 0.55) }

        let userTurn = "\(LLMService.singlePassSystemPrompt)\n\nTranscript:\n\(transcript)"
        let processed = llm.preprocess(userTurn, [])
        print("[LLMService] 📝 Single-pass prompt (\(processed.count) chars)")

        await MainActor.run { progressCallback("Generating meeting notes...", 0.65) }
        let output = await llm.getCompletion(from: processed)
        print("[LLMService] 📤 Single-pass output (\(output.count) chars):\n\(output.prefix(400))")

        await MainActor.run { progressCallback("Validating structured output...", 0.95) }
        return try decode(rawOutput: output)
    }

    // MARK: - Multi-Pass: Map → Refine (> 25,000 chars)

    private func runMultiPass(
        transcript: String,
        llm: LLM,
        progressCallback: @escaping (String, Double) -> Void
    ) async throws -> MeetingSummary {
        let chunks = splitTranscript(transcript)
        print("[LLMService] 🗂  Multi-pass: \(chunks.count) chunks")

        // Pass 1: Extract a 300-500 token summary per chunk
        var miniSummaries: [String] = []
        for (i, chunk) in chunks.enumerated() {
            let progressFraction = 0.55 + Double(i) / Double(chunks.count) * 0.25
            await MainActor.run {
                progressCallback("Analyzing segment \(i + 1) of \(chunks.count)...", progressFraction)
            }
            let summary = await extractChunk(chunk, llm: llm, index: i, total: chunks.count)
            miniSummaries.append(summary)
        }

        // Pass 2: Synthesise all mini-summaries into final JSON
        await MainActor.run { progressCallback("Synthesizing meeting notes...", 0.82) }
        let combinedSummaries = miniSummaries
            .enumerated()
            .map { "=== Segment \($0.offset + 1) ===\n\($0.element)" }
            .joined(separator: "\n\n")

        let userTurn = "\(LLMService.synthesisSystemPrompt)\n\nSegment summaries:\n\(combinedSummaries)"
        let processed = llm.preprocess(userTurn, [])
        print("[LLMService] 📝 Synthesis prompt (\(processed.count) chars)")

        let output = await llm.getCompletion(from: processed)
        print("[LLMService] 📤 Synthesis output (\(output.count) chars):\n\(output.prefix(400))")

        await MainActor.run { progressCallback("Validating structured output...", 0.95) }
        return try decode(rawOutput: output)
    }

    // MARK: - Chunk Extraction (Pass 1)

    private func extractChunk(_ chunk: String, llm: LLM, index: Int, total: Int) async -> String {
        let userTurn = "\(LLMService.extractionSystemPrompt)\n\nTranscript segment \(index + 1) of \(total):\n\(chunk)"
        let processed = llm.preprocess(userTurn, [])
        let output = await llm.getCompletion(from: processed)
        print("[LLMService] 📦 Chunk \(index + 1)/\(total) extraction (\(output.count) chars)")
        return output
    }

    // MARK: - Transcript Chunking

    /// Splits a transcript into overlapping sentence-boundary chunks.
    /// Research-backed: 10% overlap (1,200 chars) prevents boundary context loss.
    private func splitTranscript(_ transcript: String) -> [String] {
        let size    = LLMService.chunkSize
        let overlap = LLMService.chunkOverlap
        var chunks: [String] = []
        var start = transcript.startIndex

        while start < transcript.endIndex {
            // Find end of this chunk
            let rawEnd = transcript.index(start, offsetBy: size, limitedBy: transcript.endIndex) ?? transcript.endIndex

            // Snap to nearest sentence boundary (. ! ?)
            var end = rawEnd
            if rawEnd < transcript.endIndex {
                let searchRange = transcript.index(rawEnd, offsetBy: -200, limitedBy: start) ?? start
                if let boundary = transcript[searchRange..<rawEnd].lastIndex(where: { ".!?".contains($0) }) {
                    end = transcript.index(after: boundary)
                }
            }

            chunks.append(String(transcript[start..<end]))

            // Next chunk starts (size - overlap) chars in, snapped to sentence boundary
            let nextRaw = transcript.index(start, offsetBy: size - overlap, limitedBy: transcript.endIndex) ?? transcript.endIndex
            if nextRaw >= transcript.endIndex { break }

            // Snap next start to a sentence start
            let snapRange = nextRaw..<min(transcript.index(nextRaw, offsetBy: 200, limitedBy: transcript.endIndex) ?? transcript.endIndex, transcript.endIndex)
            if let nextBoundary = transcript[snapRange].firstIndex(where: { " \n".contains($0) }) {
                start = transcript.index(after: nextBoundary)
            } else {
                start = nextRaw
            }
        }
        return chunks
    }

    // MARK: - Download Helper

    private func downloadModelIfNeeded(
        progressCallback: @escaping (String, Double) -> Void
    ) async throws -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destination  = documentsDir.appendingPathComponent(LLMService.modelFileName)

        if FileManager.default.fileExists(atPath: destination.path) {
            print("[LLMService] ✅ Model cached at \(destination.path)")
            return destination
        }

        print("[LLMService] ⬇️ Downloading from \(LLMService.modelDownloadURL)")
        let downloader = LLMModelDownloader(progressCallback: progressCallback)
        let tempURL    = try await downloader.download(url: LLMService.modelDownloadURL)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        print("[LLMService] ✅ Saved to \(destination.path)")
        return destination
    }

    // MARK: - JSON Decoder

    private func decode(rawOutput: String) throws -> MeetingSummary {
        guard
            let jsonStart = rawOutput.firstIndex(of: "{"),
            let jsonEnd   = rawOutput.lastIndex(of: "}")
        else {
            print("[LLMService] ❌ No JSON braces in output:\n\(rawOutput)")
            throw NSError(domain: "LLMService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Model produced no JSON. Raw: \(rawOutput.prefix(300))"
            ])
        }

        let jsonString = String(rawOutput[jsonStart...jsonEnd])
        do {
            let result = try JSONDecoder().decode(MeetingSummary.self, from: Data(jsonString.utf8))
            print("[LLMService] ✅ JSON decoded: \(result.meetingNotes.count) topics, \(result.mindMapNodes.count) nodes")
            return result
        } catch {
            print("[LLMService] ❌ JSON decode error: \(error)\nRaw:\n\(jsonString)")
            throw NSError(domain: "LLMService", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "JSON parse failed. Check console for raw model output."
            ])
        }
    }
}

// MARK: - URLSession Download with Progress

private class LLMModelDownloader: NSObject, URLSessionDownloadDelegate {
    private let progressCallback: (String, Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?

    init(progressCallback: @escaping (String, Double) -> Void) {
        self.progressCallback = progressCallback
    }

    func download(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let sess = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = sess
            sess.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            let stable = FileManager.default.temporaryDirectory
                .appendingPathComponent("llm_model_\(UUID().uuidString).gguf")
            try FileManager.default.copyItem(at: location, to: stable)
            continuation?.resume(returning: stable)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil; session.finishTasksAndInvalidate(); self.session = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.progressCallback("Downloading Llama-3.2... \(Int(p * 100))%", 0.1 + p * 0.4) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.resume(throwing: error); continuation = nil; self.session = nil }
    }
}
