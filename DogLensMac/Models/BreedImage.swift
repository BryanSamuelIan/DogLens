import Foundation
import SwiftData

@Model
final class BreedImage {
    var id: UUID
    
    @Attribute(.externalStorage)
    var imageData: Data
    
    @Attribute(.externalStorage)
    var annotatedImageData: Data?
    
    @Attribute(.externalStorage)
    var videoData: Data?
    
    @Attribute(.externalStorage)
    var annotatedVideoData: Data?
    
    var isVideo: Bool = false
    
    var detectionDate: Date
    var confidence: Double
    var breed: DogBreed?
    
    init(id: UUID = UUID(),
         imageData: Data,
         annotatedImageData: Data? = nil,
         videoData: Data? = nil,
         annotatedVideoData: Data? = nil,
         isVideo: Bool = false,
         detectionDate: Date = Date(),
         confidence: Double,
         breed: DogBreed? = nil) {
        self.id = id
        self.imageData = imageData
        self.annotatedImageData = annotatedImageData
        self.videoData = videoData
        self.annotatedVideoData = annotatedVideoData
        self.isVideo = isVideo
        self.detectionDate = detectionDate
        self.confidence = confidence
        self.breed = breed
    }
}
