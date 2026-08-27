import SwiftUI
import SwiftData
import AVKit

struct VideoPreviewView: View {
    let videoURL: URL
    var onScanAgain: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var breeds: [DogBreed]

    @StateObject private var vm: VideoInferenceViewModel
    @State private var player: AVPlayer
    @State private var navigateToResult = false

    init(videoURL: URL, onScanAgain: (() -> Void)? = nil) {
        self.videoURL = videoURL
        self.onScanAgain = onScanAgain
        _vm = StateObject(wrappedValue: VideoInferenceViewModel(videoURL: videoURL))
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ── Raw Video Player ────────────────────────────────────
                VideoPlayer(player: player)
                    .frame(height: 360)
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)

                // ── Controls ───────────────────────────────────────────
                if vm.isInferring {
                    inferringView
                } else {
                    detectButton
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 16)
        }
        .navigationTitle("Video Preview")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToResult) {
            VideoResultView(vm: vm, onScanAgain: {
                player.pause()
                dismiss()
            })
        }
        .onAppear {
            vm.modelContext = modelContext
            vm.breeds = breeds
            if player.currentItem == nil {
                player = AVPlayer(url: videoURL)
            }
            player.play()
        }
        .onDisappear {
            player.pause()
        }
        .onChange(of: vm.annotatedVideoURL) { _, newURL in
            if newURL != nil {
                player.pause()
                navigateToResult = true
            }
        }
        .onChange(of: breeds) { _, newBreeds in
            vm.breeds = newBreeds
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Sub-views

    private var inferringView: some View {
        VStack(spacing: 16) {
            ProgressView(value: vm.progress)
                .progressViewStyle(.linear)
                .tint(.orange)
                .padding(.horizontal)

            Text("Running CoreML at 15 fps (\(Int(vm.progress * 100))%)")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.horizontal)
    }

    private var detectButton: some View {
        VStack(spacing: 16) {
            Button {
                Task {
                    await vm.runInference()
                }
            } label: {
                HStack {
                    Image(systemName: "brain")
                    Text("Detect Dogs")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .cornerRadius(16)
            }
            .padding(.horizontal)

            Button {
                player.pause()
                dismiss()
            } label: {
                Text("Go Back")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.vertical, 8)
            }
        }
    }
}
