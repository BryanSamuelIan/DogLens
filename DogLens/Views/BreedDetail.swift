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
                ContentUnavailableView(
                    "No Items",
                    systemImage: "photo.on.rectangle",
                    description: Text("No items for \(breed.name) have been saved yet.")
                )
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(breed.images) { breedImage in
                        BreedMediaGridItem(breedImage: breedImage)
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
        .navigationTitle(breed.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedBreedImage) { _ in
            BreedMediaGalleryPager(breed: breed, selectedItem: $selectedBreedImage)
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

// MARK: - Breed Media Gallery Pager (Swipe Left/Right Between Media)

struct BreedMediaGalleryPager: View {
    @Bindable var breed: DogBreed
    @Binding var selectedItem: BreedImage?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: UUID
    @State private var showOriginal = false

    init(breed: DogBreed, selectedItem: Binding<BreedImage?>) {
        self._breed = Bindable(breed)
        self._selectedItem = selectedItem
        let initialID = selectedItem.wrappedValue?.id ?? breed.images.first?.id ?? UUID()
        self._selectedID = State(initialValue: initialID)
    }

    private var currentIndex: Int {
        breed.images.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    private var currentItem: BreedImage? {
        breed.images.first(where: { $0.id == selectedID })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $selectedID) {
                    ForEach(breed.images) { item in
                        Group {
                            if item.isVideo {
                                ZoomableVideoView(
                                    breedImage: item,
                                    showOriginal: showOriginal,
                                    isCurrentPage: selectedID == item.id
                                )
                            } else {
                                ZoomableImageView(
                                    breedImage: item,
                                    showOriginal: showOriginal
                                )
                            }
                        }
                        .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selectedItem = nil
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.85))
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(breed.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        if breed.images.count > 1 {
                            Text("\(currentIndex + 1) of \(breed.images.count)")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if let current = currentItem,
                       (current.annotatedImageData != nil || current.annotatedVideoData != nil) {
                        Picker("View Mode", selection: $showOriginal) {
                            Text("Detection").tag(false)
                            Text("Original").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                }
            }
        }
    }
}

// MARK: - Zoomable Image View (Pinch-to-Zoom & Pan)

struct ZoomableImageView: View {
    let breedImage: BreedImage
    let showOriginal: Bool

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var image: UIImage? {
        if showOriginal {
            return UIImage(data: breedImage.imageData)
        } else {
            return UIImage(data: breedImage.annotatedImageData ?? breedImage.imageData)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let uiImage = image {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 1.0), 5.0)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    if scale <= 1.0 {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            scale = 1.0
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            scale > 1.0 ?
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                } : nil
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.5
                                }
                            }
                        }
                } else {
                    Text("Error loading image")
                        .foregroundColor(.white)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

// MARK: - Zoomable Video View (Pinch-to-Zoom & Autoplay on Active Page)

struct ZoomableVideoView: View {
    let breedImage: BreedImage
    let showOriginal: Bool
    let isCurrentPage: Bool

    @State private var player: AVPlayer?
    @State private var originalTempURL: URL?
    @State private var annotatedTempURL: URL?

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let player = player {
                    VideoPlayer(player: player)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 1.0), 5.0)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    if scale <= 1.0 {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            scale = 1.0
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            scale > 1.0 ?
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                } : nil
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.5
                                }
                            }
                        }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            setupTempFilesAndPlay()
        }
        .onDisappear {
            player?.pause()
            cleanupTempFiles()
        }
        .onChange(of: isCurrentPage) { _, isCurrent in
            if isCurrent {
                player?.play()
            } else {
                player?.pause()
            }
        }
        .onChange(of: showOriginal) { _, original in
            switchPlayer(showOriginal: original)
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

        let initialURL = (showOriginal ? originalTempURL : (annotatedTempURL ?? originalTempURL)) ?? originalTempURL
        if let initialURL {
            let p = AVPlayer(url: initialURL)
            player = p
            if isCurrentPage {
                p.play()
            }
        }
    }

    private func switchPlayer(showOriginal: Bool) {
        let url = showOriginal ? originalTempURL : (annotatedTempURL ?? originalTempURL)
        guard let url else { return }
        player?.pause()
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        if isCurrentPage {
            newPlayer.play()
        }
    }

    private func cleanupTempFiles() {
        if let url = originalTempURL { try? FileManager.default.removeItem(at: url) }
        if let url = annotatedTempURL { try? FileManager.default.removeItem(at: url) }
    }
}

// MARK: - Breed Media Grid Item (Bounded 1:1 Aspect Ratio)

struct BreedMediaGridItem: View {
    let breedImage: BreedImage

    var body: some View {
        Color.gray.opacity(0.15)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let uiImage = UIImage(data: breedImage.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if breedImage.isVideo {
                    HStack(spacing: 3) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(5)
                }
            }
    }
}
