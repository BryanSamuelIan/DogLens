import SwiftUI
import SwiftData

struct ResultView: View {
    let image: UIImage
    let results: [DetectionResult]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var breeds: [DogBreed]

    @StateObject private var vm: ResultViewModel

    init(image: UIImage, results: [DetectionResult]) {
        self.image = image
        self.results = results
        _vm = StateObject(wrappedValue: ResultViewModel(image: image, results: results))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // View Mode Picker
                Picker("View Mode", selection: $vm.showOriginal) {
                    Text("Detection").tag(false)
                    Text("Original").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Image Display
                Image(uiImage: vm.displayImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 400)
                    .cornerRadius(16)
                    .padding(.horizontal)

                // Detection Results
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
                    Button(action: vm.saveToPhotos) {
                        Text("Save to Photos")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(16)
                    }

                    Button(action: vm.saveToBreedGallery) {
                        Text("Save to Breed Gallery")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(16)
                    }

                    Button(action: { dismiss() }) {
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
        .onAppear {
            vm.modelContext = modelContext
            vm.breeds = breeds
        }
        .onChange(of: breeds) { _, newBreeds in
            vm.breeds = newBreeds
        }
        .alert("Save Result", isPresented: $vm.showingSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(vm.saveMessage)
        }
    }
}
