import SwiftUI
import AVKit
import SwiftData

// MARK: - Video Preview View

struct VideoPreviewView: View {
    let videoURL: URL

    @StateObject private var vm: VideoInferenceViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var breeds: [DogBreed]

    /// Controls which URL the AVPlayer shows
    @State private var displayedURL: URL
    @State private var player: AVPlayer
    @State private var showAnnotated = false

    init(videoURL: URL) {
        self.videoURL = videoURL
        _vm = StateObject(wrappedValue: VideoInferenceViewModel(videoURL: videoURL))
        _displayedURL = State(initialValue: videoURL)
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // ── Mode Picker (only after inference) ──────────────────
                if vm.annotatedVideoURL != nil {
                    Picker("View Mode", selection: $showAnnotated) {
                        Text("Original").tag(false)
                        Text("Detected").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: showAnnotated) { _, annotated in
                        switchPlayer(to: annotated ? vm.annotatedVideoURL! : videoURL)
                    }
                }

                // ── Video Player ────────────────────────────────────────
                VideoPlayer(player: player)
                    .frame(height: 360)
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)

                // ── Inference Controls ──────────────────────────────────
                if vm.isInferring {
                    inferringView
                } else if vm.annotatedVideoURL == nil {
                    detectButton
                } else {
                    saveActionsView
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 16)
        }
        .navigationTitle("Video Preview")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vm.modelContext = modelContext
            vm.breeds = breeds
            player.play()
        }
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        .onChange(of: breeds) { _, newBreeds in vm.breeds = newBreeds }
        .alert("Save Result", isPresented: $vm.showingSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(vm.saveMessage)
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
            Text("Analyzing video…")
                .font(.headline)
                .foregroundColor(.secondary)

            ProgressView(value: vm.progress) {
                Text(String(format: "%.0f%%", vm.progress * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .progressViewStyle(.linear)
            .tint(.orange)
            .padding(.horizontal)

            Text("Running CoreML at 15 fps")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal)
    }

    private var detectButton: some View {
        VStack(spacing: 16) {
            Button {
                Task { await vm.runInference() }
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
        .padding(.horizontal)
    }

    private var saveActionsView: some View {
        VStack(spacing: 16) {
            // Save annotated video to Photos
            Button {
                vm.saveToPhotos()
            } label: {
                HStack {
                    if vm.isSavingToPhotos {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text("Save Video to Photos")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(16)
            }
            .disabled(vm.isSavingToPhotos)

            // Save best frame to Breed Gallery
            Button {
                vm.saveToBreedGallery()
            } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("Save Best Frame to Gallery")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .cornerRadius(16)
            }

            // Scan again
            Button {
                player.pause()
                dismiss()
            } label: {
                Text("Scan Again")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func switchPlayer(to url: URL) {
        let wasPlaying = player.rate != 0
        player.pause()
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        if wasPlaying { player.play() }
    }
}
