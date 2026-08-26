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
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Seed data if empty
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
    }
}
