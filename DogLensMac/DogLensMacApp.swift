import SwiftUI
import SwiftData

@main
struct DogLensMacApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DogBreed.self,
            BreedImage.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            seedPredefinedBreedsIfNeeded(context: container.mainContext)
            return container
        } catch {
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

    private static func seedPredefinedBreedsIfNeeded(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<DogBreed>()
            let existingBreeds = try context.fetch(descriptor)
            if existingBreeds.isEmpty {
                for name in DogBreed.predefinedBreeds {
                    context.insert(DogBreed(name: name))
                }
                try context.save()
            }
        } catch {
            print("Failed to seed predefined breeds on Mac: \(error)")
        }
    }
}
