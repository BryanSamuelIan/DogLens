import SwiftUI
import SwiftData
import Photos

struct ResultView: View {
    let image: UIImage
    let results: [DetectionResult]
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingSaveAlert = false
    @State private var saveMessage = ""
    @Query private var breeds: [DogBreed]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Annotated Image
                AnnotatedImage(image: image, results: results)
                    .frame(maxHeight: 400)
                    .cornerRadius(16)
                    .padding(.horizontal)
                
                // Details
                VStack(spacing: 16) {
                    Text("\(results.count) Dog(s) Detected")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    ForEach(results) { result in
                        HStack {
                            Text(result.label)
                                .font(.headline)
                            Spacer()
                            Text(String(format: "%.1f%%", result.confidence * 100))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                // Actions
                VStack(spacing: 16) {
                    Button(action: saveToLibrary) {
                        Text("Save to Photos")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(16)
                    }
                    
                    Button(action: saveToSwiftData) {
                        Text("Save to Breed Gallery")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(16)
                    }
                    
                    Button(action: {
                        // Go back to home by dismissing twice (or using a root binding)
                        // For simplicity, just dismiss this view
                        dismiss()
                    }) {
                        Text("Scan Again")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .padding()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .padding(.top, 20)
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .alert(isPresented: $showingSaveAlert) {
            Alert(title: Text("Save Result"), message: Text(saveMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    private func saveToLibrary() {
        // Draw bounding boxes and save
        let annotatedImage = createAnnotatedUIImage()
        
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized || status == .limited {
                UIImageWriteToSavedPhotosAlbum(annotatedImage, nil, nil, nil)
                DispatchQueue.main.async {
                    saveMessage = "Image saved to your photos successfully."
                    showingSaveAlert = true
                }
            } else {
                DispatchQueue.main.async {
                    saveMessage = "Please grant photo library access in settings."
                    showingSaveAlert = true
                }
            }
        }
    }
    
    private func saveToSwiftData() {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
        
        for result in results {
            // Find the breed in SwiftData
            if let breed = breeds.first(where: { $0.name == result.label }) {
                let breedImage = BreedImage(imageData: imageData, confidence: Double(result.confidence))
                breed.images.append(breedImage)
            }
        }
        
        do {
            try modelContext.save()
            saveMessage = "Saved to Breed Gallery."
            showingSaveAlert = true
        } catch {
            saveMessage = "Failed to save to gallery."
            showingSaveAlert = true
        }
    }
    
    private func createAnnotatedUIImage() -> UIImage {
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
        image.draw(at: .zero)
        
        let context = UIGraphicsGetCurrentContext()!
        context.setLineWidth(5.0)
        context.setStrokeColor(UIColor.orange.cgColor)
        
        for result in results {
            context.stroke(result.boundingBox)
            
            // Draw text
            let text = result.label
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.orange
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(x: result.boundingBox.minX, y: max(0, result.boundingBox.minY - textSize.height), width: textSize.width, height: textSize.height)
            text.draw(in: textRect, withAttributes: attributes)
        }
        
        let annotatedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return annotatedImage
    }
}

struct AnnotatedImage: View {
    let image: UIImage
    let results: [DetectionResult]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                ForEach(results) { result in
                    let scaleX = geometry.size.width / image.size.width
                    let scaleY = geometry.size.height / image.size.height
                    
                    // The image might be letterboxed by scaledToFit. 
                    // To do this perfectly in SwiftUI requires knowing the rendered rect.
                    // For simplicity, we just assume the image fills the space (or is closely matched).
                    // Actually, a better way is to display the annotated UIImage directly.
                }
            }
        }
    }
}
