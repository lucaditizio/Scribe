import Foundation
import SwiftData
import MLX
import MLXLMCommon

/// The structured output expected from Llama-3.2
struct MeetingSummary: Codable {
    let meetingNotes: String
    let actionItems: String
    let mindMapNodes: [MindMapNode]
}

struct MindMapNode: Codable {
    let id: String
    let text: String
    let children: [MindMapNode]?
}

class LLMService: ObservableObject {
    
    // We bind the progress string to the UI generating mesh
    @Published var currentProgress: String = "Initializing Llama 3.2 Engine..."
    
    private let modelConfiguration = ModelConfiguration(
        id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
        overrideTokenizer: "PreTrainedTokenizer"
    )
    
    /// Loads the MLX Model constraint into Apple Silicon, generates the JSON, and shuts down immediately to save RAM.
    func generateSummary(transcript: String, progressCallback: @escaping (String, Double) -> Void) async throws -> MeetingSummary {
        
        await MainActor.run { progressCallback("Warming up Neural Engine...", 0.1) }
        
        // --- 1. Load MLX Model ---
        // MLX seamlessly downloads via HuggingFace on first run and caches it in ~/.cache/huggingface
        let loadContext = try await load(configuration: modelConfiguration) { progress in
            Task { @MainActor in
                progressCallback("Downloading Llama-3.2 (2GB)... \(Int(progress.fractionCompleted * 100))%", 0.1 + (progress.fractionCompleted * 0.4))
            }
        }
        
        let model = loadContext.model
        let tokenizer = loadContext.tokenizer
        
        await MainActor.run { progressCallback("Analyzing Transcript...", 0.5) }
        
        // --- 2. Build Structured Prompt ---
        // Llama 3.2 Instruct format
        let systemPrompt = """
        You are an elite, highly structured executive assistant. Your task is to read the following raw transcript and output a strict JSON object with EXACTLY three keys. Output ONLY valid JSON. Your output must be entirely in English.
        
        Required JSON Structure:
        {
          "meetingNotes": "A concise, professional 3-4 sentence paragraph summarizing the core discussion.",
          "actionItems": "A bulleted list of next steps, assigning owners if mentioned. Use Markdown bullets (-).",
          "mindMapNodes": [
             { "id": "1", "text": "Main Topic", "children": [ { "id": "1.1", "text": "Subtopic A" } ] }
          ]
        }
        """
        
        // We use the tokenizer's chat template or manual instruction formatting
        let inputString = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|><|start_header_id|>user<|end_header_id|>\n\nTranscript:\n\(transcript)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n{"
        
        // --- 3. Execute Inference in Batches ---
        let promptTokens = try tokenizer.encode(text: inputString)
        var generatedTokens = [Int]()
        
        // Using MLX generate API
        let stream = generate(
            prompt: promptTokens,
            model: model,
            tokenizer: tokenizer,
            maxTokens: 1024,
            temperature: 0.2 // Low temperature for strict JSON adherence
        )
        
        await MainActor.run { progressCallback("Generating JSON Syntax...", 0.6) }
        
        var fullOutput = "{" // we injected { in the prompt, so we prepend it back
        for try await token in stream {
            generatedTokens.append(token.token)
            fullOutput += token.text
            
            // Artificial progress bump during token stream
            await MainActor.run { 
                let percent = 0.6 + (Double(generatedTokens.count) / 1024.0) * 0.3
                progressCallback("Writing Note... \(generatedTokens.count) tokens", min(percent, 0.9)) 
            }
        }
        
        await MainActor.run { progressCallback("Validating JSON Structural Output...", 0.95) }
        
        // --- 4. Cleanup Memory constraints ---
        // To respect the strict Sequential Batch process for 6GB RAM phones
        MLX.GPU.clearCache()
        
        // --- 5. Decode JSON ---
        if let jsonStart = fullOutput.firstIndex(of: "{"),
           let jsonEnd = fullOutput.lastIndex(of: "}") {
            
            let jsonString = String(fullOutput[jsonStart...jsonEnd])
            let jsonData = Data(jsonString.utf8)
            
            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(MeetingSummary.self, from: jsonData)
                return result
            } catch {
                print("Failed to decode Llama JSON: \(error). Raw string: \(jsonString)")
                throw NSError(domain: "LLMService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Llama output into strict JSON."])
            }
        } else {
            throw NSError(domain: "LLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Llama failed to generate a JSON closure."])
        }
    }
}
