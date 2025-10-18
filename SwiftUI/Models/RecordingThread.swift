import Foundation
import SwiftData

@Model
final class RecordingThread {
    var id: UUID
    var title: String
    var color: String // Hex color code
    var createdAt: Date
    var isDefault: Bool
    var recordings: [Recording]
    
    init(
        title: String,
        color: String = "#007AFF",
        isDefault: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.color = color
        self.createdAt = Date()
        self.isDefault = isDefault
        self.recordings = []
    }
    
    var recordingCount: Int {
        recordings.count
    }
    
    var totalDuration: TimeInterval {
        recordings.reduce(0) { $0 + $1.duration }
    }
    
    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}
