import SwiftUI
import AVFoundation

// MARK: - Waveform Visualization Component

struct WaveformView: View {
    let audioURL: URL
    @State private var waveformData: [Float] = []
    @State private var isLoading = true
    @State private var playbackProgress: Double = 0.0
    @Binding var isPlaying: Bool
    @Binding var currentTime: TimeInterval

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading waveform...")
                    .onAppear {
                        loadWaveform()
                    }
            } else {
                // Waveform visualization
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background waveform (dimmed)
                        WaveformBars(data: waveformData, isPlaying: false)
                            .opacity(0.3)

                        // Foreground waveform (active part)
                        WaveformBars(data: waveformData, isPlaying: isPlaying)
                            .mask(
                                Rectangle()
                                    .frame(width: geometry.size.width * playbackProgress)
                            )

                        // Playback indicator
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: geometry.size.height)
                            .offset(x: geometry.size.width * playbackProgress)
                    }
                }
                .frame(height: 60)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = min(max(value.location.x / UIScreen.main.bounds.width, 0), 1)
                            seekToProgress(progress)
                        }
                )
            }
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updatePlaybackProgress()
        }
    }

    private func loadWaveform() {
        Task {
            do {
                waveformData = try await generateWaveformData(from: audioURL)
                isLoading = false
            } catch {
                print("Failed to load waveform: \(error.localizedDescription)")
                // Create mock data for demonstration
                waveformData = generateMockWaveformData()
                isLoading = false
            }
        }
    }

    private func generateWaveformData(from url: URL) async throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        // Calculate number of bars (aim for ~100-200 bars for good visualization)
        let barsCount = min(Int(frameCount) / 1024, 200)
        var waveformData = [Float](repeating: 0.0, count: barsCount)

        // Read audio data in chunks
        let bufferSize: AVAudioFrameCount = 1024
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize)!

        var currentFrame: AVAudioFramePosition = 0
        let framesPerBar = Int(frameCount) / barsCount

        for i in 0..<barsCount {
            let framesToRead = min(bufferSize, AVAudioFrameCount(framesPerBar))
            try audioFile.read(into: buffer, frameCount: framesToRead)

            if let channelData = buffer.floatChannelData?[0] {
                var sum: Float = 0.0
                for j in 0..<Int(framesToRead) {
                    sum += abs(channelData[j])
                }
                waveformData[i] = sum / Float(framesToRead)
            }

            currentFrame += AVAudioFramePosition(framesToRead)
        }

        // Normalize the data
        let maxAmplitude = waveformData.max() ?? 1.0
        return waveformData.map { $0 / maxAmplitude }
    }

    private func generateMockWaveformData() -> [Float] {
        // Generate realistic-looking mock waveform data
        var data = [Float]()
        for i in 0..<100 {
            let baseAmplitude = sin(Float(i) * 0.1) * 0.3
            let randomVariation = Float.random(in: -0.2...0.2)
            let amplitude = max(0.1, min(1.0, abs(baseAmplitude + randomVariation)))
            data.append(amplitude)
        }
        return data
    }

    private func updatePlaybackProgress() {
        guard !waveformData.isEmpty else { return }

        // In a real implementation, this would get the current playback time
        // from the audio player and calculate progress
        // For now, we'll simulate progress when playing
        if isPlaying {
            playbackProgress = min(playbackProgress + 0.01, 1.0)
        }
    }

    private func seekToProgress(_ progress: Double) {
        // In a real implementation, this would seek the audio player
        // to the corresponding time position
        playbackProgress = progress
        print("Seeking to progress: \(progress)")
    }
}

// MARK: - Waveform Bars Component

struct WaveformBars: View {
    let data: [Float]
    let isPlaying: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 1) {
            ForEach(0..<data.count, id: \.self) { index in
                WaveformBar(
                    amplitude: data[index],
                    isPlaying: isPlaying,
                    index: index,
                    totalCount: data.count
                )
            }
        }
    }
}

// MARK: - Individual Waveform Bar

struct WaveformBar: View {
    let amplitude: Float
    let isPlaying: Bool
    let index: Int
    let totalCount: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(barColor)
            .frame(width: barWidth, height: barHeight)
    }

    private var barColor: Color {
        if isPlaying {
            let progress = Double(index) / Double(totalCount)
            return progress <= 0.5 ? .accentColor : .accentColor.opacity(0.5)
        } else {
            return .primary.opacity(0.7)
        }
    }

    private var barWidth: CGFloat {
        // Wider bars for fewer data points, narrower for more
        max(2, min(4, 200 / CGFloat(totalCount)))
    }

    private var barHeight: CGFloat {
        // Scale amplitude to reasonable height range
        max(4, CGFloat(amplitude) * 50)
    }
}

// MARK: - Preview

struct WaveformView_Previews: PreviewProvider {
    static var previews: some View {
        WaveformView(
            audioURL: URL(fileURLWithPath: "/tmp/test.flac"),
            isPlaying: .constant(false),
            currentTime: .constant(0)
        )
    }
}
