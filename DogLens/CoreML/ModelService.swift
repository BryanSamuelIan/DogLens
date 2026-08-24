import Foundation
import CoreML
import UIKit
import CoreGraphics

class ModelService {
    static let shared = ModelService()
    
    // CoreML model instance
    private var model: DogLensImage?
    
    private init() {
        do {
            let config = MLModelConfiguration()
            model = try DogLensImage(configuration: config)
        } catch {
            print("Failed to load CoreML model: \(error)")
        }
    }
    
    func detectDogs(in image: UIImage) async throws -> [DetectionResult] {
        guard let model = model else {
            throw NSError(domain: "ModelError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        
        // Convert UIImage to CVPixelBuffer (assuming 416x416 input size, adjust if needed)
        // Usually, the generated DogLensImage class has an init that takes CGImage,
        // let's try using the pixel buffer method.
        guard let pixelBuffer = image.pixelBuffer(width: 416, height: 416) else {
            throw NSError(domain: "ImageError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image"])
        }
        let input = DogLensImageInput(image: pixelBuffer)
        let output = try await model.prediction(input: input)
        
        // Output shape [1, 56, 3549]
        // 4 bounding box coordinates (cx, cy, w, h) + 52 classes
        // 3549 anchors
        guard let multiArray = output.featureValue(for: "var_1223")?.multiArrayValue else {
            return []
        }
        // Run heavy post-processing in a detached task to avoid blocking the main thread
        return await Task.detached(priority: .userInitiated) {
            var results: [DetectionResult] = []
            
            let numAnchors = 3549
            let numClasses = 52
            
            let strides = multiArray.strides
            let stride1 = strides[1].intValue
            let stride2 = strides[2].intValue
            
            let isFloat32 = multiArray.dataType == .float32
            let isFloat16 = multiArray.dataType == .float16
            let isDouble = multiArray.dataType == .double
            
            let ptr32 = isFloat32 ? multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count) : nil
            let ptr16 = isFloat16 ? multiArray.dataPointer.bindMemory(to: Float16.self, capacity: multiArray.count) : nil
            let ptrDouble = isDouble ? multiArray.dataPointer.bindMemory(to: Double.self, capacity: multiArray.count) : nil
            
            for i in 0..<numAnchors {
                var maxConf: Float = 0.0
                var maxClassId: Int = 0
                
                // Find max class confidence
                for c in 0..<numClasses {
                    let index = (4 + c) * stride1 + i * stride2
                    let conf: Float
                    if let p = ptr32 { conf = p[index] }
                    else if let p = ptr16 { conf = Float(p[index]) }
                    else if let p = ptrDouble { conf = Float(p[index]) }
                    else { conf = multiArray[index].floatValue }
                    
                    if conf > maxConf {
                        maxConf = conf
                        maxClassId = c
                    }
                }
                
                // YOLO threshold
                if maxConf > 0.5 {
                    let iX = 0 * stride1 + i * stride2
                    let iY = 1 * stride1 + i * stride2
                    let iW = 2 * stride1 + i * stride2
                    let iH = 3 * stride1 + i * stride2
                    
                    let x: CGFloat
                    let y: CGFloat
                    let w: CGFloat
                    let h: CGFloat
                    
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
                    
                    // Usually coordinates are normalized, if not they are in 416x416 space
                    // Let's assume normalized 0-1 based on the input size 416. 
                    // But typically YOLOv8 outputs are in pixel coordinates of the model input (416x416).
                    // Let's scale back to original image size:
                    let scaleX = image.size.width / 416.0
                    let scaleY = image.size.height / 416.0
                    
                    let rectX = (x - w/2) * scaleX
                    let rectY = (y - h/2) * scaleY
                    let rectW = w * scaleX
                    let rectH = h * scaleY
                    
                    let rect = CGRect(x: rectX, y: rectY, width: rectW, height: rectH)
                    
                    let breedLabel = maxClassId < DogBreed.predefinedBreeds.count ? DogBreed.predefinedBreeds[maxClassId] : "Unknown"
                    
                    let result = DetectionResult(boundingBox: rect, label: breedLabel, confidence: maxConf)
                    results.append(result)
                }
            }
            
            // Non-Maximum Suppression (NMS) - simple implementation
            results.sort { $0.confidence > $1.confidence }
            var nmsResults: [DetectionResult] = []
            for result in results {
                var keep = true
                for kept in nmsResults {
                    let intersection = result.boundingBox.intersection(kept.boundingBox)
                    let unionArea = result.boundingBox.width * result.boundingBox.height + kept.boundingBox.width * kept.boundingBox.height - (intersection.width * intersection.height)
                    let iou = (intersection.width * intersection.height) / unionArea
                    if iou > 0.45 {
                        keep = false
                        break
                    }
                }
                if keep {
                    nmsResults.append(result)
                }
            }
            
            return nmsResults
        }.value
    }
}

extension NSNumber {
    var cgFloatValue: CGFloat {
        return CGFloat(self.doubleValue)
    }
}
