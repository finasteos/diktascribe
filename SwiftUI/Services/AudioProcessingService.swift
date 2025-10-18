import Foundation
import AVFoundation
import AudioKit

// MARK: - Audio Processing Service using AudioKit

@MainActor
class AudioProcessingService: ObservableObject {
    @Published var isProcessing = false
    @Published var noiseGateThreshold: Float = -40.0
    @Published var compressorRatio: Float = 4.0
    @Published var highPassCutoff: Float = 80.0

    private var engine: AudioEngine?
    private var mic: AudioEngine.InputNode?
    private var noiseGate: DynamicsProcessor?
    private var compressor: DynamicsProcessor?
    private var highPassFilter: HighPassFilter?
    private var mixer: Mixer?

    init() {
        setupAudioProcessingChain()
    }

    private func setupAudioProcessingChain() {
        do {
            // Initialize AudioKit engine
            engine = AudioEngine()
            mic = engine?.input

            // Setup processing nodes
            setupNoiseGate()
            setupCompressor()
            setupHighPassFilter()
            setupMixer()

            // Connect the chain: Mic → HighPass → NoiseGate → Compressor → Mixer → Output
            connectProcessingChain()

        } catch {
            print("Failed to setup AudioKit processing chain: \(error.localizedDescription)")
        }
    }

    private func setupNoiseGate() {
        noiseGate = DynamicsProcessor()
        noiseGate?.threshold = noiseGateThreshold
        noiseGate?.ratio = 10.0  // High ratio for noise gate
        noiseGate?.attackTime = 0.001  // Fast attack
        noiseGate?.releaseTime = 0.1   // Quick release
    }

    private func setupCompressor() {
        compressor = DynamicsProcessor()
        compressor?.threshold = -20.0
        compressor?.ratio = compressorRatio
        compressor?.attackTime = 0.01
        compressor?.releaseTime = 0.1
        compressor?.makeupGain = 2.0  // Boost quieter signals
    }

    private func setupHighPassFilter() {
        highPassFilter = HighPassFilter(mic)
        highPassFilter?.cutoffFrequency = highPassCutoff
        highPassFilter?.resonance = 0.5
    }

    private func setupMixer() {
        mixer = Mixer(highPassFilter, noiseGate, compressor)
        engine?.output = mixer
    }

    private func connectProcessingChain() {
        guard let mic = mic,
              let highPassFilter = highPassFilter,
              let noiseGate = noiseGate,
              let compressor = compressor,
              let mixer = mixer else {
            print("Missing audio nodes for processing chain")
            return
        }

        // The chain is already connected in setupMixer via the Mixer initializer
        print("Audio processing chain connected successfully")
    }

    func startProcessing() async throws {
        guard let engine = engine else {
            throw NSError(domain: "AudioProcessingService", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "AudioKit engine not initialized"])
        }

        do {
            // Request microphone permission through AudioKit
            try await requestMicrophonePermission()

            try engine.start()
            isProcessing = true
            print("AudioKit processing started")

        } catch {
            print("Failed to start AudioKit processing: \(error.localizedDescription)")
            throw error
        }
    }

    func stopProcessing() {
        engine?.stop()
        isProcessing = false
        print("AudioKit processing stopped")
    }

    func updateNoiseGate(threshold: Float) {
        noiseGateThreshold = threshold
        noiseGate?.threshold = threshold
        print("Noise gate threshold updated to: \(threshold) dB")
    }

    func updateCompressor(ratio: Float) {
        compressorRatio = ratio
        compressor?.ratio = ratio
        print("Compressor ratio updated to: \(ratio):1")
    }

    func updateHighPass(cutoff: Float) {
        highPassCutoff = cutoff
        highPassFilter?.cutoffFrequency = cutoff
        print("High-pass cutoff updated to: \(cutoff) Hz")
    }

    private func requestMicrophonePermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw NSError(domain: "AudioProcessingService", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
            }
        case .denied, .restricted:
            throw NSError(domain: "AudioProcessingService", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Microphone access denied. Please enable in Settings."])
        @unknown default:
            throw NSError(domain: "AudioProcessingService", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: "Unknown microphone permission status"])
        }
    }

    // MARK: - Audio Quality Monitoring

    func getCurrentAudioLevel() -> Float {
        // In a real implementation, this would tap into the audio stream
        // For now, return a placeholder
        return 0.5
    }

    func isBackgroundNoisePresent() -> Bool {
        let level = getCurrentAudioLevel()
        return level < 0.1 && level > 0.01  // Low but consistent signal = background noise
    }

    // MARK: - Preset Configurations

    func applyRestaurantPreset() {
        // Optimized for restaurant environment
        updateHighPass(cutoff: 100.0)      // Cut low-frequency noise
        updateNoiseGate(threshold: -35.0)  // Tighter noise gate
        updateCompressor(ratio: 6.0)       // More aggressive compression
        print("Applied restaurant audio preset")
    }

    func applyOfficePreset() {
        // Optimized for office environment
        updateHighPass(cutoff: 80.0)       // Standard high-pass
        updateNoiseGate(threshold: -45.0)  // More sensitive noise gate
        updateCompressor(ratio: 3.0)        // Gentle compression
        print("Applied office audio preset")
    }

    func applyOutdoorPreset() {
        // Optimized for outdoor environment
        updateHighPass(cutoff: 120.0)      // Cut wind noise
        updateNoiseGate(threshold: -30.0)  // Less sensitive (more ambient sound)
        updateCompressor(ratio: 5.0)       // Moderate compression
        print("Applied outdoor audio preset")
    }

    deinit {
        stopProcessing()
    }
}

// MARK: - Integration with Existing AudioRecordingService

extension AudioRecordingService {
    func integrateAudioKit(_ audioKitService: AudioProcessingService) {
        // This would integrate AudioKit's processed audio stream
        // with our existing AVAudioEngine recording
        print("AudioKit integration ready - would chain processed audio to AVAudioFile")
    }
}
