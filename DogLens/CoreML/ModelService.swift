import Foundation
import CoreML
import UIKit
import CoreGraphics

class ModelService {
    static let shared = ModelService()

    private var model: DogLensImagev2?
    private var modelTask: Task<DogLensImagev2, Error>?
    private let modelLock = NSLock()

    private init() {
        _ = getOrStartModelTask()
    }

    private func getOrStartModelTask() -> Task<DogLensImagev2, Error> {
        modelLock.lock()
        defer { modelLock.unlock() }

        if let existingTask = modelTask {
            return existingTask
        }

        let task = Task.detached(priority: .userInitiated) { () -> DogLensImagev2 in
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .cpuAndNeuralEngine
                return try DogLensImagev2(configuration: config)
            } catch {
                print("Failed to load CoreML model with .cpuAndNeuralEngine, trying .cpuOnly: \(error)")
                let cpuConfig = MLModelConfiguration()
                cpuConfig.computeUnits = .cpuOnly
                return try DogLensImagev2(configuration: cpuConfig)
            }
        }

        modelTask = task
        return task
    }

    private func getModel() async throws -> DogLensImagev2 {
        modelLock.lock()
        if let model = self.model {
            modelLock.unlock()
            return model
        }
        modelLock.unlock()

        let task = getOrStartModelTask()

        do {
            let loadedModel = try await task.value
            modelLock.lock()
            self.model = loadedModel
            modelLock.unlock()
            return loadedModel
        } catch {
            modelLock.lock()
            self.modelTask = nil
            modelLock.unlock()
            throw NSError(domain: "ModelError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load CoreML model: \(error.localizedDescription)"])
        }
    }

    /// Run inference entirely off the main thread so CoreML can freely
    /// dispatch without deadlocking on real devices.
    func detectDogs(in image: UIImage) async throws -> [DetectionResult] {
        let model = try await getModel()

        return try await Task.detached(priority: .userInitiated) {
            // Use the thread-safe CoreGraphics-only pixel buffer conversion
            guard let pixelBuffer = image.pixelBufferOffMain(width: 416, height: 416) else {
                throw NSError(domain: "ImageError", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to pixel buffer"])
            }

            let input = DogLensImagev2Input(image: pixelBuffer)
            let output = try model.prediction(input: input)

            // Output shape: [1, 56, 3549]
            // Channels 0-3: cx, cy, w, h  |  Channels 4-55: class confidences (52 classes)
            guard let multiArray = output.featureValue(for: "var_1223")?.multiArrayValue else {
                return []
            }

            var results: [DetectionResult] = []
            let numAnchors = 3549
            let numClasses = 52

            let strides = multiArray.strides
            let stride1 = strides[1].intValue
            let stride2 = strides[2].intValue

            let isFloat32 = multiArray.dataType == .float32
            let isFloat16 = multiArray.dataType == .float16
            let isDouble  = multiArray.dataType == .double

            let ptr32    = isFloat32 ? multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count) : nil
            let ptr16    = isFloat16 ? multiArray.dataPointer.bindMemory(to: Float16.self,  capacity: multiArray.count) : nil
            let ptrDouble = isDouble  ? multiArray.dataPointer.bindMemory(to: Double.self,   capacity: multiArray.count) : nil

            for i in 0..<numAnchors {
                var maxConf: Float = 0.0
                var maxClassId = 0

                for c in 0..<numClasses {
                    let index = (4 + c) * stride1 + i * stride2
                    let conf: Float
                    if let p = ptr32        { conf = p[index] }
                    else if let p = ptr16   { conf = Float(p[index]) }
                    else if let p = ptrDouble { conf = Float(p[index]) }
                    else                    { conf = multiArray[index].floatValue }

                    if conf > maxConf {
                        maxConf = conf
                        maxClassId = c
                    }
                }

                guard maxConf > 0.25 else { continue }

                let iX = 0 * stride1 + i * stride2
                let iY = 1 * stride1 + i * stride2
                let iW = 2 * stride1 + i * stride2
                let iH = 3 * stride1 + i * stride2

                let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat
                if let p = ptr32 {
                    x = CGFloat(p[iX]); y = CGFloat(p[iY]); w = CGFloat(p[iW]); h = CGFloat(p[iH])
                } else if let p = ptr16 {
                    x = CGFloat(p[iX]); y = CGFloat(p[iY]); w = CGFloat(p[iW]); h = CGFloat(p[iH])
                } else if let p = ptrDouble {
                    x = CGFloat(p[iX]); y = CGFloat(p[iY]); w = CGFloat(p[iW]); h = CGFloat(p[iH])
                } else {
                    x = CGFloat(multiArray[iX].floatValue); y = CGFloat(multiArray[iY].floatValue)
                    w = CGFloat(multiArray[iW].floatValue); h = CGFloat(multiArray[iH].floatValue)
                }

                // YOLOv8 outputs are in the 416×416 model input space — scale to original image
                let scaleX = image.size.width  / 416.0
                let scaleY = image.size.height / 416.0

                let rect = CGRect(
                    x: (x - w / 2) * scaleX,
                    y: (y - h / 2) * scaleY,
                    width:  w * scaleX,
                    height: h * scaleY
                )

                let breedLabel = maxClassId < DogBreed.predefinedBreeds.count
                    ? DogBreed.predefinedBreeds[maxClassId]
                    : "Unknown"
                results.append(DetectionResult(boundingBox: rect, label: breedLabel, confidence: maxConf))
            }

            // Non-Maximum Suppression
            results.sort { $0.confidence > $1.confidence }
            var nmsResults: [DetectionResult] = []
            for result in results {
                var keep = true
                for kept in nmsResults {
                    let inter = result.boundingBox.intersection(kept.boundingBox)
                    if !inter.isNull && !inter.isEmpty {
                        let interArea = inter.width * inter.height
                        let area1 = result.boundingBox.width * result.boundingBox.height
                        let area2 = kept.boundingBox.width * kept.boundingBox.height
                        let unionArea = area1 + area2 - interArea
                        if unionArea > 0 {
                            let iou = interArea / unionArea
                            if iou > 0.45 {
                                keep = false
                                break
                            }
                        }
                    }
                }
                if keep { nmsResults.append(result) }
            }

            return nmsResults
        }.value
    }
}
