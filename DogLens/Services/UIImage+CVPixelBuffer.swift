import UIKit
import CoreGraphics
import VideoToolbox

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

    // MARK: - Thread-safe version using CoreGraphics only (no UIKit / no main thread required)
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

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: pixelData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else { return nil }

        let targetWidth = CGFloat(width)
        let targetHeight = CGFloat(height)

        context.saveGState()

        switch self.imageOrientation {
        case .down:
            context.translateBy(x: targetWidth, y: targetHeight)
            context.rotate(by: .pi)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        case .left:
            context.translateBy(x: 0, y: targetHeight)
            context.rotate(by: -.pi / 2)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetHeight, height: targetWidth))
        case .right:
            context.translateBy(x: targetWidth, y: 0)
            context.rotate(by: .pi / 2)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetHeight, height: targetWidth))
        case .upMirrored:
            context.translateBy(x: targetWidth, y: 0)
            context.scaleBy(x: -1, y: 1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        case .downMirrored:
            context.translateBy(x: 0, y: targetHeight)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        case .leftMirrored:
            context.translateBy(x: targetWidth, y: 0)
            context.rotate(by: .pi / 2)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetHeight, height: targetWidth))
        case .rightMirrored:
            context.translateBy(x: 0, y: targetHeight)
            context.rotate(by: -.pi / 2)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetHeight, height: targetWidth))
        default: // .up
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        }

        context.restoreGState()

        return buffer
    }
}
