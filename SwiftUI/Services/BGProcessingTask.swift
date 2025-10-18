import Foundation
import BackgroundTasks

// MARK: - Background Processing Task Manager

enum BGProcessingTaskType {
    case transcription
    case export
    case sync

    var identifier: String {
        switch self {
        case .transcription:
            return "ai.laga.ideas.transcription"
        case .export:
            return "ai.laga.ideas.export"
        case .sync:
            return "ai.laga.ideas.sync"
        }
    }
}

@MainActor
class BGProcessingTask {
    private let task: BGTask?
    private let type: BGProcessingTaskType

    init?(type: BGProcessingTaskType, completion: @escaping (BGProcessingTask) -> Void) {
        self.type = type

        // Register background task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: type.identifier, using: nil) { task in
            let bgTask = BGProcessingTask(task: task, type: type)
            completion(bgTask)
        }

        // Try to get existing task or schedule new one
        if let existingTask = BGTaskScheduler.shared.pendingTask(withIdentifier: type.identifier) {
            self.task = existingTask
        } else {
            // Schedule new background task
            do {
                let request = BGProcessingTaskRequest(identifier: type.identifier)
                request.earliestBeginDate = Date(timeIntervalSinceNow: 1) // Start in 1 second
                try BGTaskScheduler.shared.submit(request)
                self.task = nil // Will be created when task runs
            } catch {
                print("Failed to schedule background task: \(error.localizedDescription)")
                return nil
            }
        }
    }

    private init(task: BGTask, type: BGProcessingTaskType) {
        self.task = task
        self.type = type

        // Set expiration handler
        task.expirationHandler = {
            print("Background task expired: \(type.identifier)")
            task.setTaskCompleted(success: false)
        }
    }

    static func request(_ type: BGProcessingTaskType, completion: @escaping (BGProcessingTask) -> Void) -> BGProcessingTask? {
        return BGProcessingTask(type: type, completion: completion)
    }

    func cancel() {
        task?.setTaskCompleted(success: false)
    }

    func complete(success: Bool) {
        task?.setTaskCompleted(success: success)
    }

    // MARK: - Background Task Scheduling

    static func scheduleTranscriptionTask() {
        do {
            let request = BGProcessingTaskRequest(identifier: BGProcessingTaskType.transcription.identifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: 5) // Start in 5 seconds
            try BGTaskScheduler.shared.submit(request)
            print("Scheduled transcription background task")
        } catch {
            print("Failed to schedule transcription task: \(error.localizedDescription)")
        }
    }

    static func scheduleExportTask() {
        do {
            let request = BGProcessingTaskRequest(identifier: BGProcessingTaskType.export.identifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: 10) // Start in 10 seconds
            try BGTaskScheduler.shared.submit(request)
            print("Scheduled export background task")
        } catch {
            print("Failed to schedule export task: \(error.localizedDescription)")
        }
    }

    static func scheduleSyncTask() {
        do {
            let request = BGProcessingTaskRequest(identifier: BGProcessingTaskType.sync.identifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: 30) // Start in 30 seconds
            try BGTaskScheduler.shared.submit(request)
            print("Scheduled sync background task")
        } catch {
            print("Failed to schedule sync task: \(error.localizedDescription)")
        }
    }

    // MARK: - Background Task Handler Registration

    static func registerBackgroundTasks() {
        // Register transcription task handler
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BGProcessingTaskType.transcription.identifier, using: nil) { task in
            handleTranscriptionTask(task: task)
        }

        // Register export task handler
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BGProcessingTaskType.export.identifier, using: nil) { task in
            handleExportTask(task: task)
        }

        // Register sync task handler
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BGProcessingTaskType.sync.identifier, using: nil) { task in
            handleSyncTask(task: task)
        }
    }

    private static func handleTranscriptionTask(task: BGTask) {
        let bgTask = BGProcessingTask(task: task, type: .transcription)

        // Perform transcription work here
        Task {
            do {
                // Simulate transcription work
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                bgTask.complete(success: true)
                print("Background transcription completed successfully")
            } catch {
                bgTask.complete(success: false)
                print("Background transcription failed: \(error.localizedDescription)")
            }
        }
    }

    private static func handleExportTask(task: BGTask) {
        let bgTask = BGProcessingTask(task: task, type: .export)

        // Perform export work here
        Task {
            do {
                // Simulate export work
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                bgTask.complete(success: true)
                print("Background export completed successfully")
            } catch {
                bgTask.complete(success: false)
                print("Background export failed: \(error.localizedDescription)")
            }
        }
    }

    private static func handleSyncTask(task: BGTask) {
        let bgTask = BGProcessingTask(task: task, type: .sync)

        // Perform sync work here
        Task {
            do {
                // Simulate sync work
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                bgTask.complete(success: true)
                print("Background sync completed successfully")
            } catch {
                bgTask.complete(success: false)
                print("Background sync failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - App Delegate Integration

class LAGAAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // Register background tasks
        BGProcessingTask.registerBackgroundTasks()

        // Schedule initial background tasks if needed
        BGProcessingTask.scheduleTranscriptionTask()

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Schedule background tasks when entering background
        BGProcessingTask.scheduleTranscriptionTask()
    }
}
