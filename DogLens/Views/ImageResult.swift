import SwiftUI
import SwiftData

struct ImageResultView: View {

    let image: UIImage
    let results: [DetectionResult]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var breeds: [DogBreed]

    @StateObject private var vm: ResultViewModel

    init(image: UIImage, results: [DetectionResult]) {
        self.image = image
        self.results = results
        _vm = StateObject(
            wrappedValue: ResultViewModel(
                image: image,
                results: results
            )
        )
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
                        let isHigh = result.confidence >= 0.7
                        HStack {
                            Text(result.label)
                                .font(.headline)
                                .fontWeight(isHigh ? .bold : .regular)

                            Spacer()

                            Text(
                                String(
                                    format: "%.1f%%",
                                    result.confidence * 100
                                )
                            )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fontWeight(isHigh ? .bold : .regular)
                        }
                        .padding()
                        .background(isHigh ? Color.orange.opacity(0.12) : Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isHigh ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 1)
                        )
                        .shadow(color: isHigh ? Color.orange.opacity(0.15) : .clear, radius: isHigh ? 6 : 0, x: 0, y: 3)
                    }
                }
                .padding(.horizontal)

                // Actions
                VStack(spacing: 16) {

                    // Only show Breed Gallery option if
                    // at least one detection has confidence >= 70%
                    if results.contains(where: { $0.confidence >= 0.7 }) {

                        VStack(spacing: 6) {

                            if vm.isNewBreed {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.caption)
                                        .foregroundStyle(.orange)

                                    Text("New Breed!")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.orange)

                                    Image(systemName: "sparkles")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                                .transition(
                                    .scale.combined(with: .opacity)
                                )
                            }

                            Button(action: vm.saveToBreedGallery) {
                                HStack(spacing: 8) {

                                    if vm.isNewBreed {
                                        Image(systemName: "star.fill")
                                            .font(.subheadline)
                                    }

                                    Text("Save to Breed Gallery")
                                        .font(.headline)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    vm.isNewBreed
                                    ? LinearGradient(
                                        colors: [.orange, .pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    : LinearGradient(
                                        colors: [.orange, .orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(
                                    color: vm.isNewBreed
                                        ? .orange.opacity(0.5)
                                        : .clear,
                                    radius: 8,
                                    x: 0,
                                    y: 4
                                )
                            }
                            .animation(
                                .easeInOut(duration: 0.3),
                                value: vm.isNewBreed
                            )
                        }
                    }

                    Button(action: vm.saveToPhotos) {
                        Text("Save to Photos")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
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
        .navigationTitle("Image Result")
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
