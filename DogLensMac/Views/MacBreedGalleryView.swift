import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct MacBreedGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DogBreed.name) private var breeds: [DogBreed]

    @State private var searchText = ""
    @State private var selectedBreed: DogBreed?
    @State private var selectedImageForPreview: BreedImage?

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
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Breed Collection")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(unlockedCount) of \(breeds.count) Breeds Unlocked")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // iCloud Sync Button
                Button {
                    Task {
                        await MacCloudKitService.shared.syncFromCloud(modelContext: modelContext)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "icloud.and.arrow.down")
                        Text("Sync iCloud")
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
                LazyVGrid(columns: columns, spacing: 16) {
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
            .searchable(text: $searchText, prompt: "Search 52 Breeds…")
        }
        .sheet(item: $selectedBreed) { breed in
            MacBreedDetailSheet(breed: breed)
                .frame(minWidth: 650, minHeight: 500)
        }
    }
}

// MARK: - Mac Breed Card
struct MacBreedCard: View {
    let breed: DogBreed

    private var isUnlocked: Bool {
        !breed.images.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                Color(NSColor.controlBackgroundColor)
                if let first = breed.images.first, let nsImg = NSImage(data: first.imageData) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }
            .frame(height: 130)
            .clipped()

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(breed.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if isUnlocked {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                            .font(.subheadline)
                    }
                }

                Text("\(breed.images.count) Items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isUnlocked ? Color.blue.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
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
                        "No Saved Images",
                        systemImage: "photo.on.rectangle",
                        description: Text("Scan a \(breed.name) using the scanner to unlock and collect it.")
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
                }
            }
            .sheet(item: $previewImage) { item in
                MacFullScreenMediaView(breedImage: item)
                    .frame(minWidth: 700, minHeight: 600)
            }
        }
    }

    private func deleteImage(_ image: BreedImage) {
        if let idx = breed.images.firstIndex(where: { $0.id == image.id }) {
            breed.images.remove(at: idx)
            modelContext.delete(image)
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

        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let data = image.jpegData {
                try? data.write(to: url)
            }
        }
    }
}
