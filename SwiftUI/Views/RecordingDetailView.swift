import SwiftUI
import SwiftData

// MARK: - Recording Detail View

struct RecordingDetailView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RecordingViewModel()
    @State private var showTranscriptionSheet = false
    @State private var showExportSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Recording Info Card
                    RecordingInfoCard(recording: recording)

                    // Full Waveform Visualization
                    WaveformSection(
                        recording: recording,
                        isPlaying: false, // TODO: Connect to actual playback state
                        currentTime: 0
                    )

                    // Transcription Section
                    if let transcription = recording.transcription {
                        TranscriptionSection(transcription: transcription)
                    } else {
                        NoTranscriptionSection {
                            showTranscriptionSheet = true
                        }
                    }

                    // Action Buttons
                    ActionSection(recording: recording) {
                        showExportSheet = true
                    }

                    // Metadata Section
                    MetadataSection(recording: recording)
                }
                .padding()
            }
            .navigationTitle(recording.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Export") {
                            showExportSheet = true
                        }

                        Button("Share") {
                            shareRecording()
                        }

                        Divider()

                        Button("Add to Thread") {
                            // TODO: Implement thread assignment
                        }

                        Button("Rename") {
                            // TODO: Implement renaming
                        }

                        Divider()

                        Button("Delete", role: .destructive) {
                            // TODO: Implement deletion with confirmation
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showTranscriptionSheet) {
                TranscriptionProgressView(
                    isVisible: $showTranscriptionSheet,
                    progress: 0.0,
                    currentTask: "Starting transcription...",
                    onCancel: {
                        showTranscriptionSheet = false
                    }
                )
            }
            .sheet(isPresented: $showExportSheet) {
                ExportOptionsView(recording: recording)
            }
        }
    }

    private func shareRecording() {
        // TODO: Implement sharing functionality
        print("Sharing recording: \(recording.fileName)")
    }
}

// MARK: - Recording Info Card

struct RecordingInfoCard: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(recording.displayTitle)
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                if recording.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.title3)
                }
            }

            HStack(spacing: 16) {
                Label(recording.formattedDuration, systemImage: "clock")
                Label(recording.formattedFileSize, systemImage: "doc")
                Label(recording.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Waveform Section

struct WaveformSection: View {
    let recording: Recording
    let isPlaying: Bool
    let currentTime: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Waveform")
                .font(.headline)

            WaveformView(
                audioURL: recording.fileURL,
                isPlaying: .constant(isPlaying),
                currentTime: .constant(currentTime)
            )
            .frame(height: 120)
            .background(Color(.systemGray6))
            .cornerRadius(8)

            // Playback Controls
            HStack {
                Button(action: {
                    // TODO: Play/Pause
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(.accentColor)
                }

                Spacer()

                Button(action: {
                    // TODO: Skip backward
                }) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }

                Spacer()

                Button(action: {
                    // TODO: Skip forward
                }) {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }

                Spacer()

                Button(action: {
                    // TODO: Toggle playback speed
                }) {
                    Image(systemName: "speedometer")
                        .font(.title2)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Transcription Section

struct TranscriptionSection: View {
    let transcription: Transcription

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcription")
                    .font(.headline)

                Spacer()

                HStack(spacing: 8) {
                    Label(transcription.formattedConfidence, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)

                    Label(transcription.formattedProcessingTime, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ScrollView {
                Text(transcription.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            .frame(height: 150)

            if transcription.hasSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(transcription.summary!)
                        .font(.callout)
                        .italic()
                        .padding()
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            if transcription.hasTranslation {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Translation")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(transcription.translation!)
                        .font(.callout)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - No Transcription Section

struct NoTranscriptionSection: View {
    let onTranscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription")
                .font(.headline)

            VStack(alignment: .center, spacing: 16) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("No transcription available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button("Transcribe Recording", action: onTranscribe)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

// MARK: - Action Section

struct ActionSection: View {
    let recording: Recording
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: {
                // TODO: Share recording
            }) {
                Label("Share", systemImage: "square.and.arrow.up.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: {
                // TODO: Add to favorites
            }) {
                Label(recording.isFavorite ? "Favorited" : "Add to Favorites", systemImage: "star")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(recording.isFavorite ? .yellow : .accentColor)
        }
    }
}

// MARK: - Metadata Section

struct MetadataSection: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Technical Details")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Sample Rate", value: "\(Int(recording.sampleRate)) Hz")
                DetailRow(label: "Channels", value: "\(recording.channels)")
                DetailRow(label: "Format", value: recording.format.uppercased())
                DetailRow(label: "File Path", value: recording.fileURL.lastPathComponent)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Export Options View

struct ExportOptionsView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Export Format") {
                    Button("Markdown (.md)") {
                        exportAs(.markdown)
                    }

                    Button("PDF Document") {
                        exportAs(.pdf)
                    }

                    Button("Plain Text (.txt)") {
                        exportAs(.txt)
                    }
                }

                Section("Quick Actions") {
                    Button("Copy Transcription") {
                        // TODO: Copy to clipboard
                    }

                    Button("Share Link") {
                        // TODO: Generate shareable link
                    }
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func exportAs(_ format: ExportFormat) {
        // TODO: Implement actual export
        print("Exporting as \(format)")
        dismiss()
    }
}

// MARK: - Preview

struct RecordingDetailView_Previews: PreviewProvider {
    static var previews: some View {
        RecordingDetailView(
            recording: Recording(
                title: "Brainstorm Session",
                fileName: "recording_2024-01-15_14-30-00.flac",
                fileURL: URL(fileURLWithPath: "/tmp/test.flac"),
                duration: 125.5,
                fileSize: 2048 * 1024
            )
        )
    }
}
