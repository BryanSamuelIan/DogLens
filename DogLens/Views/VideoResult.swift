import SwiftUI
import SwiftData
import AVKit

struct VideoResultView: View {
    @ObservedObject var vm: VideoInferenceViewModel
    var onScanAgain: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var breeds: [DogBreed]

    @State private var showAnnotated = true
    @State private var player: AVPlayer?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ── View Mode Picker ──────────────────────────────────────
                if vm.annotatedVideoURL != nil {
                    Picker("View Mode", selection: $showAnnotated) {
                        Text("Detected").tag(true)
                        Text("Original").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: showAnnotated) { _, annotated in
                        switchPlayer(showAnnotated: annotated)
                    }
                }

                // ── Video Player ──────────────────────────────────────────
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(height: 360)
                        .cornerRadius(16)
                        .padding(.horizontal)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                } else {
                    ProgressView("Loading video…")
                        .frame(height: 360)
                }

                // ── Detection Results List ────────────────────────────────
                VStack(spacing: 16) {
                    let detections = vm.allVideoDetections
                        .map { (breedName: $0.key, confidence: $0.value) }
                        .sorted { $0.confidence > $1.confidence }

                    Text("\(detections.count) Dog(s) Detected")
                        .font(.title2)
                        .fontWeight(.bold)

                    if detections.isEmpty {
                        Text("No dog breeds detected in video.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(detections, id: \.breedName) { item in
                            HStack {
                                Text(item.breedName)
                                    .font(.headline)
                                Spacer()
                                Text(String(format: "%.1f%%", item.confidence * 100))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)

                // ── Action Buttons ────────────────────────────────────────
                VStack(spacing: 16) {
                    // Save to Photos
                    Button(action: vm.saveToPhotos) {
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

                    // Save to Breed Gallery (Only if highest confidence is at least 70% / 0.7)
                    if vm.allVideoDetections.values.contains(where: { $0 >= 0.70 }) {
                        Button(action: vm.saveToBreedGallery) {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                Text("Save Video to Breed Gallery")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(16)
                        }
                    }

                    // Scan Again
                    Button {
                        player?.pause()
                        if let onScanAgain {
                            onScanAgain()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text("Scan Again")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .padding()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .padding(.top, 16)
        }
        .navigationTitle("Video Result")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vm.modelContext = modelContext
            vm.breeds = breeds
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
        .onChange(of: breeds) { _, newBreeds in
            vm.breeds = newBreeds
        }
        .alert("Save Result", isPresented: $vm.showingSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(vm.saveMessage)
        }
    }

    private func setupPlayer() {
        let targetURL = (showAnnotated ? vm.annotatedVideoURL : nil) ?? vm.sourceURL
        let p = AVPlayer(url: targetURL)
        player = p
        p.play()
    }

    private func switchPlayer(showAnnotated: Bool) {
        let targetURL = (showAnnotated ? vm.annotatedVideoURL : nil) ?? vm.sourceURL
        player?.pause()
        let newPlayer = AVPlayer(url: targetURL)
        player = newPlayer
        newPlayer.play()
    }
}
