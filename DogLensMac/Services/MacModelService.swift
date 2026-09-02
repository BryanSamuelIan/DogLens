import Foundation
import CoreML
import AppKit
import CoreGraphics

@MainActor
class MacModelService {
    static let shared = MacModelService()

    private var model: DogLensImagev2?

    private init() {}

    private func getModel() throws -> DogLensImagev2 {
        if let existing = self.model {
            return existing
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            let loaded = try DogLensImagev2(configuration: config)
            self.model = loaded
            return loaded
        } catch {
            print("Failed to load CoreML model with .cpuAndNeuralEngine, fallback to .cpuOnly: \(error)")
            let cpuConfig = MLModelConfiguration()
            cpuConfig.computeUnits = .cpuOnly
            let loaded = try DogLensImagev2(configuration: cpuConfig)
            self.model = loaded
            return loaded
        }
    }

    func detectDogs(in image: NSImage) async throws -> [DetectionResult] {
        let model = try getModel()

        guard let pixelBuffer = image.pixelBuffer(width: 416, height: 416) else {
            throw NSError(domain: "ImageError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to pixel buffer"])
        }

        let input = DogLensImagev2Input(image: pixelBuffer)
        let output = try await model.prediction(input: input)

        guard let multiArray = output.featureValue(for: "var_1223")?.multiArrayValue else {
            return []
        }

        let imageSize = image.size
        var results: [DetectionResult] = []
        let numAnchors = 3549
        let numClasses = 52

        let strides = multiArray.strides
        guard strides.count >= 3 else { return [] }
        let stride1 = strides[1].intValue
        let stride2 = strides[2].intValue

        let isFloat32 = multiArray.dataType == .float32
        let isDouble  = multiArray.dataType == .double

        let ptr32     = isFloat32 ? multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count) : nil
        let ptrDouble = isDouble  ? multiArray.dataPointer.bindMemory(to: Double.self,   capacity: multiArray.count) : nil
        var readFloat: (Int) -> Float = { index in multiArray[index].floatValue }
        var readCoords: (Int, Int, Int, Int) -> (CGFloat, CGFloat, CGFloat, CGFloat) = { iX, iY, iW, iH in
            (CGFloat(multiArray[iX].floatValue), CGFloat(multiArray[iY].floatValue), CGFloat(multiArray[iW].floatValue), CGFloat(multiArray[iH].floatValue))
        }

        if let p = ptr32 {
            readFloat = { index in p[index] }
            readCoords = { iX, iY, iW, iH in
                (CGFloat(p[iX]), CGFloat(p[iY]), CGFloat(p[iW]), CGFloat(p[iH]))
            }
        } else if let p = ptrDouble {
            readFloat = { index in Float(p[index]) }
            readCoords = { iX, iY, iW, iH in
                (CGFloat(p[iX]), CGFloat(p[iY]), CGFloat(p[iW]), CGFloat(p[iH]))
            }
        }

        #if arch(arm64)
        if multiArray.dataType == .float16 {
            let ptr16 = multiArray.dataPointer.bindMemory(to: Float16.self, capacity: multiArray.count)
            readFloat = { index in Float(ptr16[index]) }
            readCoords = { iX, iY, iW, iH in
                (CGFloat(ptr16[iX]), CGFloat(ptr16[iY]), CGFloat(ptr16[iW]), CGFloat(ptr16[iH]))
            }
        }
        #endif

        for i in 0..<numAnchors {
            var maxConf: Float = 0.0
            var maxClassId = 0

            for c in 0..<numClasses {
                let index = (4 + c) * stride1 + i * stride2
                let conf = readFloat(index)

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

            let (x, y, w, h) = readCoords(iX, iY, iW, iH)

            let scaleX = imageSize.width  / 416.0
            let scaleY = imageSize.height / 416.0

            let rect = CGRect(
                x: (x - w / 2) * scaleX,
                y: (y - h / 2) * scaleY,
                width:  w * scaleX,
                height: h * scaleY
            )

            let breedLabel = maxClassId < DogBreed.predefinedBreeds.count
                ? DogBreed.predefinedBreeds[maxClassId]
                : "Unknown"
            results.append(DetectionResult(label: breedLabel, confidence: maxConf, boundingBox: rect))
        }

        // Non-Maximum Suppression (NMS)
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
    }

    /// Renders bounding box outlines and text labels directly onto an NSImage matching iOS DogLens style
    func renderAnnotatedImage(image: NSImage, detections: [DetectionResult]) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let newImage = NSImage(size: size)
        newImage.lockFocus()

        image.draw(in: NSRect(origin: .zero, size: size))

        let lineWidth = max(2.5, min(8.0, size.width / 180.0))
        let fontSize = max(11.0, min(24.0, size.width / 45.0))
        let font = NSFont.boldSystemFont(ofSize: fontSize)

        for detection in detections {
            let rect = detection.boundingBox

            // Invert Y coordinate for AppKit (bottom-left origin)
            let appKitY = size.height - rect.origin.y - rect.size.height
            let drawRect = NSRect(x: rect.origin.x, y: appKitY, width: rect.size.width, height: rect.size.height)

            // Bounding box outline in orange (matching iOS)
            let boxPath = NSBezierPath(roundedRect: drawRect, xRadius: 4, yRadius: 4)
            boxPath.lineWidth = lineWidth
            NSColor.systemOrange.setStroke()
            boxPath.stroke()

            // Text Label matching iOS style (White text on Orange pill)
            let text = "\(detection.label) \(Int(detection.confidence * 100))%"
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
