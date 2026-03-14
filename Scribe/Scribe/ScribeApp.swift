import SwiftUI
import SwiftData

@main
struct ScribeApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
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
            RecordingListView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }
}
