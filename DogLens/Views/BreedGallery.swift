import SwiftUI
import SwiftData

struct BreedGalleryView: View {
    @Query(sort: \DogBreed.name) private var breeds: [DogBreed]
    @StateObject private var vm = BreedGalleryViewModel()
    @ObservedObject private var cloudService = CloudKitService.shared
    @Environment(\.modelContext) private var modelContext
    @State private var showProfileSheet = false

    let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    private let totalBreeds = DogBreed.predefinedBreeds.count

    var unlockedCount: Int {
        breeds.filter { $0.imageCount > 0 }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let displayed = vm.filteredBreeds(from: breeds)
                if displayed.isEmpty {
                    ContentUnavailableView(
                        vm.searchText.isEmpty ? "No Breeds Found" : "No Results",
                        systemImage: "magnifyingglass",
                        description: Text(
                            vm.searchText.isEmpty
                                ? "Dog breeds haven't been loaded yet."
                                : "No breeds match \"\(vm.searchText)\"."
                        )
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(displayed) { breed in
                            NavigationLink(destination: BreedDetailView(breed: breed)) {
                                BreedCard(breed: breed)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .refreshable {
                await cloudService.syncWithLocalDatabase(modelContext: modelContext)
                await cloudService.refreshCloudItemCount()
            }
            .task {
                await cloudService.syncWithLocalDatabase(modelContext: modelContext)
                await cloudService.refreshCloudItemCount()
            }
            .navigationTitle("Breed Gallery")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showProfileSheet = true
                    } label: {
                        iCloudIconButton
                    }
                    .buttonStyle(.plain)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "pawprint.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("\(unlockedCount)/\(totalBreeds)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("Unlocked")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .searchable(text: $vm.searchText, prompt: "Search breeds")
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showProfileSheet) {
                ProfileSheetView()
            }
        }
    }

    @ViewBuilder
    private var iCloudIconButton: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 32, height: 32)
            
            switch cloudService.syncState {
            case .syncing:
                ProgressView()
                    .scaleEffect(0.7)
            case .synced:
                Image(systemName: "icloud.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.blue)
            case .error:
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red)
            case .idle:
                Image(systemName: "icloud.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.blue)
            }
        }
    }
}

struct BreedCard: View {
    let breed: DogBreed

    private var photoCount: Int {
        breed.images.filter { !$0.isVideo }.count
    }
    
    private var videoCount: Int {
        breed.images.filter { $0.isVideo }.count
    }

    private var countSubtitle: String {
        if breed.images.isEmpty {
            return "0 Items"
        } else if videoCount == 0 {
            return "\(photoCount) Photo\(photoCount == 1 ? "" : "s")"
        } else if photoCount == 0 {
            return "\(videoCount) Video\(videoCount == 1 ? "" : "s")"
        } else {
            return "\(photoCount) Photo\(photoCount == 1 ? "" : "s") • \(videoCount) Video\(videoCount == 1 ? "" : "s")"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail / Mini Grid Preview
            thumbnailView
                .aspectRatio(4/3, contentMode: .fit)
                .clipped()

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(breed.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text(countSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if breed.images.isEmpty {
            Color.gray.opacity(0.12)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundColor(.secondary.opacity(0.6))
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
        Color.gray.opacity(0.12)
            .overlay {
                if let uiImage = UIImage(data: item.imageData) {
                    Image(uiImage: uiImage)
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
        HStack(spacing: 1.5) {
            ForEach(breed.images.prefix(2)) { item in
                Color.gray.opacity(0.12)
                    .overlay {
                        if let uiImage = UIImage(data: item.imageData) {
                            Image(uiImage: uiImage)
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
        HStack(spacing: 1.5) {
            // Main left item
            if let first = items.first {
                Color.gray.opacity(0.12)
                    .overlay {
                        if let uiImage = UIImage(data: first.imageData) {
                            Image(uiImage: uiImage)
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
                VStack(spacing: 1.5) {
                    ForEach(Array(items.dropFirst().prefix(2))) { item in
                        Color.gray.opacity(0.12)
                            .overlay {
                                if let uiImage = UIImage(data: item.imageData) {
                                    Image(uiImage: uiImage)
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
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(.black.opacity(0.65), in: Capsule())
            .padding(4)
    }
}

#Preview {
    BreedGalleryView()
}
