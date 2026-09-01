//
//  DogLensApp.swift
//  DogLens
//
//  Created by Bryan Samuel on 21/08/26.
//

import SwiftUI
import SwiftData

@main
struct DogLensApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DogBreed.self,
            BreedImage.self
        ])
        
        // Explicitly set cloudKitDatabase to .none so SwiftData uses clean local storage,
        // while our dedicated CloudKitService manages media assets and iCloud synchronization.
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            seedBreedsIfNeeded(container: container)
            return container
        } catch {
            print("Failed to load ModelContainer with default config: \(error). Attempting fallback...")
            
            // Fallback recovery: attempt in-memory or rebuilt configuration if SQLite store was mismatched
            do {
                let fallbackConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
                )
                let fallbackContainer = try ModelContainer(for: schema, configurations: [fallbackConfig])
                seedBreedsIfNeeded(container: fallbackContainer)
                return fallbackContainer
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
    
    // MARK: - Database Seeding Helper
    
    private static func seedBreedsIfNeeded(container: ModelContainer) {
        Task { @MainActor in
            let context = container.mainContext
            let fetchDescriptor = FetchDescriptor<DogBreed>()
            do {
                let existingBreeds = try context.fetch(fetchDescriptor)
                if existingBreeds.isEmpty {
                    for breedName in DogBreed.predefinedBreeds {
                        let newBreed = DogBreed(name: breedName)
                        context.insert(newBreed)
                    }
                    try context.save()
                }
            } catch {
                print("Error seeding database: \(error)")
            }
        }
    }
}
