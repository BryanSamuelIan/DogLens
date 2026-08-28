import SwiftUI
import Combine

@MainActor
final class LiveScannerViewModel: ObservableObject {
    @Published var detectionResults: [DetectionResult] = []
    
    private var isProcessing = false

    func processFrame(_ image: UIImage) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            let results = try await ModelService.shared.detectDogs(in: image)
            self.detectionResults = results
        } catch {
            print("Live inference error: \(error.localizedDescription)")
        }
    }
    
    func clearResults() {
        self.detectionResults = []
    }
}
