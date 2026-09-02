import Foundation
import CoreML
import AppKit
import CoreGraphics

@MainActor
class MacModelService {
    static let shared = MacModelService()

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

    func detectDogs(in image: NSImage) async throws -> [DetectionResult] {
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
        let imageSize = image.size

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

            results.append(DetectionResult(label: breedLabel, confidence: maxConf, boundingBox: rect))
        }

        results.sort { $0.confidence > $1.confidence }
        return results
    }

    /// Renders bounding box outlines and text labels directly onto an NSImage matching iOS DogLens style
    func renderAnnotatedImage(image: NSImage, detections: [DetectionResult]) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let newImage = NSImage(size: size)
        newImage.lockFocus()

        image.draw(in: NSRect(origin: .zero, size: size))

        for detection in detections {
            let box = detection.boundingBox

            // Convert Cocoa bottom-left coordinates to top-left or vice-versa
            let drawRect = NSRect(
                x: box.origin.x,
                y: size.height - box.origin.y - box.size.height,
                width: box.size.width,
                height: box.size.height
            )

            // Bounding box border
            let path = NSBezierPath(roundedRect: drawRect, xRadius: 6, yRadius: 6)
            path.lineWidth = 3.0
            NSColor.systemOrange.setStroke()
            path.stroke()

            // Label pill
            let text = "\(detection.label) \(Int(detection.confidence * 100))%"
            let font = NSFont.systemFont(ofSize: 13, weight: .bold)
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]
            let textSize = (text as NSString).size(withAttributes: textAttributes)
            let pillPaddingH: CGFloat = 6.0
            let pillPaddingV: CGFloat = 3.0
            let pillWidth = textSize.width + (pillPaddingH * 2)
            let pillHeight = textSize.height + (pillPaddingV * 2)

            // Position pill above box (or inside top if near image edge)
            var pillY = drawRect.maxY
            if pillY + pillHeight > size.height {
                pillY = drawRect.maxY - pillHeight
            }
            let pillRect = NSRect(
                x: drawRect.minX,
                y: pillY,
                width: min(pillWidth, size.width - drawRect.minX),
                height: pillHeight
            )

            // Background pill fill
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)
            NSColor.systemOrange.setFill()
            pillPath.fill()

            // Draw label text
            let textPoint = NSPoint(x: pillRect.minX + pillPaddingH, y: pillRect.minY + pillPaddingV)
            (text as NSString).draw(at: textPoint, withAttributes: textAttributes)
        }

        newImage.unlockFocus()
        return newImage
    }
}
