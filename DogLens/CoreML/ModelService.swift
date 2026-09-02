import Foundation
import CoreML
import UIKit
import CoreGraphics

@MainActor
class ModelService {
    static let shared = ModelService()

    private var model: DogBreedYOLO11s?

    private init() {}

    private func getModel() throws -> DogBreedYOLO11s {
        if let existing = self.model {
            return existing
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let loaded = try DogBreedYOLO11s(configuration: config)
            self.model = loaded
            return loaded
        } catch {
            print("Failed to load DogBreedYOLO11s with default compute units, trying .cpuOnly: \(error)")
            let cpuConfig = MLModelConfiguration()
            cpuConfig.computeUnits = .cpuOnly
            let loaded = try DogBreedYOLO11s(configuration: cpuConfig)
            self.model = loaded
            return loaded
        }
    }

    /// Run inference with prediction on MainActor and processing off the main thread.
    func detectDogs(in image: UIImage) async throws -> [DetectionResult] {
        let model = try getModel()

        guard let (pixelBuffer, letterboxInfo) = image.letterboxPixelBuffer(targetSize: 640) else {
            throw NSError(domain: "ImageError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to letterbox pixel buffer"])
        }

        let input = DogBreedYOLO11sInput(
            image: pixelBuffer,
            iouThreshold: 0.45,
            confidenceThreshold: 0.25
        )
        let output = try await model.prediction(input: input)

        let coordinates = output.coordinates
        let confidence = output.confidence
        let imageSize = image.size

        return await Task.detached(priority: .userInitiated) {
            let numDetections = coordinates.shape.first?.intValue ?? 0
            guard numDetections > 0 else { return [] }

            let coordStrides = coordinates.strides
            let confStrides = confidence.strides
            guard coordStrides.count >= 2, confStrides.count >= 2 else { return [] }

            let coordStride0 = coordStrides[0].intValue
            let coordStride1 = coordStrides[1].intValue
            let confStride0 = confStrides[0].intValue
            let confStride1 = confStrides[1].intValue

            let numClasses = min(confidence.shape.last?.intValue ?? 52, DogBreed.predefinedBreeds.count)

            let isFloat32 = confidence.dataType == .float32
            let isDouble  = confidence.dataType == .double

            let ptr32     = isFloat32 ? confidence.dataPointer.bindMemory(to: Float32.self, capacity: confidence.count) : nil
            let ptrDouble = isDouble  ? confidence.dataPointer.bindMemory(to: Double.self,   capacity: confidence.count) : nil

            var readConf: (Int, Int) -> Float = { detIdx, classIdx in
                confidence[detIdx * confStride0 + classIdx * confStride1].floatValue
            }

            if let p = ptr32 {
                readConf = { detIdx, classIdx in p[detIdx * confStride0 + classIdx * confStride1] }
            } else if let p = ptrDouble {
                readConf = { detIdx, classIdx in Float(p[detIdx * confStride0 + classIdx * confStride1]) }
            }

            #if arch(arm64)
            if confidence.dataType == .float16 {
                let ptr16 = confidence.dataPointer.bindMemory(to: Float16.self, capacity: confidence.count)
                readConf = { detIdx, classIdx in Float(ptr16[detIdx * confStride0 + classIdx * confStride1]) }
            }
            #endif

            var results: [DetectionResult] = []

            for i in 0..<numDetections {
                var maxConf: Float = 0.0
                var maxClassId = 0

                for c in 0..<numClasses {
                    let conf = readConf(i, c)
                    if conf > maxConf {
                        maxConf = conf
                        maxClassId = c
                    }
                }

                guard maxConf >= 0.25 else { continue }

                let normCX = CGFloat(coordinates[i * coordStride0 + 0 * coordStride1].floatValue)
                let normCY = CGFloat(coordinates[i * coordStride0 + 1 * coordStride1].floatValue)
                let normW  = CGFloat(coordinates[i * coordStride0 + 2 * coordStride1].floatValue)
                let normH  = CGFloat(coordinates[i * coordStride0 + 3 * coordStride1].floatValue)

                // Convert from normalized 640x640 letterbox coordinates back to original image space
                let canvasCX = normCX * letterboxInfo.targetSize
                let canvasCY = normCY * letterboxInfo.targetSize
                let canvasW  = normW  * letterboxInfo.targetSize
                let canvasH  = normH  * letterboxInfo.targetSize

                let origCenterX = (canvasCX - letterboxInfo.padX) / letterboxInfo.scale
                let origCenterY = (canvasCY - letterboxInfo.padY) / letterboxInfo.scale
                let origW = canvasW / letterboxInfo.scale
                let origH = canvasH / letterboxInfo.scale

                let rect = CGRect(
                    x: max(0, origCenterX - origW / 2.0),
                    y: max(0, origCenterY - origH / 2.0),
                    width: min(imageSize.width, origW),
                    height: min(imageSize.height, origH)
                )

                let breedLabel = maxClassId < DogBreed.predefinedBreeds.count
                    ? DogBreed.predefinedBreeds[maxClassId]
                    : "Unknown"

                results.append(DetectionResult(boundingBox: rect, label: breedLabel, confidence: maxConf))
            }

            results.sort { $0.confidence > $1.confidence }
            return results
        }.value
    }
}
