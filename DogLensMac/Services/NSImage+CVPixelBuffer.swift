import AppKit
import CoreGraphics
import CoreImage
import VideoToolbox
import ImageIO

public struct MacLetterboxInfo {
    public let scale: CGFloat
    public let padX: CGFloat
    public let padY: CGFloat
    public let targetSize: CGFloat

    public init(scale: CGFloat, padX: CGFloat, padY: CGFloat, targetSize: CGFloat) {
        self.scale = scale
        self.padX = padX
        self.padY = padY
        self.targetSize = targetSize
    }
}

extension NSImage {
    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: self.size)
        if let cg = self.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cg
        }
        if let tiffData = self.tiffRepresentation,
           let source = CGImageSourceCreateWithData(tiffData as CFData, nil) {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return nil
    }

    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Converts NSImage to 640x640 CVPixelBuffer with letterboxing matching YOLO preprocessing
    func letterboxPixelBuffer(targetSize: Int = 640) -> (pixelBuffer: CVPixelBuffer, letterboxInfo: MacLetterboxInfo)? {
        guard let cgImage = self.cgImage else { return nil }

        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, targetSize, targetSize,
                                  kCVPixelFormatType_32BGRA, attrs, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        let origWidth = ciImage.extent.width
        let origHeight = ciImage.extent.height
        guard origWidth > 0, origHeight > 0 else { return nil }

        let targetF = CGFloat(targetSize)
        let scale = min(targetF / origWidth, targetF / origHeight)
        let scaledWidth = origWidth * scale
        let scaledHeight = origHeight * scale
        let padX = (targetF - scaledWidth) / 2.0
        let padY = (targetF - scaledHeight) / 2.0

        // Neutral gray background (114/255) matching YOLO letterbox
        let grayColor = CIColor(red: 114.0 / 255.0, green: 114.0 / 255.0, blue: 114.0 / 255.0)
        let background = CIImage(color: grayColor).cropped(to: CGRect(x: 0, y: 0, width: targetF, height: targetF))

        let transform = CGAffineTransform(translationX: -ciImage.extent.origin.x, y: -ciImage.extent.origin.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: padX / scale, y: padY / scale)

        let transformedImage = ciImage.transformed(by: transform)
        let finalImage = transformedImage.composited(over: background)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        NSImage.sharedCIContext.render(finalImage, to: buffer, bounds: CGRect(x: 0, y: 0, width: targetF, height: targetF), colorSpace: colorSpace)

        let info = MacLetterboxInfo(scale: scale, padX: padX, padY: padY, targetSize: targetF)
        return (buffer, info)
    }

    func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        guard let result = letterboxPixelBuffer(targetSize: width) else { return nil }
        return result.pixelBuffer
    }

    /// Converts NSImage to JPEG Data
    var jpegData: Data? {
        guard let tiffRepresentation = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
