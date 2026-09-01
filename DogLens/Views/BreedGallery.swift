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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                Color.gray.opacity(0.2)
                if let firstImage = breed.images.first,
                   let uiImage = UIImage(data: firstImage.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                }
            }
            .frame(height: 120)
            .clipped()

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(breed.name)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(breed.imageCount) Images")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    BreedGalleryView()
}
