// BreedGalleryViewModel.swift
import SwiftUI
import Combine

@MainActor
final class BreedGalleryViewModel: ObservableObject {
    @Published var searchText = ""

    func filteredBreeds(from breeds: [DogBreed]) -> [DogBreed] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return breeds
        }
        return breeds.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}
