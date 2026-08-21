import SwiftUI

struct ImagePreviewView: View {
    let image: UIImage
    @State private var isDetecting = false
    @State private var detectionResults: [DetectionResult]?
    @State private var showResult = false
    @State private var showNoDetection = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Spacer()
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .cornerRadius(16)
                .padding()
            
            Spacer()
            
            if isDetecting {
                ProgressView("Analyzing image...")
                    .padding()
            } else {
                Button(action: detect) {
                    Text("Detect Dogs")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(16)
                }
                .padding(.horizontal)
                
                Button(action: {
                    dismiss()
                }) {
                    Text("Retake")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .padding()
                }
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showResult) {
            if let results = detectionResults, !results.isEmpty {
                ResultView(image: image, results: results)
            }
        }
        .navigationDestination(isPresented: $showNoDetection) {
            NoDetectionView()
        }
    }
    
    private func detect() {
        isDetecting = true
        Task {
            do {
                let results = try await ModelService.shared.detectDogs(in: image)
                DispatchQueue.main.async {
                    self.isDetecting = false
                    self.detectionResults = results
                    if results.isEmpty {
                        self.showNoDetection = true
                    } else {
                        self.showResult = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isDetecting = false
                    print("Detection error: \(error)")
                }
            }
        }
    }
}
