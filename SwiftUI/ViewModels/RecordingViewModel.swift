import Foundation
import SwiftData
import AVFoundation
import UIKit

@MainActor
class RecordingViewModel: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var recordingTime: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var currentlyPlayingURL: URL?
    @Published var selectedRecordings: Set<Recording> = []
    @Published var searchText: String = ""
    @Published var isTranscribing = false
    @Published var transcriptionProgress: Double = 0
    @Published var currentTranscriptionTask: String = ""
    
    // Services
    private let audioService = AudioRecordingService()
    private let transcriptionService = TranscriptionServiceManager()
    private let fileManager = IdeasFileManager.shared
    private var modelContext: ModelContext?
    private var audioPlayer: AVAudioPlayer?
    
    // Haptic feedback
    private let hapticGenerator = UINotificationFeedbackGenerator()
    
    init() {
        setupServices()
        loadRecordings()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        audioService.setModelContext(context)
    }
    
    private func setupServices() {
        // Observe audio service changes
        Task {
            for await isRecording in audioService.$isRecording.values {
                self.isRecording = isRecording
            }
        }
        
        Task {
            for await recordingTime in audioService.$recordingTime.values {
                self.recordingTime = recordingTime
            }
        }
        
        Task {
            for await audioLevel in audioService.$audioLevel.values {
                self.audioLevel = audioLevel
            }
        }
        
        // Observe transcription service changes
        Task {
            for await isTranscribing in transcriptionService.$isProcessing.values {
                self.isTranscribing = isTranscribing
            }
        }
        
        Task {
            for await progress in transcriptionService.$progress.values {
                self.transcriptionProgress = progress
            }
        }
        
        Task {
            for await task in transcriptionService.$currentTask.values {
                self.currentTranscriptionTask = task
            }
        }
    }
    
    func startRecording() async {
        do {
            hapticGenerator.prepare()
            
            try await audioService.startRecording()
            
            hapticGenerator.notificationOccurred(.success)
            
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
            // TODO: Show error alert to user
        }
    }
    
    func stopRecording() {
        hapticGenerator.prepare()
        
        audioService.stopRecording()
        
        hapticGenerator.notificationOccurred(.success)
        
        // Reload recordings to show the new one
        loadRecordings()
    }
    
    func playRecording(url: URL) {
        do {
            // Stop current playback if playing
            if isPlaying {
                audioPlayer?.stop()
                currentlyPlayingURL = nil
                isPlaying = false
                return
            }
            
            // Start new playback
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            currentlyPlayingURL = url
            isPlaying = true
            
        } catch {
            print("Failed to play recording: \(error.localizedDescription)")
        }
    }
    
    func deleteRecording(_ recording: Recording) {
        do {
            // Delete files
            try fileManager.deleteFile(at: recording.fileURL)
            
            // Delete transcription files if they exist
            let transcriptionURL = fileManager.getTranscriptionFileURL(for: recording.fileURL)
            if fileManager.fileManager.fileExists(atPath: transcriptionURL.path) {
                try fileManager.fileManager.removeItem(at: transcriptionURL)
            }
            
            let srtURL = fileManager.getSRTFileURL(for: recording.fileURL)
            if fileManager.fileManager.fileExists(atPath: srtURL.path) {
                try fileManager.fileManager.removeItem(at: srtURL)
            }
            
            // Remove from CoreData
            if let context = modelContext {
                context.delete(recording)
                try context.save()
            }
            
            // Reload recordings
            loadRecordings()
            
        } catch {
            print("Failed to delete recording: \(error.localizedDescription)")
        }
    }
    
    func deleteRecordings(_ recordings: [Recording]) {
        recordings.forEach { deleteRecording($0) }
    }
    
    func transcribeRecording(_ recording: Recording) async {
        do {
            let transcription = try await transcriptionService.transcribeRecording(recording)
            
            // Update recording in CoreData
            recording.transcription = transcription
            
            if let context = modelContext {
                try context.save()
            }
            
            // Reload recordings to show updated transcription
            loadRecordings()
            
        } catch {
            print("Failed to transcribe recording: \(error.localizedDescription)")
            // TODO: Show error alert to user
        }
    }
    
    func toggleFavorite(_ recording: Recording) {
        recording.isFavorite.toggle()
        
        if let context = modelContext {
            try? context.save()
        }
        
        loadRecordings()
    }
    
    func searchRecordings() -> [Recording] {
        if searchText.isEmpty {
            return recordings
        }
        
        return recordings.filter { recording in
            let titleMatch = recording.displayTitle.localizedCaseInsensitiveContains(searchText)
            let transcriptionMatch = recording.transcription?.text.localizedCaseInsensitiveContains(searchText) ?? false
            return titleMatch || transcriptionMatch
        }
    }
    
    func getRecordingsForDate(_ date: Date) -> [Recording] {
        recordings.filter { recording in
            Calendar.current.isDate(recording.createdAt, inSameDayAs: date)
        }
    }
    
    func exportRecording(_ recording: Recording, format: ExportFormat) async throws -> URL {
        switch format {
        case .markdown:
            return try exportAsMarkdown(recording)
        case .pdf:
            return try exportAsPDF(recording)
        case .txt:
            return try exportAsText(recording)
        }
    }
    
    private func exportAsMarkdown(_ recording: Recording) throws -> URL {
        let exportDir = try fileManager.createExportDirectory()
        let fileName = "recording_\(recording.fileName.replacingOccurrences(of: ".flac", with: ".md"))"
        let exportURL = exportDir.appendingPathComponent(fileName)
        
        var markdown = "# \(recording.displayTitle)\n\n"
        markdown += "**Created:** \(recording.createdAt.formatted())\n"
        markdown += "**Duration:** \(recording.formattedDuration)\n"
        markdown += "**File Size:** \(recording.formattedFileSize)\n\n"
        
        if let transcription = recording.transcription {
            markdown += "## Transcription\n\n\(transcription.text)\n\n"
            
            if let summary = transcription.summary {
                markdown += "## Summary\n\n\(summary)\n\n"
            }
            
            if let translation = transcription.translation {
                markdown += "## Translation\n\n\(translation)\n\n"
            }
        }
        
        try markdown.write(to: exportURL, atomically: true, encoding: .utf8)
        return exportURL
    }
    
    private func exportAsPDF(_ recording: Recording) throws -> URL {
        // TODO: Implement PDF export with proper formatting
        // For now, return markdown export
        return try exportAsMarkdown(recording)
    }
    
    private func exportAsText(_ recording: Recording) throws -> URL {
        let exportDir = try fileManager.createExportDirectory()
        let fileName = "recording_\(recording.fileName.replacingOccurrences(of: ".flac", with: ".txt"))"
        let exportURL = exportDir.appendingPathComponent(fileName)
        
        let text = recording.transcription?.text ?? "No transcription available"
        try text.write(to: exportURL, atomically: true, encoding: .utf8)
        return exportURL
    }
    
    private func loadRecordings() {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            recordings = try context.fetch(descriptor)
        } catch {
            print("Failed to load recordings: \(error.localizedDescription)")
            recordings = []
        }
    }
    
    func requestMicrophonePermission() async {
        do {
            try await audioService.requestMicrophonePermission()
        } catch {
            print("Microphone permission denied: \(error.localizedDescription)")
        }
    }
    
    func createTestRecording() {
        // Create a test recording for development
        let testURL = fileManager.baseDirectory.appendingPathComponent("test_recording.flac")
        
        let testRecording = Recording(
            title: "Test Recording",
            fileName: "test_recording.flac",
            fileURL: testURL,
            duration: 30.5,
            fileSize: 1024 * 1024 // 1MB
        )
        
        if let context = modelContext {
            context.insert(testRecording)
            try? context.save()
            loadRecordings()
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension RecordingViewModel: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentlyPlayingURL = nil
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaying = false
        currentlyPlayingURL = nil
        print("Audio playback error: \(error?.localizedDescription ?? "Unknown error")")
    }
}

// MARK: - Export Format

enum ExportFormat {
    case markdown
    case pdf
    case txt
}
