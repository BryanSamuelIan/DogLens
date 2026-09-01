import SwiftUI
import AppKit
import SwiftData
import UniformTypeIdentifiers

enum InputMode: String, CaseIterable, Identifiable {
    case webcam = "Live Camera"
    case fileDrop = "Upload / Drop Image"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .webcam: return "camera.fill"
        case .fileDrop: return "arrow.down.doc.fill"
        }
    }
}

struct MacScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var cameraManager = MacCameraManager()
    @State private var inputMode: InputMode = .fileDrop

    @State private var isDropTargeted = false
    @State private var isProcessing = false
    @State private var originalImage: NSImage?
    @State private var annotatedImage: NSImage?
    @State private var detections: [DetectionResult] = []
    @State private var showOriginal = false

    @State private var savedAlertMessage: String?
    @State private var showSavedAlert = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Top Header Bar
                HStack(spacing: 16) {
                    Picker("Mode", selection: $inputMode) {
                        ForEach(InputMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 340)

                    Button {
                        openFilePicker()
                    } label: {
                        Label("Upload from File…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if inputMode == .webcam && !cameraManager.availableDevices.isEmpty {
                        Menu {
                            ForEach(cameraManager.availableDevices) { dev in
                                Button {
                                    cameraManager.selectDevice(id: dev.id)
                                } label: {
                                    HStack {
                                        Text(dev.name)
                                        if dev.id == cameraManager.selectedDeviceID {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(
                                cameraManager.availableDevices.first(where: { $0.id == cameraManager.selectedDeviceID })?.name ?? "Select Camera",
                                systemImage: "video.fill"
                            )
                        }
                        .menuStyle(.borderedButton)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Main Content Area
                HStack(spacing: 0) {
                    // Left: Input / Preview Zone
                    VStack {
                        if let _ = originalImage {
                            resultImageDisplay
                        } else {
                            if inputMode == .webcam {
                                webcamPreviewZone
                            } else {
                                dropzoneArea
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)

                    // Right: Detections & Actions Panel
                    if originalImage != nil {
                        Divider()
                        detectionsSidePanel
                            .frame(width: 340)
                    }
                }
            }

            // Global Drag & Drop Highlight Overlay
            if isDropTargeted {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, dash: [10]))
                        .background(Color.blue.opacity(0.15))
                        .padding(24)

                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.blue)

                        Text("Drop Image to Scan & Detect Dogs")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Supports JPG, PNG, and HEIC files")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openFilePicker()
                } label: {
                    Label("Upload from File", systemImage: "square.and.arrow.up")
                }
                .help("Upload and detect dog image from Mac files")
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            cameraManager.setup()
            if inputMode == .webcam {
                cameraManager.startSession()
            }
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: inputMode) { _, newMode in
            if newMode == .webcam {
                cameraManager.startSession()
            } else {
                cameraManager.stopSession()
            }
        }
        .alert("Notice", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(savedAlertMessage ?? "")
        }
    }

    // MARK: - Webcam Preview Zone
    private var webcamPreviewZone: some View {
        VStack(spacing: 16) {
            ZStack {
                if cameraManager.isRunning {
                    MacCameraPreviewView(session: cameraManager.session)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.85))
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("Starting Camera…")
                                    .foregroundColor(.secondary)
                            }
                        }
                }

                if isProcessing {
                    ZStack {
                        Color.black.opacity(0.5)
                        ProgressView("Analyzing image with CoreML…")
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .foregroundColor(.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            HStack(spacing: 14) {
                Button {
                    Task {
                        await captureAndDetect()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.shutter.button.fill")
                            .font(.title3)
                        Text("Capture & Detect")
                            .fontWeight(.semibold)
                    }
                    .frame(minWidth: 180, minHeight: 38)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isProcessing || !cameraManager.isRunning)

                Button {
                    openFilePicker()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                        Text("Upload Image File…")
                    }
                    .frame(minHeight: 38)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Dropzone Area (Rectangle for Drag & Drop)
    private var dropzoneArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isDropTargeted ? Color.blue : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 2, dash: [10])
                )
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isDropTargeted ? Color.blue.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.5))
                )

            VStack(spacing: 20) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 56))
                    .foregroundColor(isDropTargeted ? .blue : .secondary)

                VStack(spacing: 8) {
                    Text("Drag & Drop Image Here")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Drop any dog photo directly from Finder, Desktop, or Photos")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text("— OR —")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Button {
                    openFilePicker()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.headline)
                        Text("Choose File from Mac…")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
            }
            .padding(40)

            if isProcessing {
                ZStack {
                    Color.black.opacity(0.5)
                    ProgressView("Analyzing image with CoreML…")
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .foregroundColor(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    // MARK: - Result Image Display
    private var resultImageDisplay: some View {
        VStack(spacing: 14) {
            HStack {
                Picker("View", selection: $showOriginal) {
                    Text("Detection").tag(false)
                    Text("Original").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()

                // Save to File Button (NSSavePanel)
                Button {
                    let defaultBreed = detections.first?.label.replacingOccurrences(of: " ", with: "_") ?? "Dog"
                    let filename = "DogLens_\(defaultBreed)_\(showOriginal ? "Original" : "Detection").jpg"
                    let targetImage = showOriginal ? originalImage : (annotatedImage ?? originalImage)
                    if let img = targetImage {
                        saveImageToFile(image: img, defaultName: filename)
                    }
                } label: {
                    Label("Save to File…", systemImage: "arrow.down.doc.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    withAnimation {
                        originalImage = nil
                        annotatedImage = nil
                        detections = []
                    }
                } label: {
                    Label("Scan Another Image", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }

            ZStack {
                Color.black.opacity(0.04)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                let displayImg = showOriginal ? originalImage : (annotatedImage ?? originalImage)
                if let img = displayImg {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                }
            }
        }
    }

    // MARK: - Detections Side Panel
    private var detectionsSidePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Detection Results")
                    .font(.headline)
                Text("\(detections.count) dog\(detections.count == 1 ? "" : "s") detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            .padding(.horizontal, 16)

            if detections.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No dog breed recognized with high confidence.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(detections) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(item.label)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("\(Int(item.confidence * 100))%")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }

                                ProgressView(value: Double(item.confidence), total: 1.0)
                                    .tint(.blue)

                                Button {
                                    saveDetectionToGallery(breedName: item.label, confidence: Double(item.confidence))
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Save to Breed Gallery")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            Spacer()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Actions
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, let img = NSImage(contentsOf: url) {
                    DispatchQueue.main.async {
                        Task {
                            await runDetection(on: img)
                        }
                    }
                }
            }
            return true
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            _ = provider.loadObject(ofClass: NSImage.self) { img, _ in
                if let img = img as? NSImage {
                    DispatchQueue.main.async {
                        Task {
                            await runDetection(on: img)
                        }
                    }
                }
            }
            return true
        }
        return false
    }

    private func captureAndDetect() async {
        isProcessing = true
        do {
            let photo = try await cameraManager.capturePhoto()
            await runDetection(on: photo)
        } catch {
            print("Capture failed: \(error)")
            isProcessing = false
        }
    }

    private func runDetection(on image: NSImage) async {
        isProcessing = true
        do {
            let results = try await MacModelService.shared.detectDogs(in: image)
            let annotated = MacModelService.shared.renderAnnotatedImage(image: image, detections: results)

            withAnimation {
                self.originalImage = image
                self.annotatedImage = annotated
                self.detections = results
                self.isProcessing = false
            }
        } catch {
            print("Detection error: \(error)")
            withAnimation {
                self.originalImage = image
                self.annotatedImage = nil
                self.detections = []
                self.isProcessing = false
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Select Dog Photo"
        panel.message = "Choose an image to scan with DogLens"
        panel.prompt = "Choose Image"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.jpeg, .png, .heic]

        // Open in modal or sheet
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            Task {
                await runDetection(on: image)
            }
        }
    }

    private func saveDetectionToGallery(breedName: String, confidence: Double) {
        guard let origImg = originalImage, let origData = origImg.jpegData else { return }
        let annData = annotatedImage?.jpegData

        do {
            let descriptor = FetchDescriptor<DogBreed>()
            let allBreeds = try modelContext.fetch(descriptor)
            let breed: DogBreed

            if let existing = allBreeds.first(where: { $0.name.lowercased() == breedName.lowercased() }) {
                breed = existing
            } else {
                let newBreed = DogBreed(name: breedName)
                modelContext.insert(newBreed)
                breed = newBreed
            }

            let breedImage = BreedImage(
                imageData: origData,
                annotatedImageData: annData,
                isVideo: false,
                detectionDate: Date(),
                confidence: confidence,
                breed: breed
            )

            modelContext.insert(breedImage)
            breed.images.append(breedImage)
            try modelContext.save()

            // Background iCloud sync
            Task {
                await MacCloudKitService.shared.uploadBreedImage(breedImage, breedName: breed.name)
            }

            savedAlertMessage = "Saved \(breedName) to your Breed Gallery and syncing with iCloud."
            showSavedAlert = true
        } catch {
            print("Failed to save to gallery: \(error)")
        }
    }

    // MARK: - Save Image to File via NSSavePanel (Default: ~/Downloads)
    private func saveImageToFile(image: NSImage, defaultName: String) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Image to File"
        savePanel.message = "Choose where to save the photo on your Mac"
        savePanel.prompt = "Save Image"
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.nameFieldStringValue = defaultName
        savePanel.allowedContentTypes = [.jpeg, .png]

        // Set default directory to ~/Downloads
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloadsURL
        }

        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let data = image.jpegData {
                do {
                    try data.write(to: url)
                    savedAlertMessage = "Image successfully saved to:\n\(url.path)"
                    showSavedAlert = true
                } catch {
                    print("Failed to save image to file: \(error)")
                }
            }
        }
    }
}
