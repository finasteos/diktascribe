import Foundation
import SwiftData

@Model
final class Recording {
    var id: UUID
    var title: String
    var fileName: String
    var fileURL: URL
    var createdAt: Date
    var duration: TimeInterval
    var fileSize: Int64
    var sampleRate: Double
    var channels: Int
    var format: String
    var transcription: Transcription?
    var isFavorite: Bool
    var isAnalyzed: Bool
    var thread: RecordingThread?
    var tags: [String]
    
    init(
        title: String = "",
        fileName: String,
        fileURL: URL,
        duration: TimeInterval = 0,
        fileSize: Int64 = 0,
        sampleRate: Double = 48000,
        channels: Int = 1,
        format: String = "flac"
    ) {
        self.id = UUID()
        self.title = title
        self.fileName = fileName
        self.fileURL = fileURL
        self.createdAt = Date()
        self.duration = duration
        self.fileSize = fileSize
        self.sampleRate = sampleRate
        self.channels = channels
        self.format = format
        self.isFavorite = false
        self.isAnalyzed = false
        self.tags = []
    }
    
    var displayTitle: String {
        title.isEmpty ? fileName : title
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}
