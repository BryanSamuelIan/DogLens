import UIKit
import CoreGraphics
import VideoToolbox
import CoreImage
import ImageIO

public struct LetterboxInfo {
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

extension UIImage {
    // MARK: - Thread-safe version using CoreImage & EXIF orientation (off main thread)
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Converts UIImage to a 640x640 CVPixelBuffer with proper letterboxing (aspect-ratio preservation + padding)
    /// to match Ultralytics YOLO inference preprocessing.
    func letterboxPixelBuffer(targetSize: Int = 640) -> (pixelBuffer: CVPixelBuffer, letterboxInfo: LetterboxInfo)? {
        guard let cgImage = self.cgImage else { return nil }

        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, targetSize, targetSize,
                                  kCVPixelFormatType_32BGRA, attrs, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }

        let exifOrientation = CGImagePropertyOrientation(self.imageOrientation)
        let ciImage = CIImage(cgImage: cgImage).oriented(exifOrientation)

        let origWidth = ciImage.extent.width
        let origHeight = ciImage.extent.height
        guard origWidth > 0, origHeight > 0 else { return nil }

        let targetF = CGFloat(targetSize)
        let scale = min(targetF / origWidth, targetF / origHeight)
        let scaledWidth = origWidth * scale
        let scaledHeight = origHeight * scale
        let padX = (targetF - scaledWidth) / 2.0
        let padY = (targetF - scaledHeight) / 2.0

        // Neutral gray background (114/255) matching YOLO standard letterbox
        let grayColor = CIColor(red: 114.0 / 255.0, green: 114.0 / 255.0, blue: 114.0 / 255.0)
        let background = CIImage(color: grayColor).cropped(to: CGRect(x: 0, y: 0, width: targetF, height: targetF))

        let transform = CGAffineTransform(translationX: -ciImage.extent.origin.x, y: -ciImage.extent.origin.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: padX / scale, y: padY / scale)

        let transformedImage = ciImage.transformed(by: transform)
        let finalImage = transformedImage.composited(over: background)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        UIImage.sharedCIContext.render(finalImage, to: buffer, bounds: CGRect(x: 0, y: 0, width: targetF, height: targetF), colorSpace: colorSpace)

        let info = LetterboxInfo(scale: scale, padX: padX, padY: padY, targetSize: targetF)
        return (buffer, info)
    }

    func pixelBufferOffMain(width: Int, height: Int) -> CVPixelBuffer? {
        guard let result = letterboxPixelBuffer(targetSize: width) else { return nil }
        return result.pixelBuffer
    }

    // MARK: - UIKit version for video encoding
    func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attrs, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: pixelData, width: width, height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)

        UIGraphicsPushContext(context)
        self.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        return buffer
    }

    func toPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        pixelBuffer(width: width, height: height)
    }
}

extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .left: self = .left
        case .rightMirrored: self = .rightMirrored
        case .right: self = .right
        @unknown default: self = .up
        }
    }
}
