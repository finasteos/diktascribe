import Foundation
import AVFoundation
import SwiftData

@MainActor
class AudioRecordingService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var recordingTime: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var currentlyPlayingURL: URL?
    
    private let audioEngine = AVAudioEngine()
    private let inputNode: AVAudioInputNode
    private var audioFile: AVAudioFile?
    private var displayLink: CADisplayLink?
    private var silenceTimer: Timer?
    private var recordingTimer: Timer?
    private var silenceThreshold: Float = -40.0 // dB
    private var maxSilenceDuration: TimeInterval = 3.0 // seconds
    
    // Audio format: 48kHz mono FLAC
    private let audioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 48000,
        channels: 1,
        interleaved: true
    )!
    
    private var context: ModelContext?
    private var currentRecording: Recording?
    private let fileManager = FileManager.default
    
    override init() {
        self.inputNode = audioEngine.inputNode
        super.init()
        setupAudioSession()
        setupNotifications()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.context = context
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Configure for recording and playback
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setPreferredSampleRate(48000)
            try audioSession.setPreferredInputNumberOfChannels(1)
            
            // Set buffer duration for low latency
            try audioSession.setPreferredIOBufferDuration(0.005)
            
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error.localizedDescription)")
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            stopRecording()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Resume recording if appropriate
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .newDeviceAvailable:
            // New microphone available (e.g., AirPods connected)
            print("New audio device available")
        case .oldDeviceUnavailable:
            if isRecording {
                stopRecording()
            }
        default:
            break
        }
    }
    
    func startRecording() async throws {
        guard !isRecording else { return }
        
        do {
            // Request microphone permission
            try await requestMicrophonePermission()
            
            // Create file URL
            let fileName = "recording_\(DateFormatter.filenameFormatter.string(from: Date())).flac"
            let fileURL = try getDocumentsDirectory().appendingPathComponent("Ideas/\(DateFormatter.dateFolderFormatter.string(from: Date()))/\(fileName)")
            
            // Ensure directory exists
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            // Setup audio engine
            let outputFile = try AVAudioFile(forWriting: fileURL, settings: audioFormat.settings)
            
            // Install tap on input node for audio level monitoring
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.inputFormat(forBus: 0)) { [weak self] buffer, time in
                self?.processAudioBuffer(buffer)
            }
            
            // Start engine
            try audioEngine.start()
            
            // Start recording timer
            startRecordingTimer()
            
            // Reset silence detection
            resetSilenceDetection()
            
            isRecording = true
            audioFile = outputFile
            
            print("Started recording to: \(fileURL.path)")
            
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
            throw error
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        // Stop timers
        stopRecordingTimer()
        stopSilenceDetection()
        
        // Remove tap
        inputNode.removeTap(onBus: 0)
        
        // Stop engine
        audioEngine.stop()
        
        // Finalize audio file
        if let audioFile = audioFile {
            let fileURL = audioFile.url
            let fileSize = fileManager.fileSize(at: fileURL)
            
            // Create recording model
            currentRecording = Recording(
                fileName: fileURL.lastPathComponent,
                fileURL: fileURL,
                duration: recordingTime,
                fileSize: fileSize
            )
            
            // Save to CoreData if context is available
            if let context = context, let recording = currentRecording {
                context.insert(recording)
                try? context.save()
            }
            
            self.audioFile = nil
            print("Stopped recording. File: \(fileURL.path), Size: \(fileSize) bytes")
        }
        
        isRecording = false
        recordingTime = 0
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Calculate RMS for audio level
        if let channelData = buffer.floatChannelData?[0] {
            let channelLength = Int(buffer.frameLength)
            var sum: Float = 0
            
            for i in 0..<channelLength {
                sum += channelData[i] * channelData[i]
            }
            
            let rms = sqrtf(sum / Float(channelLength))
            let db = 20 * log10f(rms)
            
            DispatchQueue.main.async {
                self.audioLevel = max(0, (db + 60) / 60) // Normalize to 0-1
            }
            
            // Check for silence
            checkSilenceLevel(db)
        }
        
        // Write to file if recording
        if isRecording, let audioFile = audioFile {
            do {
                try audioFile.write(from: buffer)
            } catch {
                print("Failed to write audio buffer: \(error.localizedDescription)")
            }
        }
    }
    
    private func checkSilenceLevel(_ db: Float) {
        if db < silenceThreshold {
            // Start or continue silence timer
            if silenceTimer == nil {
                silenceTimer = Timer.scheduledTimer(withTimeInterval: maxSilenceDuration, repeats: false) { [weak self] _ in
                    print("Silence detected for \(self?.maxSilenceDuration ?? 0)s, stopping recording")
                    self?.stopRecording()
                }
            }
        } else {
            // Reset silence timer
            resetSilenceDetection()
        }
    }
    
    private func resetSilenceDetection() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingTime += 0.1
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    func requestMicrophonePermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw NSError(domain: "AudioRecordingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
            }
        case .denied, .restricted:
            throw NSError(domain: "AudioRecordingService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied. Please enable in Settings."])
        @unknown default:
            throw NSError(domain: "AudioRecordingService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown microphone permission status"])
        }
    }
    
    private func getDocumentsDirectory() throws -> URL {
        try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }
    
    deinit {
        stopRecording()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Helper Extensions

extension DateFormatter {
    static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
    
    static let dateFolderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension FileManager {
    func fileSize(at url: URL) -> Int64 {
        (try? attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}
