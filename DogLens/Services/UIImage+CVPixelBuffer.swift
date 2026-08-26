import UIKit
import CoreGraphics
import VideoToolbox
import CoreImage
import ImageIO

extension UIImage {
    // MARK: - Original UIKit version (main-thread only)
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
        UIGraphicsPushContext(context)
        self.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        return buffer
    }

    // MARK: - Thread-safe version using CoreImage & EXIF orientation (off main thread)
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    func pixelBufferOffMain(width: Int, height: Int) -> CVPixelBuffer? {
        guard let cgImage = self.cgImage else { return nil }

        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attrs, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }

        let exifOrientation = CGImagePropertyOrientation(self.imageOrientation)
        let ciImage = CIImage(cgImage: cgImage).oriented(exifOrientation)

        let targetWidth = CGFloat(width)
        let targetHeight = CGFloat(height)

        let scaleX = targetWidth / ciImage.extent.width
        let scaleY = targetHeight / ciImage.extent.height

        let transform = CGAffineTransform(translationX: -ciImage.extent.origin.x, y: -ciImage.extent.origin.y)
            .scaledBy(x: scaleX, y: scaleY)

        let finalImage = ciImage.transformed(by: transform)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        UIImage.sharedCIContext.render(finalImage, to: buffer, bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight), colorSpace: colorSpace)

        return buffer
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

