import SwiftUI
import Combine

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var isDetecting = false
    @Published var detectionResults: [DetectionResult]?
    @Published var showResult = false
    @Published var showNoDetection = false
    @Published var errorMessage: String?

    func detect(image: UIImage) {
        isDetecting = true
        Task {
            do {
                let results = try await ModelService.shared.detectDogs(in: image)
                self.isDetecting = false
                self.detectionResults = results
                if results.isEmpty {
                    self.showNoDetection = true
                } else {
                    self.showResult = true
                }
            } catch {
                self.isDetecting = false
                self.errorMessage = "Detection failed: \(error.localizedDescription)"
            }
        }
    }
}
