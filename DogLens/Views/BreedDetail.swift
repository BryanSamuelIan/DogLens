import SwiftUI
import SwiftData
import AVKit

struct BreedDetailView: View {
    @Bindable var breed: DogBreed
    @Environment(\.modelContext) private var modelContext
    @State private var selectedBreedImage: BreedImage?

    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ScrollView {
            if breed.images.isEmpty {
                ContentUnavailableView("No Items", systemImage: "photo.on.rectangle", description: Text("No items for \(breed.name) have been saved yet."))
                    .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(breed.images) { breedImage in
                        if let uiImage = UIImage(data: breedImage.imageData) {
                            ZStack(alignment: .bottomTrailing) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(minWidth: 0, maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipped()

                                if breedImage.isVideo {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
                                        .padding(6)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedBreedImage = breedImage
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteImage(breedImage)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(breed.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedBreedImage) { breedImage in
            if breedImage.isVideo {
                FullScreenVideoView(breedImage: breedImage)
            } else {
                FullScreenImageView(breedImage: breedImage)
            }
        }
    }

    private func deleteImage(_ breedImage: BreedImage) {
        if let index = breed.images.firstIndex(where: { $0.id == breedImage.id }) {
            breed.images.remove(at: index)
            modelContext.delete(breedImage)
            do {
                try modelContext.save()
            } catch {
                print("Failed to delete image")
            }
        }
    }
}

// MARK: - Full Screen Image View

struct FullScreenImageView: View {
    let breedImage: BreedImage
    @Environment(\.dismiss) var dismiss
    @State private var showOriginal = false

    var displayImage: UIImage? {
        if showOriginal {
            return UIImage(data: breedImage.imageData)
        } else {
            return UIImage(data: breedImage.annotatedImageData ?? breedImage.imageData)
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if breedImage.annotatedImageData != nil {
                    Picker("View Mode", selection: $showOriginal) {
                        Text("Detection").tag(false)
                        Text("Original").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }

                if let img = displayImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("Error loading image")
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Full Screen Video View

struct FullScreenVideoView: View {
    let breedImage: BreedImage
    @Environment(\.dismiss) var dismiss
    @State private var showOriginal = false
    @State private var player: AVPlayer?

    @State private var originalTempURL: URL?
    @State private var annotatedTempURL: URL?

    var body: some View {
        NavigationStack {
            VStack {
                if breedImage.annotatedVideoData != nil {
                    Picker("View Mode", selection: $showOriginal) {
                        Text("Detection").tag(false)
                        Text("Original").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    .onChange(of: showOriginal) { _, original in
                        switchPlayer(showOriginal: original)
                    }
                }

                if let player = player {
                    VideoPlayer(player: player)
                        .frame(maxHeight: 500)
                        .cornerRadius(16)
                        .padding()
                } else {
                    ProgressView("Loading video…")
                        .padding()
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupTempFilesAndPlay()
            }
            .onDisappear {
                player?.pause()
                cleanupTempFiles()
            }
        }
    }

    private func setupTempFilesAndPlay() {
        let tempDir = FileManager.default.temporaryDirectory
        if let origData = breedImage.videoData {
            let url = tempDir.appendingPathComponent("gallery_orig_\(breedImage.id.uuidString).mp4")
            try? origData.write(to: url)
            originalTempURL = url
        }

        if let annData = breedImage.annotatedVideoData {
            let url = tempDir.appendingPathComponent("gallery_ann_\(breedImage.id.uuidString).mp4")
            try? annData.write(to: url)
            annotatedTempURL = url
        }

        let initialURL = breedImage.annotatedVideoData != nil ? annotatedTempURL : originalTempURL
        if let initialURL {
            let p = AVPlayer(url: initialURL)
            player = p
            p.play()
        }
    }

    private func switchPlayer(showOriginal: Bool) {
        let url = showOriginal ? originalTempURL : (annotatedTempURL ?? originalTempURL)
        guard let url else { return }
        player?.pause()
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        newPlayer.play()
    }

    private func cleanupTempFiles() {
        if let url = originalTempURL { try? FileManager.default.removeItem(at: url) }
        if let url = annotatedTempURL { try? FileManager.default.removeItem(at: url) }
    }
}
