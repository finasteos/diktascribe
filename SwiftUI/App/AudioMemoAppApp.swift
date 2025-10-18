import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct AudioMemoAppApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: LAGAAppDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
            Transcription.self,
            RecordingThread.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(sharedModelContainer)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording") {
                    // TODO: Implement global recording shortcut
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        .onChange(of: UIApplication.shared.backgroundRefreshStatus) { status in
            switch status {
            case .available:
                print("Background refresh available")
                BGProcessingTask.registerBackgroundTasks()
            case .denied:
                print("Background refresh denied")
            case .restricted:
                print("Background refresh restricted")
            @unknown default:
                print("Unknown background refresh status")
            }
        }
    }
}
