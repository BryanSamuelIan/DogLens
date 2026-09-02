import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

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
                .frame(minWidth: 650, minHeight: 500)
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

// MARK: - Mac Breed Detail Sheet
struct MacBreedDetailSheet: View {
    @Bindable var breed: DogBreed
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var previewImage: BreedImage?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if breed.images.isEmpty {
                    ContentUnavailableView(
                        "No Saved Photos",
                        systemImage: "photo.on.rectangle",
                        description: Text("Scan a \(breed.name) using the scanner to collect it.")
                    )
                    .padding(50)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(breed.images) { item in
                                ZStack {
                                    Color(NSColor.controlBackgroundColor)
                                    if let nsImg = NSImage(data: item.imageData) {
                                        Image(nsImage: nsImg)
                                            .resizable()
                                            .scaledToFill()
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    previewImage = item
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteImage(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle(breed.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $previewImage) { item in
                MacFullScreenMediaView(breedImage: item)
                    .frame(minWidth: 700, minHeight: 600)
            }
        }
    }

    private func deleteImage(_ item: BreedImage) {
        if let idx = breed.images.firstIndex(where: { $0.id == item.id }) {
            breed.images.remove(at: idx)
            modelContext.delete(item)
            try? modelContext.save()
        }
    }
}

// MARK: - Mac Full Screen Media Preview View
struct MacFullScreenMediaView: View {
    let breedImage: BreedImage
    @Environment(\.dismiss) private var dismiss
    @State private var showOriginal = false

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
                if breedImage.annotatedImageData != nil {
                    Picker("Mode", selection: $showOriginal) {
                        Text("Detection").tag(false)
                        Text("Original").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .padding(.top, 12)
                    .tint(.orange)
                }

                if let img = displayImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                } else {
                    Text("Error loading image")
                }

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        let breedName = breedImage.breed?.name.replacingOccurrences(of: " ", with: "_") ?? "Dog"
                        let filename = "DogLens_\(breedName)_\(showOriginal ? "Original" : "Detection").jpg"
                        if let img = displayImage {
                            saveImageToFile(image: img, defaultName: filename)
                        }
                    } label: {
                        Label("Save to File…", systemImage: "arrow.down.doc")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                }
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
}
