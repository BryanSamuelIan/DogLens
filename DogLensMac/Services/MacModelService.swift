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
            config.computeUnits = .all
            let loaded = try DogLensImagev2(configuration: config)
            self.model = loaded
            return loaded
        } catch {
            print("Failed to load CoreML model with .all compute units, fallback to .cpuOnly: \(error)")
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

        return await Task.detached(priority: .userInitiated) {
            var results: [DetectionResult] = []
            let numAnchors = 3549
            let numClasses = 52

            let strides = multiArray.strides
            let stride1 = strides[1].intValue
            let stride2 = strides[2].intValue

            let isFloat32 = multiArray.dataType == .float32
            let isDouble  = multiArray.dataType == .double
            let ptr32     = isFloat32 ? multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count) : nil
            let ptrDouble = isDouble  ? multiArray.dataPointer.bindMemory(to: Double.self,   capacity: multiArray.count) : nil

            for i in 0..<numAnchors {
                var maxConf: Float = 0.0
                var maxClassId = 0

                for c in 0..<numClasses {
                    let index = (4 + c) * stride1 + i * stride2
                    let conf: Float
                    if let p = ptr32 {
                        conf = p[index]
                    } else if let p = ptrDouble {
                        conf = Float(p[index])
                    } else {
                        conf = multiArray[index].floatValue
                    }

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

                let x: CGFloat
                let y: CGFloat
                let w: CGFloat
                let h: CGFloat

                if let p = ptr32 {
                    x = CGFloat(p[iX]); y = CGFloat(p[iY]); w = CGFloat(p[iW]); h = CGFloat(p[iH])
                } else if let p = ptrDouble {
                    x = CGFloat(p[iX]); y = CGFloat(p[iY]); w = CGFloat(p[iW]); h = CGFloat(p[iH])
                } else {
                    x = CGFloat(multiArray[iX].floatValue); y = CGFloat(multiArray[iY].floatValue)
                    w = CGFloat(multiArray[iW].floatValue); h = CGFloat(multiArray[iH].floatValue)
                }

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
        }.value
    }

    /// Renders bounding box outlines and text labels directly onto an NSImage
    func renderAnnotatedImage(image: NSImage, detections: [DetectionResult]) -> NSImage {
        let newImage = NSImage(size: image.size)
        newImage.lockFocus()

        image.draw(in: NSRect(origin: .zero, size: image.size))

        for detection in detections {
            let rect = detection.boundingBox

            // Invert Y coordinate for macOS AppKit top-left vs bottom-left coordinates if necessary
            // Note: If bounding box Y is from top-left, AppKit coordinates have origin at bottom-left:
            let appKitY = image.size.height - rect.origin.y - rect.size.height
            let drawRect = NSRect(x: rect.origin.x, y: appKitY, width: rect.size.width, height: rect.size.height)

            // Bounding Box outline
            let path = NSBezierPath(roundedRect: drawRect, xRadius: 6, yRadius: 6)
            path.lineWidth = max(3.0, image.size.width / 300.0)
            NSColor.systemYellow.setStroke()
            path.stroke()

            // Label pill
            let text = "\(detection.label) \(Int(detection.confidence * 100))%"
            let font = NSFont.boldSystemFont(ofSize: max(14.0, image.size.width / 40.0))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let textBackgroundRect = NSRect(
                x: drawRect.origin.x,
                y: min(image.size.height - textSize.height - 4, drawRect.origin.y + drawRect.size.height),
                width: textSize.width + 12,
                height: textSize.height + 6
            )

            let pillPath = NSBezierPath(roundedRect: textBackgroundRect, xRadius: 4, yRadius: 4)
            NSColor.systemYellow.setFill()
            pillPath.fill()

            (text as NSString).draw(
                at: NSPoint(x: textBackgroundRect.origin.x + 6, y: textBackgroundRect.origin.y + 3),
                withAttributes: attributes
            )
        }

        newImage.unlockFocus()
        return newImage
    }
}
