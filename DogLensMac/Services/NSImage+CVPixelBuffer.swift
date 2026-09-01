import AppKit
import CoreGraphics
import CoreImage
import VideoToolbox

extension NSImage {
    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        guard let cgImage = self.cgImage else { return nil }

        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attrs, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        let targetWidth = CGFloat(width)
        let targetHeight = CGFloat(height)

        let scaleX = targetWidth / ciImage.extent.width
        let scaleY = targetHeight / ciImage.extent.height

        let transform = CGAffineTransform(translationX: -ciImage.extent.origin.x, y: -ciImage.extent.origin.y)
            .scaledBy(x: scaleX, y: scaleY)

        let finalImage = ciImage.transformed(by: transform)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        NSImage.sharedCIContext.render(finalImage, to: buffer, bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight), colorSpace: colorSpace)

        return buffer
    }

    /// Converts NSImage to JPEG Data
    var jpegData: Data? {
        guard let tiffRepresentation = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
