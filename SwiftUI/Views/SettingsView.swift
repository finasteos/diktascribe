import SwiftUI
import SPIndicator

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showGitHubSetup = false
    @State private var showAbout = false
    @StateObject private var gitHubService = GitHubService()

    var body: some View {
        NavigationStack {
            List {
                // GitHub Integration Section
                Section("GitHub Integration") {
                    Button(action: {
                        showGitHubSetup = true
                    }) {
                        HStack {
                            Image(systemName: "network")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text("LAGA Repository")
                                    .font(.body)
                                Text("Configure GitHub token to send recordings")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: {
                        Task {
                            await testGitHubConnection()
                        }
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                            Text("Test Connection")
                            Spacer()
                            if gitHubService.isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                        }
                    }
                    .disabled(gitHubService.isExporting)
                }

                // Audio Settings Section
                Section("Audio Settings") {
                    NavigationLink("Audio Quality", destination: AudioSettingsView())
                    NavigationLink("Processing Presets", destination: ProcessingPresetsView())
                }

                // Storage Settings Section
                Section("Storage") {
                    NavigationLink("Storage Location", destination: StorageSettingsView())
                    NavigationLink("Auto-cleanup", destination: CleanupSettingsView())
                }

                // About Section
                Section("About") {
                    Button(action: {
                        showAbout = true
                    }) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("About LAGA Ideas Recorder")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showGitHubSetup) {
                GitHubSetupView()
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
        }
    }

    private func testGitHubConnection() async {
        do {
            let isConnected = try await gitHubService.testConnection()

            if isConnected {
                SPIndicator.present(title: "Connected!", message: "GitHub connection successful", preset: .done, haptic: .success)
            } else {
                SPIndicator.present(title: "Connection Failed", message: "Could not connect to GitHub", preset: .error, haptic: .error)
            }
        } catch {
            SPIndicator.present(title: "Connection Failed", message: error.localizedDescription, preset: .error, haptic: .error)
        }
    }
}

// MARK: - Audio Settings View

struct AudioSettingsView: View {
    @State private var sampleRate = 48000
    @State private var bitDepth = 16
    @State private var channels = 1

    var body: some View {
        List {
            Section("Recording Quality") {
                Picker("Sample Rate", selection: $sampleRate) {
                    Text("16 kHz").tag(16000)
                    Text("48 kHz").tag(48000)
                }

                Picker("Bit Depth", selection: $bitDepth) {
                    Text("16-bit").tag(16)
                    Text("24-bit").tag(24)
                }

                Picker("Channels", selection: $channels) {
                    Text("Mono").tag(1)
                    Text("Stereo").tag(2)
                }
            }

            Section("Advanced") {
                Toggle("Auto-gain Control", isOn: .constant(true))
                Toggle("Noise Reduction", isOn: .constant(true))
                Toggle("Silence Detection", isOn: .constant(true))
            }
        }
        .navigationTitle("Audio Quality")
    }
}

// MARK: - Processing Presets View

struct ProcessingPresetsView: View {
    @State private var selectedPreset = "Restaurant"

    var body: some View {
        List {
            Section("Environment Presets") {
                Picker("Current Preset", selection: $selectedPreset) {
                    Text("Restaurant").tag("Restaurant")
                    Text("Office").tag("Office")
                    Text("Outdoor").tag("Outdoor")
                    Text("Custom").tag("Custom")
                }
                .pickerStyle(.inline)
            }

            Section("Preset Details") {
                switch selectedPreset {
                case "Restaurant":
                    PresetDetailView(
                        name: "Restaurant",
                        description: "Optimized for noisy restaurant environments",
                        highPass: "100 Hz",
                        noiseGate: "-35 dB",
                        compression: "6:1"
                    )
                case "Office":
                    PresetDetailView(
                        name: "Office",
                        description: "Clean office environment settings",
                        highPass: "80 Hz",
                        noiseGate: "-45 dB",
                        compression: "3:1"
                    )
                case "Outdoor":
                    PresetDetailView(
                        name: "Outdoor",
                        description: "Wind and ambient noise reduction",
                        highPass: "120 Hz",
                        noiseGate: "-30 dB",
                        compression: "5:1"
                    )
                default:
                    Text("Custom preset configuration")
                }
            }
        }
        .navigationTitle("Processing Presets")
    }
}

// MARK: - Storage Settings View

struct StorageSettingsView: View {
    @State private var storageLocation = "~/Documents/Ideas"
    @State private var cloudSyncEnabled = true

    var body: some View {
        List {
            Section("Storage Location") {
                TextField("Storage Path", text: $storageLocation)
                Toggle("iCloud Sync", isOn: $cloudSyncEnabled)
            }

            Section("Usage") {
                HStack {
                    Text("Used Space")
                    Spacer()
                    Text("2.4 GB")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Available Space")
                    Spacer()
                    Text("45.2 GB")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Storage")
    }
}

// MARK: - Cleanup Settings View

struct CleanupSettingsView: View {
    @State private var autoCleanupEnabled = true
    @State private var cleanupDays = 30

    var body: some View {
        List {
            Section("Automatic Cleanup") {
                Toggle("Enable Auto-cleanup", isOn: $autoCleanupEnabled)

                if autoCleanupEnabled {
                    Stepper("Delete after \(cleanupDays) days", value: $cleanupDays, in: 7...365)
                }
            }

            Section("Manual Cleanup") {
                Button("Clean Now", role: .destructive) {
                    // TODO: Implement manual cleanup
                }
            }
        }
        .navigationTitle("Auto-cleanup")
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "waveform")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                Text("LAGA Ideas Recorder")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version 1.0.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Professional audio recording and AI transcription for Swedish content. Built for the LAGA development workflow.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                VStack(spacing: 8) {
                    Text("Built with:")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack(spacing: 20) {
                        Text("🎙️ AudioKit")
                        Text("🤖 Whisper.swift")
                        Text("☁️ CloudKit")
                        Text("📱 SwiftUI")
                    }
                    .font(.caption)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Preset Detail View

struct PresetDetailView: View {
    let name: String
    let description: String
    let highPass: String
    let noiseGate: String
    let compression: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("High-pass Filter: \(highPass)")
                Text("Noise Gate: \(noiseGate)")
                Text("Compression: \(compression)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
