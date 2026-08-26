import SwiftUI

struct ImagePreviewView: View {
    let image: UIImage
    @StateObject private var vm = ScannerViewModel()
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

            if vm.isDetecting {
                ProgressView("Analyzing image...")
                    .padding()
            } else {
                Button(action: { vm.detect(image: image) }) {
                    Text("Detect Dogs")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(16)
                }
                .padding(.horizontal)

                Button(action: { dismiss() }) {
                    Text("Retake")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .padding()
                }
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $vm.showResult) {
            if let results = vm.detectionResults, !results.isEmpty {
                ResultView(image: image, results: results)
            }
        }
        .navigationDestination(isPresented: $vm.showNoDetection) {
            NoDetectionView()
        }
        .alert("Detection Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}
