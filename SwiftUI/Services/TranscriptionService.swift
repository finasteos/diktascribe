import Foundation
import AVFoundation
import SwiftData
import whisper

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

        // Start background processing task for long transcriptions
        if recording.duration > 30 { // Use BG task for recordings > 30 seconds
            return try await transcribeInBackground(recording)
        } else {
            return try await transcribeInForeground(recording)
        }
    }

    private func transcribeInBackground(_ recording: Recording) async throws -> Transcription {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                // Request background processing capability
                backgroundTask = BGProcessingTask.request(.transcription) { task in
                    Task {
                        do {
                            let transcription = try await self.performTranscriptionInBackground(recording, task: task)
                            continuation.resume(returning: transcription)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }

                if backgroundTask == nil {
                    throw TranscriptionError.audioProcessingFailed("Failed to start background processing")
                }

            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func transcribeInForeground(_ recording: Recording) async throws -> Transcription {
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

    private func performTranscriptionInBackground(_ recording: Recording, task: BGProcessingTask) async throws -> Transcription {
        // Update progress periodically during background processing
        Task { @MainActor in
            currentTask = "Loading Whisper model..."
            progress = 0.1
        }

        if whisperService.isModelAvailable() {
            Task { @MainActor in
                currentTask = "Transcribing with Whisper..."
                progress = 0.3
            }

            let transcription = try await whisperService.transcribeAudio(at: recording.fileURL)

            Task { @MainActor in
                currentTask = "Saving transcription..."
                progress = 0.9
            }

            // Save transcription files
            try saveTranscriptionFiles(transcription, for: recording)

            Task { @MainActor in
                progress = 1.0
            }

            return transcription

        } else {
            throw TranscriptionError.modelNotAvailable
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

// MARK: - Whisper Transcription Service (Real Implementation)

class WhisperTranscriptionService: TranscriptionServiceProtocol {
    private let modelName = "ggml-small-sv-q5_0.bin"
    private let modelSize: Int64 = 80 * 1024 * 1024 // ~80MB
    private var modelURL: URL?
    private var whisperContext: OpaquePointer?

    init() {
        setupModel()
    }

    deinit {
        if let context = whisperContext {
            whisper_free(context)
        }
    }

    private func setupModel() {
        // Check if model exists in app bundle
        modelURL = Bundle.main.url(forResource: "ggml-small-sv-q5_0", withExtension: "bin")

        if let modelURL = modelURL, FileManager.default.fileExists(atPath: modelURL.path) {
            print("Whisper model found at: \(modelURL.path)")
        } else {
            print("Whisper model not found. Please download ggml-small-sv-q5_0.bin to app bundle")
            downloadModelIfNeeded()
        }
    }

    private func downloadModelIfNeeded() {
        // In a real implementation, this would download the model from a server
        // For now, we'll log that the model is missing
        print("Model download not implemented. Please manually add ggml-small-sv-q5_0.bin to your app bundle")
    }

    func isModelAvailable() -> Bool {
        guard let modelURL = modelURL else { return false }
        let exists = FileManager.default.fileExists(atPath: modelURL.path)

        if exists && whisperContext == nil {
            // Initialize Whisper context
            whisperContext = whisper_init_from_file(modelURL.path)
            return whisperContext != nil
        }

        return exists && whisperContext != nil
    }

    func getModelSize() -> Int64? {
        guard let modelURL = modelURL else { return nil }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: modelURL.path)
            return attributes[.size] as? Int64
        } catch {
            return modelSize // Return estimated size if we can't get actual size
        }
    }

    func getEstimatedProcessingTime(for duration: TimeInterval) -> TimeInterval {
        // Whisper with Metal acceleration processes at ~0.5x real-time on M4
        return duration * 0.5
    }

    func transcribeAudio(at url: URL) async throws -> Transcription {
        guard isModelAvailable() else {
            throw TranscriptionError.modelNotAvailable
        }

        guard let whisperContext = whisperContext else {
            throw TranscriptionError.audioProcessingFailed("Whisper context not initialized")
        }

        let startTime = Date()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let transcription = try self.performTranscription(url: url, context: whisperContext)
                    let processingTime = Date().timeIntervalSince(startTime)

                    DispatchQueue.main.async {
                        continuation.resume(returning: transcription)
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func performTranscription(url: URL, context: OpaquePointer) throws -> Transcription {
        // Load audio file
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat

        guard format.sampleRate == 16000 || format.sampleRate == 48000 else {
            throw TranscriptionError.audioProcessingFailed("Unsupported sample rate: \(format.sampleRate)")
        }

        // Read audio data
        let frameCount = AVAudioFrameCount(audioFile.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!

        try audioFile.read(into: buffer, frameCount: frameCount)

        guard let floatData = buffer.floatChannelData?[0] else {
            throw TranscriptionError.audioProcessingFailed("Failed to get audio data")
        }

        // Convert to whisper format (16kHz mono float)
        let samples = convertAudioBufferToWhisperFormat(floatData: floatData, frameCount: Int(frameCount), sourceFormat: format)

        // Set up whisper parameters
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.language = "sv"  // Swedish
        params.translate = false  // Don't translate, keep original language
        params.n_threads = max(1, min(8, ProcessInfo.processInfo.processorCount))
        params.offset_ms = 0
        params.duration_ms = 0  // Process entire audio

        // Run transcription
        let result = whisper_full(context, params, samples, Int32(samples.count))

        guard result == 0 else {
            throw TranscriptionError.audioProcessingFailed("Whisper transcription failed with code: \(result)")
        }

        // Extract results
        let n_segments = whisper_full_n_segments(context)

        var fullText = ""
        var timestamps: [TimeInterval] = []

        for i in 0..<n_segments {
            let text_ptr = whisper_full_get_segment_text(context, i)
            let text = String(cString: text_ptr!)

            let t0 = whisper_full_get_segment_t0(context, i)
            let t1 = whisper_full_get_segment_t1(context, i)

            fullText += text
            if !fullText.isEmpty {
                fullText += " "
            }

            // Add word-level timestamps (approximate)
            let segmentDuration = Double(t1 - t0) / 1000.0
            let words = text.split(separator: " ")
            let timestampStep = segmentDuration / Double(words.count)

            for (index, _) in words.enumerated() {
                timestamps.append(Double(t0) / 1000.0 + Double(index) * timestampStep)
            }
        }

        // Calculate confidence (simplified)
        let confidence = calculateConfidence(context: context, segments: n_segments)

        return Transcription(
            text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: confidence,
            language: "sv",
            timestamps: timestamps,
            processingTime: Date().timeIntervalSince(Date()),
            modelUsed: "whisper-small-sv-metal"
        )
    }

    private func convertAudioBufferToWhisperFormat(floatData: UnsafePointer<Float>, frameCount: Int, sourceFormat: AVAudioFormat) -> [Float] {
        var samples = [Float](repeating: 0.0, count: frameCount)

        // Convert to mono if stereo
        if sourceFormat.channelCount == 2 {
            for i in 0..<frameCount/2 {
                let left = floatData[i * 2]
                let right = floatData[i * 2 + 1]
                samples[i] = (left + right) / 2.0  // Simple mono mix
            }
        } else {
            memcpy(&samples, floatData, frameCount * MemoryLayout<Float>.size)
        }

        // Resample to 16kHz if needed
        if sourceFormat.sampleRate == 48000 {
            samples = resampleTo16kHz(samples: samples)
        }

        return samples
    }

    private func resampleTo16kHz(samples: [Float]) -> [Float] {
        // Simple downsampling from 48kHz to 16kHz (every 3rd sample)
        // In production, use a proper resampling algorithm
        let ratio = 48_000 / 16_000
        let targetCount = Int(Double(samples.count) / ratio)
        var resampled = [Float](repeating: 0.0, count: targetCount)

        for i in 0..<targetCount {
            let sourceIndex = Int(Double(i) * ratio)
            resampled[i] = samples[min(sourceIndex, samples.count - 1)]
        }

        return resampled
    }

    private func calculateConfidence(context: OpaquePointer, segments: Int32) -> Float {
        // Simplified confidence calculation based on segment scores
        var totalConfidence: Float = 0.0

        for i in 0..<segments {
            // Whisper doesn't provide direct confidence scores in the basic API
            // This is a simplified approximation
            totalConfidence += 0.8  // Assume high confidence for now
        }

        return totalConfidence / Float(max(segments, 1))
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
