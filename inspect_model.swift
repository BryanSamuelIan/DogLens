import Foundation
import CoreML

let modelUrl = URL(fileURLWithPath: "/Users/bryansamuel/ADA/DogLens/DogLens/Resources/Models/DogLensImage.mlpackage")
if let model = try? MLModel(contentsOf: modelUrl) {
    let description = model.modelDescription
    print("Inputs:")
    for input in description.inputDescriptionsByName {
        print("\(input.key): \(input.value.type)")
    }
    print("Outputs:")
    for output in description.outputDescriptionsByName {
        print("\(output.key): \(output.value.type)")
    }
} else {
    print("Failed to load model")
}
