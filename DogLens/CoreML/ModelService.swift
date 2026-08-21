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
        
        var results: [DetectionResult] = []
        
        let numAnchors = 3549
        let numClasses = 52
        
        for i in 0..<numAnchors {
            var maxConf: Float = 0.0
            var maxClassId: Int = 0
            
            // Find max class confidence
            for c in 0..<numClasses {
                let conf = multiArray[[0, NSNumber(value: 4 + c), NSNumber(value: i)]].floatValue
                if conf > maxConf {
                    maxConf = conf
                    maxClassId = c
                }
            }
            
            // YOLO threshold
            if maxConf > 0.5 {
                let x = multiArray[[0, 0, NSNumber(value: i)]].cgFloatValue
                let y = multiArray[[0, 1, NSNumber(value: i)]].cgFloatValue
                let w = multiArray[[0, 2, NSNumber(value: i)]].cgFloatValue
                let h = multiArray[[0, 3, NSNumber(value: i)]].cgFloatValue
                
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
    }
}

extension NSNumber {
    var cgFloatValue: CGFloat {
        return CGFloat(self.doubleValue)
    }
}
