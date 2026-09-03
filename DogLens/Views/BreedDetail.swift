import SwiftUI
import SwiftData
import AVKit

struct BreedDetailView: View {
    @Bindable var breed: DogBreed
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedBreedImage: BreedImage?
    @State private var isSelectionMode = false
    @State private var selectedIDs = Set<UUID>()
    
    @State private var showBatchDeleteDialog = false
    @State private var itemToDelete: BreedImage?
    @State private var showSingleDeleteDialog = false

    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                if breed.images.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "photo.on.rectangle",
                        description: Text("No photos or videos for \(breed.name) have been saved yet.")
                    )
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(breed.images) { breedImage in
                            let isSelected = selectedIDs.contains(breedImage.id)
                            
                            ZStack(alignment: .topTrailing) {
                                BreedMediaGridItem(breedImage: breedImage)
                                    .overlay {
                                        if isSelectionMode && isSelected {
                                            Color.orange.opacity(0.18)
                                                .overlay(
                                                    Rectangle()
                                                        .stroke(Color.orange, lineWidth: 3)
                                                )
                                        }
                                    }

                                if isSelectionMode {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(isSelected ? .orange : .white.opacity(0.9))
                                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                                        .padding(6)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelectionMode {
                                    toggleSelection(breedImage.id)
                                } else {
                                    selectedBreedImage = breedImage
                                }
                            }
                            .contextMenu(isSelectionMode ? nil : ContextMenu {
                                Button(role: .destructive) {
                                    itemToDelete = breedImage
                                    showSingleDeleteDialog = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            })
                        }
                    }
                    .padding(.bottom, isSelectionMode ? 80 : 20)
                }
            }
            
            // Bottom Action Bar for Selection Mode (Apple HIG compliant)
            if isSelectionMode && !breed.images.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Text(selectedIDs.isEmpty ? "Tap items to select" : "\(selectedIDs.count) selected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(role: .destructive) {
                            showBatchDeleteDialog = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill")
                                Text(selectedIDs.isEmpty ? "Delete" : "Delete (\(selectedIDs.count))")
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            .foregroundColor(selectedIDs.isEmpty ? .secondary : .red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                selectedIDs.isEmpty
                                ? Color.secondary.opacity(0.1)
                                : Color.red.opacity(0.12),
                                in: Capsule()
                            )
                        }
                        .disabled(selectedIDs.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !breed.images.isEmpty {
                if isSelectionMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(selectedIDs.count == breed.images.count ? "Deselect All" : "Select All") {
                            if selectedIDs.count == breed.images.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(breed.images.map { $0.id })
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectionMode = false
                                selectedIDs.removeAll()
                            }
                        }
                        .fontWeight(.semibold)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Select") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectionMode = true
                            }
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedBreedImage) { _ in
            BreedMediaGalleryPager(breed: breed, selectedItem: $selectedBreedImage)
        }
        .confirmationDialog(
            "Delete \(selectedIDs.count) Item\(selectedIDs.count == 1 ? "" : "s")?",
            isPresented: $showBatchDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedImages()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the selected \(selectedIDs.count == 1 ? "item" : "\(selectedIDs.count) items") from this device and iCloud.")
        }
        .confirmationDialog(
            "Delete \(itemToDelete?.isVideo == true ? "Video" : "Photo")?",
            isPresented: $showSingleDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    deleteSingleImage(item)
                    itemToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text("This will delete this \(itemToDelete?.isVideo == true ? "video" : "photo") from this device and iCloud.")
        }
        .onChange(of: breed.images.isEmpty) { _, isEmpty in
            if isEmpty && isSelectionMode {
                isSelectionMode = false
                selectedIDs.removeAll()
            }
        }
    }

    private var navigationTitle: String {
        if isSelectionMode {
            return selectedIDs.isEmpty ? "Select Items" : "\(selectedIDs.count) Selected"
        } else {
            return breed.name
        }
    }

    private func toggleSelection(_ id: UUID) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        withAnimation(.snappy(duration: 0.2)) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        }
    }

    private func deleteSingleImage(_ breedImage: BreedImage) {
        let idString = breedImage.id.uuidString
        if let index = breed.images.firstIndex(where: { $0.id == breedImage.id }) {
            withAnimation {
                breed.images.remove(at: index)
                modelContext.delete(breedImage)
            }
            do {
                try modelContext.save()
            } catch {
                print("Failed to delete image: \(error)")
            }
            Task {
                try? await CloudKitService.shared.deleteCloudMedia(recordName: idString)
            }
        }
    }

    private func deleteSelectedImages() {
        let idsToDelete = selectedIDs
        let itemsToDelete = breed.images.filter { idsToDelete.contains($0.id) }
        let recordNames = itemsToDelete.map { $0.id.uuidString }

        withAnimation {
            for item in itemsToDelete {
                if let idx = breed.images.firstIndex(where: { $0.id == item.id }) {
                    breed.images.remove(at: idx)
                }
                modelContext.delete(item)
            }
            selectedIDs.removeAll()
            isSelectionMode = false
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to batch save after delete: \(error)")
        }

        Task {
            try? await CloudKitService.shared.deleteCloudMedia(recordNames: recordNames)
        }
    }
}

// MARK: - Breed Media Gallery Pager (Swipe Left/Right Between Media & Full-Screen Delete)

struct BreedMediaGalleryPager: View {
    @Bindable var breed: DogBreed
    @Binding var selectedItem: BreedImage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedID: UUID
    @State private var showOriginal = false
    @State private var showDeleteConfirmation = false

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

                if !breed.images.isEmpty {
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

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let current = currentItem,
                       (current.annotatedImageData != nil || current.annotatedVideoData != nil) {
                        Picker("View Mode", selection: $showOriginal) {
                            Text("Detection").tag(false)
                            Text("Original").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                    
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundColor(.red)
                    }
                    .disabled(currentItem == nil)
                }
            }
            .confirmationDialog(
                "Delete \(currentItem?.isVideo == true ? "Video" : "Photo")?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteCurrentItem()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete this \(currentItem?.isVideo == true ? "video" : "photo") from this device and iCloud.")
            }
        }
    }

    private func deleteCurrentItem() {
        guard let item = currentItem else { return }
        let idString = item.id.uuidString
        let currentIdx = currentIndex
        
        // Determine next item to display before removal
        let nextID: UUID?
        if breed.images.count > 1 {
            if currentIdx + 1 < breed.images.count {
                nextID = breed.images[currentIdx + 1].id
            } else if currentIdx - 1 >= 0 {
                nextID = breed.images[currentIdx - 1].id
            } else {
                nextID = nil
            }
        } else {
            nextID = nil
        }

        withAnimation {
            if let idx = breed.images.firstIndex(where: { $0.id == item.id }) {
                breed.images.remove(at: idx)
            }
            modelContext.delete(item)
            try? modelContext.save()
            
            if let next = nextID {
                selectedID = next
            } else {
                selectedItem = nil
                dismiss()
            }
        }

        Task {
            try? await CloudKitService.shared.deleteCloudMedia(recordName: idString)
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
