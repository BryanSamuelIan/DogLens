import Foundation
import CoreGraphics

struct DetectionResult: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let label: String
    let confidence: Float
}
