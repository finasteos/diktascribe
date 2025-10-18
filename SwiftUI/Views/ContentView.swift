import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = RecordingViewModel()
    @State private var showTranscriptionProgress = false
    @State private var selectedRecordingForTranscription: Recording?

    var body: some View {
        NavigationStack {
            VStack {

                // Search bar
                SearchBar(text: $viewModel.searchText)
                    .padding(.horizontal)

                // List of recordings
                List {
                    ForEach(viewModel.searchRecordings()) { recording in
                        RecordingRow(
                            recording: recording,
                            isPlaying: viewModel.currentlyPlayingURL == recording.fileURL && viewModel.isPlaying,
                            playAction: {
                                viewModel.playRecording(url: recording.fileURL)
                            },
                            transcribeAction: {
                                Task {
                                    await viewModel.transcribeRecording(recording)
                                }
                            },
                            toggleFavoriteAction: {
                                viewModel.toggleFavorite(recording)
                            }
                        )
                    }
                    .onDelete { indexSet in
                        let recordings = viewModel.searchRecordings()
                        for index in indexSet {
                            viewModel.deleteRecording(recordings[index])
                        }
                    }
                }
                .listStyle(PlainListStyle())

                Spacer()

                // Recording control footer
                RecordingFooter(viewModel: viewModel)

            }
            .navigationTitle("LAGA Ideas Recorder")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Export All") {
                            // TODO: Implement bulk export
                        }

                        Button("Settings") {
                            // TODO: Implement settings view
                        }

                        Button("Create Test Recording") {
                            viewModel.createTestRecording()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
                Task {
                    await viewModel.requestMicrophonePermission()
                }
            }
            .sheet(isPresented: $showTranscriptionProgress) {
                TranscriptionProgressView(
                    isVisible: $showTranscriptionProgress,
                    progress: viewModel.transcriptionProgress,
                    currentTask: viewModel.currentTranscriptionTask,
                    onCancel: {
                        // TODO: Implement transcription cancellation
                    }
                )
            }
        }
    }
}

// MARK: - RecordingRow View
struct RecordingRow: View {
    let recording: Recording
    let isPlaying: Bool
    let playAction: () -> Void
    let transcribeAction: () -> Void
    let toggleFavoriteAction: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(recording.displayTitle)
                        .font(.headline)
                        .lineLimit(1)

                    if recording.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.subheadline)
                    }
                }

                Text(recording.createdAt, style: .date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(recording.formattedFileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if recording.transcription != nil {
                        Image(systemName: "text.bubble")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button(action: transcribeAction) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 20))
                        .foregroundColor(recording.transcription != nil ? .green : .accentColor)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: playAction) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: toggleFavoriteAction) {
                Label(recording.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: recording.isFavorite ? "star.slash" : "star")
            }

            Button(action: transcribeAction) {
                Label(recording.transcription != nil ? "Retranscribe" : "Transcribe",
                      systemImage: "text.viewfinder")
            }

            Divider()

            Button(role: .destructive) {
                // Delete action handled by List's onDelete
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - RecordingFooter View
struct RecordingFooter: View {
    @ObservedObject var viewModel: RecordingViewModel

    var body: some View {
        VStack {
            if viewModel.isRecording {
                VStack {
                    Text(formatTime(viewModel.recordingTime))
                        .font(.title)
                        .padding()

                    // Audio level indicator
                    AudioLevelIndicator(level: viewModel.audioLevel)
                        .frame(height: 4)
                        .padding(.horizontal)
                }
                .transition(.opacity)
            }

            Button(action: {
                Task {
                    if viewModel.isRecording {
                        viewModel.stopRecording()
                    } else {
                        await viewModel.startRecording()
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .fill(viewModel.isRecording ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(viewModel.isRecording ? .red : .accentColor)
                }
            }
            .padding(.bottom)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
    }
}

// MARK: - AudioLevelIndicator View
struct AudioLevelIndicator: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: geometry.size.width, height: geometry.size.height)

                Rectangle()
                    .fill(Color.green)
                    .frame(width: geometry.size.width * CGFloat(level), height: geometry.size.height)
            }
            .cornerRadius(geometry.size.height / 2)
        }
    }
}

// MARK: - SearchBar View
struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search recordings...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - TranscriptionProgressView
struct TranscriptionProgressView: View {
    @Binding var isVisible: Bool
    let progress: Double
    let currentTask: String
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                ProgressView(value: progress) {
                    Text(currentTask)
                        .font(.headline)
                }
                .progressViewStyle(LinearProgressViewStyle())
                .padding()

                Text("Processing transcription...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button("Cancel", role: .cancel, action: onCancel)
                    .padding()
            }
            .padding()
            .navigationTitle("Transcription")
            .navigationBarItems(trailing: Button("Done") {
                isVisible = false
            })
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// MARK: - Helper Functions

func formatTime(_ timeInterval: TimeInterval) -> String {
    let minutes = Int(timeInterval) / 60
    let seconds = Int(timeInterval) % 60
    return String(format: "%d:%02d", minutes, seconds)
}
