import SwiftUI
import SwiftData

@main
struct AudioMemoAppApp: App {
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
    }
}
