import Foundation
import SwiftData

@Model
final class BreedImage {
    var id: UUID
    
    @Attribute(.externalStorage)
    var imageData: Data
    
    @Attribute(.externalStorage)
    var annotatedImageData: Data?
    
    var detectionDate: Date
    var confidence: Double
    var breed: DogBreed?
    
    init(id: UUID = UUID(), imageData: Data, annotatedImageData: Data? = nil, detectionDate: Date = Date(), confidence: Double, breed: DogBreed? = nil) {
        self.id = id
        self.imageData = imageData
        self.annotatedImageData = annotatedImageData
        self.detectionDate = detectionDate
        self.confidence = confidence
        self.breed = breed
    }
}
