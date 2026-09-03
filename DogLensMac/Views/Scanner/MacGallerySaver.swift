//
//  MacGallerySaver.swift
//  DogLensMac
//

import AppKit
import SwiftData

enum MacGallerySaver {
    @MainActor
    static func saveEligibleDetections(
        originalImage: NSImage,
        annotatedImage: NSImage?,
        detections: [DetectionResult],
        modelContext: ModelContext
    ) throws -> [String] {
        guard let origData = originalImage.jpegData else {
            throw NSError(domain: "GallerySaverError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode original image data."])
        }

        let annData = annotatedImage?.jpegData
        let eligible = detections.filter { $0.confidence >= 0.7 }
        guard !eligible.isEmpty else {
            return []
        }

        let descriptor = FetchDescriptor<DogBreed>()
        let allBreeds = try modelContext.fetch(descriptor)
        var savedBreedNames: [String] = []

        for item in eligible {
            let breedName = item.label
            let breed: DogBreed
            if let existing = allBreeds.first(where: { $0.name.caseInsensitiveCompare(breedName) == .orderedSame }) {
                breed = existing
            } else {
                let newBreed = DogBreed(name: breedName)
                modelContext.insert(newBreed)
                breed = newBreed
            }

            let breedImage = BreedImage(
                imageData: origData,
                annotatedImageData: annData,
                isVideo: false,
                detectionDate: Date(),
                confidence: Double(item.confidence),
                breed: breed,
                isSyncedToCloud: false
            )

            modelContext.insert(breedImage)
            breed.images.append(breedImage)
            savedBreedNames.append(breed.name)

            // Automatic 2-way background iCloud sync
            Task {
                await MacCloudKitService.shared.uploadBreedImage(breedImage, breedName: breed.name)
                try? modelContext.save()
            }
        }

        try modelContext.save()
        return savedBreedNames
    }
}
