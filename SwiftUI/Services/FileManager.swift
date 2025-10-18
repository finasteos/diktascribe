import Foundation
import SwiftData

class IdeasFileManager: ObservableObject {
    static let shared = IdeasFileManager()
    
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    
    init() {
        do {
            self.baseDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Ideas", isDirectory: true)
            
            try createBaseDirectoryIfNeeded()
        } catch {
            fatalError("Failed to initialize Ideas directory: \(error.localizedDescription)")
        }
    }
    
    private func createBaseDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Directory Management
    
    func getOrCreateDateDirectory(_ date: Date = Date()) throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        let dateDirectory = baseDirectory.appendingPathComponent(dateString, isDirectory: true)
        
        if !fileManager.fileExists(atPath: dateDirectory.path) {
            try fileManager.createDirectory(at: dateDirectory, withIntermediateDirectories: true)
        }
        
        return dateDirectory
    }
    
    func getAllDateDirectories() throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { url1, url2 in
            url1.lastPathComponent > url2.lastPathComponent // Newest first
        }
    }
    
    // MARK: - File Operations
    
    func generateUniqueFileURL(for date: Date = Date(), prefix: String = "recording") throws -> URL {
        let dateDirectory = try getOrCreateDateDirectory(date)
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH-mm-ss"
        let timeString = timeFormatter.string(from: date)
        
        var fileURL = dateDirectory.appendingPathComponent("\(prefix)_\(timeString).flac")
        var counter = 1
        
        // Ensure unique filename
        while fileManager.fileExists(atPath: fileURL.path) {
            fileURL = dateDirectory.appendingPathComponent("\(prefix)_\(timeString)_\(counter).flac")
            counter += 1
        }
        
        return fileURL
    }
    
    func moveFile(from sourceURL: URL, to destinationURL: URL) throws {
        // Ensure destination directory exists
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // Remove destination if it exists
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }
    
    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        // Ensure destination directory exists
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
    
    func deleteFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
    
    func getFileSize(at url: URL) -> Int64 {
        (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
    
    func getFileModificationDate(at url: URL) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    }
    
    // MARK: - Recording Files Management
    
    func getAllRecordingFiles() throws -> [URL] {
        let dateDirectories = try getAllDateDirectories()
        var allFiles: [URL] = []
        
        for directory in dateDirectories {
            let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            let recordingFiles = contents.filter { $0.pathExtension.lowercased() == "flac" }
            allFiles.append(contentsOf: recordingFiles)
        }
        
        return allFiles.sorted { url1, url2 in
            let date1 = getFileModificationDate(at: url1) ?? Date.distantPast
            let date2 = getFileModificationDate(at: url2) ?? Date.distantPast
            return date1 > date2 // Newest first
        }
    }
    
    func getRecordingsForDate(_ date: Date) throws -> [URL] {
        let dateDirectory = try getOrCreateDateDirectory(date)
        let contents = try fileManager.contentsOfDirectory(at: dateDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return contents.filter { $0.pathExtension.lowercased() == "flac" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    
    // MARK: - Export Operations
    
    func createExportDirectory() throws -> URL {
        let exportDirectory = baseDirectory.appendingPathComponent("Exports", isDirectory: true)
        
        if !fileManager.fileExists(atPath: exportDirectory.path) {
            try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        }
        
        return exportDirectory
    }
    
    func createThreadDirectory(threadName: String) throws -> URL {
        let threadDirectory = baseDirectory.appendingPathComponent("Threads", isDirectory: true)
            .appendingPathComponent(threadName, isDirectory: true)
        
        if !fileManager.fileExists(atPath: threadDirectory.path) {
            try fileManager.createDirectory(at: threadDirectory, withIntermediateDirectories: true)
        }
        
        return threadDirectory
    }
    
    // MARK: - Backup Operations
    
    func createBackup() throws -> URL {
        let backupName = "Ideas_Backup_\(DateFormatter.filenameFormatter.string(from: Date())).zip"
        let backupURL = baseDirectory.appendingPathComponent(backupName)
        
        // Create backup (simplified - in production you'd want proper archiving)
        let allFiles = try getAllRecordingFiles()
        // TODO: Implement proper zip archiving
        
        return backupURL
    }
    
    // MARK: - Utility Methods
    
    func getAvailableStorageSpace() -> Int64 {
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: baseDirectory.path)
            return (attributes[.systemFreeSize] as? Int64) ?? 0
        } catch {
            return 0
        }
    }
    
    func cleanupOldFiles(olderThan days: Int) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let allFiles = try getAllRecordingFiles()
        
        for fileURL in allFiles {
            if let modificationDate = getFileModificationDate(at: fileURL),
               modificationDate < cutoffDate {
                try deleteFile(at: fileURL)
            }
        }
    }
    
    // MARK: - Transcription Files
    
    func getTranscriptionFileURL(for audioURL: URL) -> URL {
        var components = audioURL.pathComponents
        if let lastComponent = components.last {
            components[components.count - 1] = lastComponent.replacingOccurrences(of: ".flac", with: ".txt")
        }
        return URL(fileURLWithPath: components.joined(separator: "/"))
    }
    
    func getSRTFileURL(for audioURL: URL) -> URL {
        var components = audioURL.pathComponents
        if let lastComponent = components.last {
            components[components.count - 1] = lastComponent.replacingOccurrences(of: ".flac", with: ".srt")
        }
        return URL(fileURLWithPath: components.joined(separator: "/"))
    }
    
    func saveTranscription(_ text: String, for audioURL: URL) throws {
        let transcriptionURL = getTranscriptionFileURL(for: audioURL)
        try text.write(to: transcriptionURL, atomically: true, encoding: .utf8)
    }
    
    func saveSRTSubtitles(_ srtContent: String, for audioURL: URL) throws {
        let srtURL = getSRTFileURL(for: audioURL)
        try srtContent.write(to: srtURL, atomically: true, encoding: .utf8)
    }
    
    func loadTranscription(for audioURL: URL) throws -> String? {
        let transcriptionURL = getTranscriptionFileURL(for: audioURL)
        guard fileManager.fileExists(atPath: transcriptionURL.path) else { return nil }
        return try String(contentsOf: transcriptionURL, encoding: .utf8)
    }
}

// MARK: - Helper Extensions

extension DateFormatter {
    static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
