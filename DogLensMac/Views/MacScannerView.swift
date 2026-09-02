import SwiftUI
import AppKit
import SwiftData
import UniformTypeIdentifiers
import AVFoundation

enum InputMode: String, CaseIterable, Identifiable {
    case webcam = "Live Camera"
    case fileDrop = "Upload / Drop Image"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .webcam: return "camera.fill"
        case .fileDrop: return "photo.on.rectangle.angled"
        }
    }
}

struct MacScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBreeds: [DogBreed]
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
                topHeaderBar
                Divider()
                mainContentArea
            }

            if isDropTargeted {
                dropOverlay
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
        .task {
            await MacCloudKitService.shared.syncFromCloud(modelContext: modelContext)
        }
        .onAppear {
            setupCamera()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: inputMode) { _, newMode in
            handleInputModeChange(to: newMode)
        }
        .alert("Notice", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(savedAlertMessage ?? "")
        }
    }

    // MARK: - Top Header Bar
    private var topHeaderBar: some View {
        HStack(spacing: 16) {
            Picker("Mode", selection: $inputMode) {
                ForEach(InputMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .tint(.orange)

            Button {
                openFilePicker()
            } label: {
                Label("Upload from File…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)

            Spacer()

            if inputMode == .webcam && !cameraManager.availableDevices.isEmpty {
                cameraDeviceMenu
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var cameraDeviceMenu: some View {
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
            let activeName = cameraManager.availableDevices.first(where: { $0.id == cameraManager.selectedDeviceID })?.name ?? "Select Camera"
            Label(activeName, systemImage: "video.fill")
        }
        .menuStyle(.borderedButton)
    }

    // MARK: - Main Content Area
    private var mainContentArea: some View {
        HStack(spacing: 0) {
            VStack {
                if originalImage != nil {
                    resultImageDisplay
                } else if inputMode == .webcam {
                    webcamPreviewZone
                } else {
                    dropzoneArea
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)

            if originalImage != nil {
                Divider()
                detectionsSidePanel
                    .frame(width: 340)
            }
        }
    }

    // MARK: - Drop Overlay
    private var dropOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, dash: [10]))
                .background(Color.orange.opacity(0.12))
                .padding(24)

            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)

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

    private func setupCamera() {
        cameraManager.setup()
        if inputMode == .webcam {
            cameraManager.startSession()
        }
    }

    private func handleInputModeChange(to newMode: InputMode) {
        if newMode == .webcam {
            cameraManager.startSession()
        } else {
            cameraManager.stopSession()
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
                                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.85))
                        .overlay {
                            VStack(spacing: 14) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 42))
                                    .foregroundColor(.orange.opacity(0.85))

                                if cameraManager.authorizationStatus == .authorized {
                                    VStack(spacing: 6) {
                                        ProgressView()
                                            .tint(.orange)
                                        Text("Starting Camera…")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                    }
                                } else if cameraManager.authorizationStatus == .denied {
                                    VStack(spacing: 8) {
                                        Text("Camera Access Denied")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Text("Please enable camera access in macOS System Settings.")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.7))
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 20)

                                        Button("Open System Settings") {
                                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                                NSWorkspace.shared.open(url)
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.orange)
                                        .padding(.top, 4)
                                    }
                                } else {
                                    VStack(spacing: 8) {
                                        Text("Camera Access Required")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Text("DogLens needs camera access to scan and identify dogs in real time.")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.7))
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 20)

                                        Button("Allow Camera Access") {
                                            cameraManager.startSession()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.orange)
                                        .padding(.top, 4)
                                    }
                                }
                            }
                            .padding(24)
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
                        Image(systemName: "camera.fill")
                            .font(.title3)
                        Text("Scan Dog")
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .frame(minWidth: 180, minHeight: 40)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isProcessing || !cameraManager.isRunning)

                Button {
                    openFilePicker()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Upload Photo…")
                    }
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Dropzone Area (iOS DogLens Aesthetic)
    private var dropzoneArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isDropTargeted ? Color.orange : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(isDropTargeted ? Color.orange.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.4))
                )

            VStack(spacing: 22) {
                // iOS App Logo / Viewfinder
                Image(systemName: "viewfinder.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.orange, .blue.opacity(0.8))

                VStack(spacing: 8) {
                    Text("Identify Dogs with DogLens")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Drag & drop photos or select from your Mac to detect 52 dog breeds")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

                HStack(spacing: 14) {
                    Button {
                        openFilePicker()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Upload Photo")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        inputMode = .webcam
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                            Text("Live Camera")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
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
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    // MARK: - Result Image Display
    private var resultImageDisplay: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Picker("", selection: $showOriginal) {
                    Text("Detection").tag(false)
                    Text("Original").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
                .tint(.orange)

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
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button {
                    withAnimation {
                        originalImage = nil
                        annotatedImage = nil
                        detections = []
                    }
                } label: {
                    Label("Scan Another", systemImage: "arrow.counterclockwise")
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

    private var hasEligibleDetection: Bool {
        detections.contains(where: { $0.confidence >= 0.7 })
    }

    private var isNewBreedDetected: Bool {
        detections.contains { result in
            result.confidence >= 0.7 && isNewBreed(name: result.label)
        }
    }

    // MARK: - Detections Side Panel
    private var detectionsSidePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "pawprint.fill")
                    .foregroundColor(.orange)
                Text("Detection Results")
                    .font(.headline)
                Spacer()
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
                        .font(.system(size: 40))
                        .foregroundColor(.orange.opacity(0.6))
                    Text("No dog breed recognized.")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("We couldn't find any dogs in this image. Make sure the dog is clearly visible and try again.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 16)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        // 1. List of all detected breeds with percentages
                        ForEach(detections) { item in
                            let isHigh = item.confidence >= 0.7
                            let isNew = isNewBreed(name: item.label)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(item.label)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("\(Int(item.confidence * 100))%")
                                        .font(.subheadline)
                                        .fontWeight(isHigh ? .bold : .medium)
                                        .foregroundColor(isHigh ? .orange : .secondary)
                                }

                                ProgressView(value: Double(item.confidence), total: 1.0)
                                    .tint(isHigh ? .orange : .secondary)

                                if isHigh && isNew {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sparkles")
                                            .font(.caption2)
                                        Text("New Breed!")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                    }
                                    .foregroundColor(.orange)
                                    .padding(.top, 2)
                                }
                            }
                            .padding(12)
                            .background(isHigh ? Color.orange.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isHigh ? Color.orange.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: isHigh ? 1.5 : 1)
                            )
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // 2. Actions (Per-Image, matching iOS concept)
                        VStack(spacing: 10) {
                            // Only show Breed Gallery option if at least one detection has confidence >= 70%
                            if hasEligibleDetection {
                                if isNewBreedDetected {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sparkles")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                        Text("New Breed Discovered!")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.orange)
                                        Image(systemName: "sparkles")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.15))
                                    .clipShape(Capsule())
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }

                                Button {
                                    saveAllEligibleDetectionsToGallery()
                                } label: {
                                    HStack(spacing: 6) {
                                        if isNewBreedDetected {
                                            Image(systemName: "star.fill")
                                                .font(.subheadline)
                                        } else {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.subheadline)
                                        }
                                        Text("Save to Breed Gallery")
                                            .font(.headline)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        isNewBreedDetected
                                        ? LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)
                                        : LinearGradient(colors: [.orange, .orange], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .shadow(
                                        color: isNewBreedDetected ? .orange.opacity(0.5) : .clear,
                                        radius: 8,
                                        x: 0,
                                        y: 4
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            // Save to Device / Photos Button (Always Available)
                            Button {
                                let defaultBreed = detections.first?.label.replacingOccurrences(of: " ", with: "_") ?? "Dog"
                                let filename = "DogLens_\(defaultBreed)_\(showOriginal ? "Original" : "Detection").jpg"
                                let targetImage = showOriginal ? originalImage : (annotatedImage ?? originalImage)
                                if let img = targetImage {
                                    saveImageToFile(image: img, defaultName: filename)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down.doc.fill")
                                    Text("Save to Device…")
                                        .font(.headline)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
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
                if let url = url {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
                        DispatchQueue.main.async {
                            Task { @MainActor in
                                await self.runDetection(on: img)
                            }
                        }
                    }
                }
            }
            return true
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            _ = provider.loadObject(ofClass: NSImage.self) { img, _ in
                if let img = img as? NSImage {
                    DispatchQueue.main.async {
                        Task { @MainActor in
                            await self.runDetection(on: img)
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

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data) else {
                return
            }

            Task { @MainActor in
                await self.runDetection(on: image)
            }
        }
    }

    private func isNewBreed(name: String) -> Bool {
        guard let breed = allBreeds.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return true
        }
        return breed.imageCount == 0
    }

    private func saveAllEligibleDetectionsToGallery() {
        guard let origImg = originalImage, let origData = origImg.jpegData else { return }
        let annData = annotatedImage?.jpegData
        let eligible = detections.filter { $0.confidence >= 0.7 }
        guard !eligible.isEmpty else {
            savedAlertMessage = "No detections with ≥ 70% confidence to save."
            showSavedAlert = true
            return
        }

        do {
            let descriptor = FetchDescriptor<DogBreed>()
            let allBreeds = try modelContext.fetch(descriptor)
            var savedBreedNames: [String] = []

            for item in eligible {
                let breedName = item.label
                let breed: DogBreed
                if let existing = allBreeds.first(where: { $0.name.caseInsensitiveCompare(breedName) == .orderedSame }) {
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
                    confidence: Double(item.confidence),
                    breed: breed
                )

                modelContext.insert(breedImage)
                breed.images.append(breedImage)
                savedBreedNames.append(breed.name)

                // Automatic 2-way background iCloud sync
                Task {
                    await MacCloudKitService.shared.uploadBreedImage(breedImage, breedName: breed.name)
                }
            }

            try modelContext.save()
            let namesList = savedBreedNames.joined(separator: ", ")
            savedAlertMessage = "Saved \(namesList) to your Breed Gallery and synced with iCloud."
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

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if let data = image.jpegData {
                do {
                    try data.write(to: url)
                    DispatchQueue.main.async {
                        self.savedAlertMessage = "Image successfully saved to:\n\(url.path)"
                        self.showSavedAlert = true
                    }
                } catch {
                    print("Failed to save image to file: \(error)")
                }
            }
        }
    }
}
