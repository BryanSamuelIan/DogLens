import SwiftUI
import PhotosUI

struct HomeView: View {
    @State private var showCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showPreview = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // App Logo Placeholder
                Image(systemName: "viewfinder.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(.orange, .blue.opacity(0.8))
                
                VStack(spacing: 8) {
                    Text("DogLens")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Identify dog breeds instantly using CoreML.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    Button(action: {
                        showCamera = true
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Scan Dog")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(16)
                    }
                    
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Upload Photo")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(16)
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                selectedImage = image
                                showPreview = true
                                selectedPhotoItem = nil
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .padding(.top, 60)
            .navigationDestination(isPresented: $showPreview) {
                if let image = selectedImage {
                    ImagePreviewView(image: image)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                ScannerView { image in
                    if let image = image {
                        selectedImage = image
                        showPreview = true
                    }
                }
            }
        }
    }
}

#Preview {
    HomeView()
}
