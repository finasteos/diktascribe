import Foundation
import SwiftData

@Model
final class Transcription {
    var id: UUID
    var text: String
    var confidence: Float
    var language: String
    var timestamps: [TimeInterval]
    var summary: String?
    var translation: String?
    var translatedLanguage: String?
    var createdAt: Date
    var processingTime: TimeInterval
    var wordCount: Int
    var modelUsed: String
    
    init(
        text: String,
        confidence: Float = 0.0,
        language: String = "sv",
        timestamps: [TimeInterval] = [],
        summary: String? = nil,
        translation: String? = nil,
        translatedLanguage: String? = nil,
        processingTime: TimeInterval = 0,
        modelUsed: String = "whisper-small-sv"
    ) {
        self.id = UUID()
        self.text = text
        self.confidence = confidence
        self.language = language
        self.timestamps = timestamps
        self.summary = summary
        self.translation = translation
        self.translatedLanguage = translatedLanguage
        self.createdAt = Date()
        self.processingTime = processingTime
        self.wordCount = text.split(separator: " ").count
        self.modelUsed = modelUsed
    }
    
    var formattedConfidence: String {
        String(format: "%.1f%%", confidence * 100)
    }
    
    var formattedProcessingTime: String {
        let minutes = Int(processingTime) / 60
        let seconds = Int(processingTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var hasTranslation: Bool {
        translation != nil && !translation!.isEmpty
    }
    
    var hasSummary: Bool {
        summary != nil && !summary!.isEmpty
    }
}
