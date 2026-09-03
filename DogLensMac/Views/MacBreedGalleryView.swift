import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import AVKit

struct MacBreedGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DogBreed.name) private var breeds: [DogBreed]
    @State private var cloudService = MacCloudKitService.shared

    @State private var searchText = ""
    @State private var selectedBreed: DogBreed?

    private var filteredBreeds: [DogBreed] {
        if searchText.isEmpty {
            return breeds
        } else {
            return breeds.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var unlockedCount: Int {
        breeds.filter { !$0.images.isEmpty }.count
    }

    private let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 250), spacing: 18)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Breed Gallery")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Discover and collect all 52 dog breeds")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Unlocked Counter Badge
                HStack(spacing: 5) {
                    Image(systemName: "pawprint.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("\(unlockedCount)/\(breeds.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("Unlocked")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))

                // iCloud Sync Button
                Button {
                    Task {
                        await cloudService.syncFromCloud(modelContext: modelContext)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "icloud.and.arrow.down.fill")
                            .foregroundColor(.orange)
                        Text(cloudService.syncStatus == .syncing ? "Syncing…" : "Sync iCloud")
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Grid
            ScrollView {
                if filteredBreeds.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Breeds Found" : "No Results",
                        systemImage: "magnifyingglass",
                        description: Text(
                            searchText.isEmpty
                                ? "Dog breeds haven't been loaded yet."
                                : "No breeds match \"\(searchText)\"."
                        )
                    )
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(filteredBreeds) { breed in
                            MacBreedCard(breed: breed)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedBreed = breed
                                }
                        }
                    }
                    .padding(24)
                }
            }
            .searchable(text: $searchText, prompt: "Search 52 Breeds…")
        }
        .sheet(item: $selectedBreed) { breed in
            MacBreedDetailSheet(breed: breed)
                .frame(minWidth: 700, minHeight: 520)
        }
        .task {
            await cloudService.syncFromCloud(modelContext: modelContext)
        }
    }
}

// MARK: - Mac Breed Card
struct MacBreedCard: View {
    let breed: DogBreed

    private var isUnlocked: Bool {
        !breed.images.isEmpty
    }

    private var photoCount: Int {
        breed.images.filter { !$0.isVideo }.count
    }

