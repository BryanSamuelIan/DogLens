import SwiftUI
import SwiftData

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
                ContentUnavailableView("No Images", systemImage: "photo.on.rectangle", description: Text("No images of \(breed.name) have been saved yet."))
                    .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(breed.images) { breedImage in
                        if let uiImage = UIImage(data: breedImage.imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
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
            FullScreenImageView(breedImage: breedImage)
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
