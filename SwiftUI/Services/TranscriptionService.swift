import Foundation
import AVFoundation
import SwiftData

// MARK: - Protocols

protocol TranscriptionServiceProtocol {
    func transcribeAudio(at url: URL) async throws -> Transcription
    func isModelAvailable() -> Bool
    func getModelSize() -> Int64?
    func getEstimatedProcessingTime(for duration: TimeInterval) -> TimeInterval
}

enum TranscriptionError: LocalizedError {
    case modelNotAvailable
    case audioProcessingFailed(String)
    case insufficientStorage
    case processingTimeout
    
    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "Transcription model is not available. Please check your internet connection and try again."
        case .audioProcessingFailed(let reason):
            return "Failed to process audio: \(reason)"
        case .insufficientStorage:
            return "Not enough storage space for transcription processing."
        case .processingTimeout:
            return "Transcription processing timed out. Please try again."
        }
    }
}

// MARK: - Transcription Service Manager

@MainActor
class TranscriptionServiceManager: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var currentTask: String = ""
    
    private let whisperService = WhisperTranscriptionService()
    private let speechService = SFSpeechTranscriptionService()
    private let fileManager = IdeasFileManager.shared
    
    private var backgroundTask: BGProcessingTask?
    
    func transcribeRecording(_ recording: Recording) async throws -> Transcription {
        isProcessing = true
        progress = 0.0
        currentTask = "Preparing transcription..."
        
        defer {
            isProcessing = false
            progress = 0.0
            currentTask = ""
        }
        
        // Check storage space
        let availableSpace = fileManager.getAvailableStorageSpace()
        let estimatedSize = whisperService.getModelSize() ?? 0
        
        guard availableSpace > estimatedSize + (10 * 1024 * 1024) else { // Need 10MB buffer
            throw TranscriptionError.insufficientStorage
        }
        
        // Try Whisper first, fallback to Speech Recognition
        do {
            currentTask = "Loading Whisper model..."
            progress = 0.1
            
            if whisperService.isModelAvailable() {
                currentTask = "Transcribing with Whisper..."
                progress = 0.3
                
                let transcription = try await whisperService.transcribeAudio(at: recording.fileURL)
                
                currentTask = "Saving transcription..."
                progress = 0.9
                
                // Save transcription files
                try saveTranscriptionFiles(transcription, for: recording)
                
                progress = 1.0
                return transcription
                
            } else {
                throw TranscriptionError.modelNotAvailable
            }
            
        } catch {
            print("Whisper transcription failed: \(error.localizedDescription)")
            
            // Fallback to SFSpeechRecognizer for short recordings (< 1 minute)
            if recording.duration < 60 {
                currentTask = "Using Apple Speech Recognition..."
                progress = 0.5
                
                do {
                    let transcription = try await speechService.transcribeAudio(at: recording.fileURL)
                    
                    currentTask = "Saving transcription..."
                    progress = 0.9
                    
                    try saveTranscriptionFiles(transcription, for: recording)
                    
                    progress = 1.0
                    return transcription
                    
                } catch {
                    throw TranscriptionError.audioProcessingFailed("Speech recognition also failed: \(error.localizedDescription)")
                }
            } else {
                throw TranscriptionError.audioProcessingFailed("Recording too long for fallback transcription and Whisper unavailable")
            }
        }
    }
    
    private func saveTranscriptionFiles(_ transcription: Transcription, for recording: Recording) throws {
        // Save plain text transcription
        try fileManager.saveTranscription(transcription.text, for: recording.fileURL)
        
        // Save SRT with timestamps if available
        if !transcription.timestamps.isEmpty {
            let srtContent = generateSRTContent(from: transcription)
            try fileManager.saveSRTSubtitles(srtContent, for: recording.fileURL)
        }
        
        // Update recording in CoreData
        recording.transcription = transcription
    }
    
    private func generateSRTContent(from transcription: Transcription) -> String {
        var srtContent = ""
        let words = transcription.text.split(separator: " ")
        let timestampsPerWord = transcription.timestamps.count / max(words.count, 1)
        
        for (index, word) in words.enumerated() {
            let startTime = Double(index * timestampsPerWord) * 0.5 // Rough estimation
            let endTime = startTime + 0.5
            
            srtContent += """
            \(index + 1)
            \(formatSRTTime(startTime)) --> \(formatSRTTime(endTime))
            \(word)
            
            """
        }
        
        return srtContent
    }
    
    private func formatSRTTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        let seconds = Int(timeInterval) % 60
        let milliseconds = Int((timeInterval.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
    
    func cancelTranscription() {
        backgroundTask?.cancel()
        isProcessing = false
        progress = 0.0
        currentTask = ""
    }
}

// MARK: - Whisper Transcription Service

class WhisperTranscriptionService: TranscriptionServiceProtocol {
    private let modelName = "ggml-small-sv-q5_0.bin"
    private let modelSize: Int64 = 80 * 1024 * 1024 // ~80MB
    private var modelURL: URL?
    
    init() {
        setupModel()
    }
    
    private func setupModel() {
        // In a real implementation, this would:
        // 1. Check if model exists in app bundle
        // 2. Download from server if needed
        // 3. Verify model integrity
        
        // For now, we'll simulate the model being available
        modelURL = Bundle.main.url(forResource: "ggml-small-sv-q5_0", withExtension: "bin")
    }
    
    func isModelAvailable() -> Bool {
        // Check if model file exists and is accessible
        guard let modelURL = modelURL else { return false }
        return FileManager.default.fileExists(atPath: modelURL.path)
    }
    
    func getModelSize() -> Int64? {
        return modelSize
    }
    
    func getEstimatedProcessingTime(for duration: TimeInterval) -> TimeInterval {
        // Whisper processes at roughly 2x real-time on modern hardware
        return duration * 2.0
    }
    
    func transcribeAudio(at url: URL) async throws -> Transcription {
        guard isModelAvailable() else {
            throw TranscriptionError.modelNotAvailable
        }
        
        // Simulate transcription processing
        // In a real implementation, this would:
        // 1. Load the Whisper model
        // 2. Process the audio file
        // 3. Return transcribed text with timestamps
        
        try await Task.sleep(nanoseconds: 2_000_000_000) // Simulate 2 second processing
        
        // Mock transcription result
        let mockText = "Detta är en exempeltranskription från Whisper för den svenska ljudfilen."
        let mockTimestamps = generateMockTimestamps(for: mockText)
        
        return Transcription(
            text: mockText,
            confidence: 0.85,
            language: "sv",
            timestamps: mockTimestamps,
            processingTime: 2.0,
            modelUsed: "whisper-small-sv"
        )
    }
    
    private func generateMockTimestamps(for text: String) -> [TimeInterval] {
        let words = text.split(separator: " ")
        return (0..<words.count).map { Double($0) * 0.5 } // One timestamp per word
    }
}

// MARK: - SFSpeech Transcription Service (Fallback)

class SFSpeechTranscriptionService: TranscriptionServiceProtocol {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "sv-SE"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    func isModelAvailable() -> Bool {
        return speechRecognizer?.isAvailable == true
    }
    
    func getModelSize() -> Int64? {
        return nil // Cloud-based, no local model
    }
    
    func getEstimatedProcessingTime(for duration: TimeInterval) -> TimeInterval {
        // SFSpeech is typically faster but requires internet
        return min(duration * 0.5, 10.0) // Cap at 10 seconds
    }
    
    func transcribeAudio(at url: URL) async throws -> Transcription {
        guard isModelAvailable() else {
            throw TranscriptionError.modelNotAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
                recognitionRequest.addAudioPCMBuffer(try loadAudioBuffer(from: url))
                
                recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    if let result = result, result.isFinal {
                        let transcription = Transcription(
                            text: result.bestTranscription.formattedString,
                            confidence: result.bestTranscription.segments.first?.confidence ?? 0.7,
                            language: "sv",
                            processingTime: result.speechRecognitionMetadata?.audioDuration ?? 0,
                            modelUsed: "sfspeech-sv"
                        )
                        continuation.resume(returning: transcription)
                    }
                }
                
                self.recognitionRequest = recognitionRequest
                
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func loadAudioBuffer(from url: URL) throws -> AVAudioPCMBuffer {
        let audioFile = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(audioFile.length))
        try audioFile.read(into: buffer!)
        return buffer!
    }
    
    func requestAuthorization() async throws {
        guard let speechRecognizer = speechRecognizer else {
            throw TranscriptionError.modelNotAvailable
        }
        
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        switch status {
        case .authorized:
            return
        case .notDetermined, .denied, .restricted:
            throw TranscriptionError.audioProcessingFailed("Speech recognition not authorized")
        @unknown default:
            throw TranscriptionError.audioProcessingFailed("Unknown speech recognition status")
        }
    }
}
