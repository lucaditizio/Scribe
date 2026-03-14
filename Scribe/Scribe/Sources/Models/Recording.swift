import Foundation
import SwiftData

@Model
final class Recording {
    // We use a String for ID in SwiftData to easily map with persistent files
    @Attribute(.unique) var id: String
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFilePath: String
    var categoryTag: String
    
    // Phase 2 placeholders
    var rawTranscript: String?
    
    // Phase 3 LLM Structural Data
    var meetingNotes: String?
    var actionItems: String?
    var mindMapJSON: Data?
    
    init(
        id: String = UUID().uuidString,
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0.0,
        audioFilePath: String,
        categoryTag: String = "#NOTE"
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioFilePath = audioFilePath
        self.categoryTag = categoryTag
    }
}
