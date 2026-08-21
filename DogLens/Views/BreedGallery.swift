import SwiftUI
import SwiftData

struct BreedGalleryView: View {
    @Query(sort: \DogBreed.name) private var breeds: [DogBreed]
    
    let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if breeds.isEmpty {
                    ContentUnavailableView("No Breeds Found", systemImage: "magnifyingglass", description: Text("Dog breeds haven't been loaded yet."))
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(breeds) { breed in
                            NavigationLink(destination: BreedDetailView(breed: breed)) {
                                BreedCard(breed: breed)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Breed Gallery")
            .background(Color(.systemGroupedBackground))
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
                if let firstImage = breed.images.first, let uiImage = UIImage(data: firstImage.imageData) {
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