    private var videoCount: Int {
        breed.images.filter { $0.isVideo }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail / Mini Grid Preview
            thumbnailView
                .aspectRatio(4/3, contentMode: .fit)
                .clipped()

            // Info Section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(breed.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                    if isUnlocked {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.orange)
                            .font(.subheadline)
                    }
                }

                HStack(spacing: 4) {
                    if !isUnlocked {
                        Text("0 Photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        if videoCount == 0 {
                            Text("\(photoCount) Photo\(photoCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if photoCount == 0 {
                            Text("\(videoCount) Video\(videoCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(photoCount) Photo\(photoCount == 1 ? "" : "s") • \(videoCount) Video\(videoCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isUnlocked ? Color.orange.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: isUnlocked ? 1.5 : 1)
        )
        .shadow(color: isUnlocked ? Color.orange.opacity(0.08) : Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if breed.images.isEmpty {
            Color(NSColor.controlBackgroundColor).opacity(0.7)
                .overlay {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.orange.opacity(0.35))
                }
        } else if breed.images.count == 1, let first = breed.images.first {
            singleThumbnail(first)
        } else if breed.images.count == 2 {
            twoItemGrid
        } else {
            multiItemCollage
        }
    }

    @ViewBuilder
    private func singleThumbnail(_ item: BreedImage) -> some View {
        Color(NSColor.controlBackgroundColor)
            .overlay {
                if let nsImg = NSImage(data: item.imageData) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if item.isVideo {
                    videoBadge
                }
            }
    }

    @ViewBuilder
    private var twoItemGrid: some View {
        HStack(spacing: 2) {
            ForEach(breed.images.prefix(2)) { item in
                Color(NSColor.controlBackgroundColor)
                    .overlay {
                        if let nsImg = NSImage(data: item.imageData) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if item.isVideo {
                            videoBadge
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var multiItemCollage: some View {
        let items = Array(breed.images.prefix(4))
        HStack(spacing: 2) {
            // Main left item
            if let first = items.first {
                Color(NSColor.controlBackgroundColor)
                    .overlay {
                        if let nsImg = NSImage(data: first.imageData) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if first.isVideo {
                            videoBadge
                        }
                    }
            }

            // Right side stacked items
            if items.count > 1 {
                VStack(spacing: 2) {
                    ForEach(Array(items.dropFirst().prefix(2))) { item in
                        Color(NSColor.controlBackgroundColor)
                            .overlay {
                                if let nsImg = NSImage(data: item.imageData) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .scaledToFill()
                                }
                            }
                            .clipped()
                            .overlay(alignment: .bottomTrailing) {
                                if item.isVideo {
                                    videoBadge
                                }
                            }
                    }
                }
            }
        }
    }

    private var videoBadge: some View {
        Image(systemName: "video.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.black.opacity(0.65), in: Capsule())
            .padding(6)
    }
}

// MARK: - Mac Breed Detail Sheet (with HIG Batch Selection & Single Delete)

struct MacBreedDetailSheet: View {
    @Bindable var breed: DogBreed
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var previewImage: BreedImage?
    @State private var isSelectionMode = false
    @State private var selectedIDs = Set<UUID>()

    @State private var showBatchDeleteAlert = false
    @State private var showSingleDeleteAlert = false
    @State private var itemToDelete: BreedImage?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if breed.images.isEmpty {
                    ContentUnavailableView(
                        "No Saved Items",
                        systemImage: "photo.on.rectangle",
                        description: Text("Scan a \(breed.name) using the scanner to collect it.")
                    )
                    .padding(50)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(breed.images) { item in
                                let isSelected = selectedIDs.contains(item.id)

                                ZStack(alignment: .topTrailing) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Color(NSColor.controlBackgroundColor)
                                        if let nsImg = NSImage(data: item.imageData) {
                                            Image(nsImage: nsImg)
                                                .resizable()
                                                .scaledToFill()
                                        }

                                        if item.isVideo {
                                            HStack(spacing: 3) {
                                                Image(systemName: "video.fill")
                                                    .font(.system(size: 8, weight: .bold))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 3)
                                            .background(.black.opacity(0.65), in: Capsule())
                                            .padding(6)
                                        }
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(
                                                isSelectionMode && isSelected
                                                ? Color.orange
                                                : Color.primary.opacity(0.08),
                                                lineWidth: isSelectionMode && isSelected ? 3 : 1
                                            )
                                    )

                                    if isSelectionMode {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(isSelected ? .orange : .white.opacity(0.9))
                                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                            .padding(6)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isSelectionMode {
                                        toggleSelection(item.id)
                                    } else {
                                        previewImage = item
                                    }
                                }
                                .contextMenu(isSelectionMode ? nil : ContextMenu {
                                    Button(role: .destructive) {
                                        itemToDelete = item
                                        showSingleDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                })
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle(sheetTitle)
            .toolbar {
                if isSelectionMode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            withAnimation {
                                isSelectionMode = false
                                selectedIDs.removeAll()
                            }
                        }
                    }

                    ToolbarItem(placement: .automatic) {
                        Button(selectedIDs.count == breed.images.count ? "Deselect All" : "Select All") {
                            if selectedIDs.count == breed.images.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(breed.images.map { $0.id })
                            }
                        }
                    }

                    ToolbarItem(placement: .automatic) {
                        Button(role: .destructive) {
                            showBatchDeleteAlert = true
                        } label: {
                            Label(
                                selectedIDs.isEmpty ? "Delete" : "Delete (\(selectedIDs.count))",
                                systemImage: "trash"
                            )
                            .foregroundColor(selectedIDs.isEmpty ? .secondary : .red)
                        }
                        .disabled(selectedIDs.isEmpty)
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            withAnimation {
                                isSelectionMode = false
                                selectedIDs.removeAll()
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                    }
                } else {
                    if !breed.images.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                withAnimation {
                                    isSelectionMode = true
                                }
                            } label: {
                                Label("Select", systemImage: "checkmark.circle")
                            }
                        }
                    }

                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundColor(.orange)
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(item: $previewImage) { item in
                MacFullScreenMediaView(breed: breed, breedImage: item)
                    .frame(minWidth: 700, minHeight: 600)
            }
            .alert("Delete \(selectedIDs.count) Item\(selectedIDs.count == 1 ? "" : "s")?", isPresented: $showBatchDeleteAlert) {
                Button("Delete", role: .destructive) {
                    deleteSelectedItems()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete the selected \(selectedIDs.count == 1 ? "item" : "\(selectedIDs.count) items") from this device and iCloud.")
            }
            .alert("Delete \(itemToDelete?.isVideo == true ? "Video" : "Photo")?", isPresented: $showSingleDeleteAlert) {
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
    }

    private var sheetTitle: String {
        if isSelectionMode {
            return selectedIDs.isEmpty ? "Select Items" : "\(selectedIDs.count) Selected"
        } else {
            return breed.name
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func deleteSingleImage(_ item: BreedImage) {
        let idString = item.id.uuidString
        if let idx = breed.images.firstIndex(where: { $0.id == item.id }) {
            breed.images.remove(at: idx)
            modelContext.delete(item)
            try? modelContext.save()

            Task {
                await MacCloudKitService.shared.deleteCloudMedia(recordName: idString)
            }
        }
    }

    private func deleteSelectedItems() {
        let idsToDelete = selectedIDs
        let itemsToDelete = breed.images.filter { idsToDelete.contains($0.id) }
        let recordNames = itemsToDelete.map { $0.id.uuidString }

        for item in itemsToDelete {
            if let idx = breed.images.firstIndex(where: { $0.id == item.id }) {
                breed.images.remove(at: idx)
            }
            modelContext.delete(item)
        }

        selectedIDs.removeAll()
        isSelectionMode = false

        try? modelContext.save()

        Task {
            await MacCloudKitService.shared.deleteCloudMedia(recordNames: recordNames)
        }
    }
}

// MARK: - Mac Full Screen Media Preview View (Photo + Video Support & Single Deletion)

struct MacFullScreenMediaView: View {
    @Bindable var breed: DogBreed
    let breedImage: BreedImage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showOriginal = false
    @State private var showDeleteAlert = false
    @State private var player: AVPlayer?
    @State private var tempVideoURL: URL?

    private var displayImage: NSImage? {
        if showOriginal {
            return NSImage(data: breedImage.imageData)
        } else {
            return NSImage(data: breedImage.annotatedImageData ?? breedImage.imageData)
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if (breedImage.annotatedImageData != nil || breedImage.annotatedVideoData != nil) {
                    Picker("Mode", selection: $showOriginal) {
                        Text("Detection").tag(false)
                        Text("Original").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .padding(.top, 12)
                    .tint(.orange)
                }

                if breedImage.isVideo {
                    if let player = player {
                        VideoPlayer(player: player)
                            .frame(minHeight: 400)
                            .padding(20)
                    } else {
                        ProgressView("Loading Video…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    if let img = displayImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .padding(20)
                    } else {
                        Text("Error loading image")
                    }
                }

                Spacer()
            }
            .onAppear {
                if breedImage.isVideo {
                    setupVideoPlayer()
                }
            }
            .onDisappear {
                player?.pause()
                cleanupTempVideo()
            }
            .onChange(of: showOriginal) { _, original in
                if breedImage.isVideo {
                    setupVideoPlayer()
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        let breedName = breed.name.replacingOccurrences(of: " ", with: "_")
                        if breedImage.isVideo {
                            let filename = "DogLens_\(breedName)_\(showOriginal ? "Original" : "Detection").mp4"
                            saveVideoToFile(defaultName: filename)
                        } else if let img = displayImage {
                            let filename = "DogLens_\(breedName)_\(showOriginal ? "Original" : "Detection").jpg"
                            saveImageToFile(image: img, defaultName: filename)
                        }
                    } label: {
                        Label("Save to File…", systemImage: "arrow.down.doc")
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                }
            }
            .alert("Delete \(breedImage.isVideo ? "Video" : "Photo")?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    deleteCurrentMedia()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete this \(breedImage.isVideo ? "video" : "photo") from this device and iCloud.")
            }
        }
    }

    private func setupVideoPlayer() {
        cleanupTempVideo()
        let tempDir = FileManager.default.temporaryDirectory
        let data = showOriginal ? (breedImage.videoData ?? breedImage.annotatedVideoData) : (breedImage.annotatedVideoData ?? breedImage.videoData)
        guard let videoData = data else { return }

        let fileURL = tempDir.appendingPathComponent("mac_preview_\(breedImage.id.uuidString).mp4")
        try? videoData.write(to: fileURL)
        tempVideoURL = fileURL

        let p = AVPlayer(url: fileURL)
        player = p
        p.play()
    }

    private func cleanupTempVideo() {
        if let url = tempVideoURL {
            try? FileManager.default.removeItem(at: url)
            tempVideoURL = nil
        }
    }

    private func deleteCurrentMedia() {
        let idString = breedImage.id.uuidString
        if let idx = breed.images.firstIndex(where: { $0.id == breedImage.id }) {
            breed.images.remove(at: idx)
            modelContext.delete(breedImage)
            try? modelContext.save()
            dismiss()

            Task {
                await MacCloudKitService.shared.deleteCloudMedia(recordName: idString)
            }
        }
    }

    private func saveImageToFile(image: NSImage, defaultName: String) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.nameFieldStringValue = defaultName
        savePanel.allowedContentTypes = [.jpeg, .png]

        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloadsURL
        }

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            if let data = image.jpegData {
                try? data.write(to: url)
            }
        }
    }

    private func saveVideoToFile(defaultName: String) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.nameFieldStringValue = defaultName
        savePanel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]

        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloadsURL
        }

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            let data = showOriginal ? (breedImage.videoData ?? breedImage.annotatedVideoData) : (breedImage.annotatedVideoData ?? breedImage.videoData)
            if let data = data {
                try? data.write(to: url)
            }
        }
    }
}
