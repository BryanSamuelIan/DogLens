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
