import SwiftUI
import SwiftData

@main
struct DogLensMacApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DogBreed.self,
            BreedImage.self
        ])
        // Explicitly set cloudKitDatabase to .none so SwiftData uses clean local storage
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return container
        } catch {
            print("Failed to load ModelContainer with default config: \(error). Attempting in-memory fallback...")
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let memoryContainer = try? ModelContainer(for: schema, configurations: [memoryConfig]) {
                return memoryContainer
            }
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }
    }
}
