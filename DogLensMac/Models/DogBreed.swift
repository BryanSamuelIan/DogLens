import Foundation
import SwiftData

@Model
final class DogBreed {
    var id: UUID
    var name: String
    
    @Relationship(deleteRule: .cascade, inverse: \BreedImage.breed)
    var images: [BreedImage] = []
    
    var imageCount: Int {
        images.count
    }
    
    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

extension DogBreed {
    static let predefinedBreeds: [String] = [
        "Afghan Hound", "Basset", "Beagle", "Bernese Mountain Dog",
        "Bloodhound", "Border Collie", "Boston Terrier", "Boxer",
        "Bulldog", "Chihuahua", "Chow", "Cocker Spaniel",
        "Doberman", "French Bulldog", "German Shepherd", "Golden Retriever",
        "Great Dane", "Labrador Retriever", "Maltese Dog", "Papillon",
        "Pekinese", "Pomeranian", "Poodle", "Pug",
        "Rottweiler", "Saint Bernard", "Samoyed", "Siberian Husky",
        "Staffordshire Bullterrier", "Tibetan Mastiff", "Yorkshire Terrier"
    ]
}
