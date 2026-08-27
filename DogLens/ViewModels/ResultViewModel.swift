// ResultViewModel.swift
import SwiftUI
import SwiftData
import Photos
import Combine

@MainActor
final class ResultViewModel: ObservableObject {
    // MARK: - Input
    let originalImage: UIImage
    let detectionResults: [DetectionResult]

    // MARK: - Published UI State
    @Published var showOriginal = false
    @Published var annotatedImage: UIImage?
    @Published var showingSaveAlert = false
    @Published var saveMessage = ""

    // MARK: - Dependencies (injected from View)
    var modelContext: ModelContext?
    var breeds: [DogBreed] = []

    init(image: UIImage, results: [DetectionResult]) {
        self.originalImage = image
        self.detectionResults = results
        self.annotatedImage = Self.createAnnotatedImage(from: image, with: results)
    }

    // MARK: - Computed Image
    var displayImage: UIImage {
        showOriginal ? originalImage : (annotatedImage ?? originalImage)
    }

    // MARK: - Image Creation
    private static func createAnnotatedImage(from image: UIImage, with results: [DetectionResult]) -> UIImage? {
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
        image.draw(at: .zero)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        let lineWidth = max(4.0, size.width / 150.0)
        ctx.setLineWidth(lineWidth)
        ctx.setStrokeColor(UIColor.orange.cgColor)
        for result in results {
            ctx.stroke(result.boundingBox)
            let text = result.label
            let fontSize = max(18.0, size.width / 40.0)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.orange
            ]
            let textSize = text.size(withAttributes: attrs)
            let rect = CGRect(
                x: result.boundingBox.minX,
                y: max(0, result.boundingBox.minY - textSize.height),
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: rect, withAttributes: attrs)
        }
        let annotated = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return annotated
    }

    // MARK: - Save Actions
    func saveToPhotos() {
        let imageToSave = annotatedImage ?? originalImage
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                if status == .authorized || status == .limited {
                    UIImageWriteToSavedPhotosAlbum(imageToSave, nil, nil, nil)
                    self.saveMessage = "Image saved to your Photos."
                } else {
                    self.saveMessage = "Please grant Photo Library permission in Settings."
                }
                self.showingSaveAlert = true
            }
        }
    }

    func saveToBreedGallery() {
        guard let ctx = modelContext,
              let originalData = originalImage.jpegData(compressionQuality: 0.8) else {
            saveMessage = "Failed to encode image."
            showingSaveAlert = true
            return
        }
        let annotatedData = annotatedImage?.jpegData(compressionQuality: 0.8)
        
        let validResults = detectionResults.filter { $0.confidence >= 0.7 }
        let uniqueBreedNames = Array(Set(validResults.map { $0.label }))
        var savedCount = 0
        
        for breedName in uniqueBreedNames {
            if let breed = breeds.first(where: { $0.name == breedName }) {
                let maxConf = validResults
                    .filter { $0.label == breedName }
                    .map { Double($0.confidence) }
                    .max() ?? 0.0
                
                let breedImage = BreedImage(
                    imageData: originalData,
                    annotatedImageData: annotatedData,
                    isVideo: false,
                    confidence: maxConf
                )
                breed.images.append(breedImage)
                savedCount += 1
            }
        }
        do {
            try ctx.save()
            saveMessage = savedCount > 0
                ? "Saved to \(savedCount) breed(s) in Gallery."
                : "No matching breeds found in gallery."
        } catch {
            saveMessage = "Failed to save to gallery."
        }
        showingSaveAlert = true
    }
}
