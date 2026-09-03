//
//  MacScannerView.swift
//  DogLensMac
//

import SwiftUI
import AppKit
import SwiftData
import UniformTypeIdentifiers
import AVFoundation
import Combine

struct MacScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBreeds: [DogBreed]

    // Camera & Live Scanner Services
    @State private var cameraManager = MacCameraManager()
    @StateObject private var liveScannerVM = MacLiveScannerViewModel()

    // Mode States
    @State private var scannerMode: ScannerMode = .photo
    @State private var inputSource: MediaInputSource = .camera
    @State private var isDropTargeted = false

    // Photo Scan State
    @State private var isProcessingPhoto = false
    @State private var originalImage: NSImage?
    @State private var annotatedImage: NSImage?
    @State private var photoDetections: [DetectionResult] = []
    @State private var showOriginalPhoto = false

    // Video Scan State
    @State private var activeVideoVM: MacVideoInferenceViewModel? = nil

    // Feedback & Alerts
    @State private var savedAlertMessage: String?
    @State private var showSavedAlert = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MacScannerHeader(
                    scannerMode: $scannerMode,
                    inputSource: $inputSource,
                    cameraManager: cameraManager,
                    onUploadFile: { openFilePicker() }
                )

                Divider()

                mainContentArea
            }

            if isDropTargeted {
                MacDropOverlayView(isTargeted: isDropTargeted, scannerMode: scannerMode)
            }

            if showSavedAlert, let msg = savedAlertMessage {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: msg.contains("No detections") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(msg.contains("No detections") ? .orange : .green)

                        Text(msg)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)

                        Spacer()

                        Button {
                            withAnimation {
                                showSavedAlert = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(msg.contains("No detections") ? Color.orange.opacity(0.5) : Color.green.opacity(0.5), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showSavedAlert)
                .task {
                    try? await Task.sleep(nanoseconds: 4_500_000_000)
                    withAnimation {
                        showSavedAlert = false
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openFilePicker()
                } label: {
                    Label(
                        scannerMode == .video ? "Upload Video" : "Upload File",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .help(scannerMode == .video ? "Upload and detect dog video from Mac files" : "Upload and detect dog photo from Mac files")
            }
        }
        .onDrop(of: [.image, .movie, .fileURL, .item], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            setupCamera()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: scannerMode) { _, newMode in
            handleModeChange(to: newMode)
        }
        .onChange(of: inputSource) { _, newSource in
            handleInputSourceChange(to: newSource)
        }
    }

    // MARK: - Main Content Area
    @ViewBuilder
    private var mainContentArea: some View {
        switch scannerMode {
        case .photo:
            photoContentView
        case .video:
            videoContentView
        case .live:
            liveContentView
        }
    }

    // MARK: - 1. Photo Mode Content
    private var photoContentView: some View {
        HStack(spacing: 0) {
            VStack {
                if originalImage != nil {
                    MacResultDisplayView(
                        showOriginal: $showOriginalPhoto,
                        originalImage: originalImage,
                        annotatedImage: annotatedImage,
                        onSaveToFile: { triggerSavePhotoToFile() },
                        onScanAnother: { resetPhotoScanState() }
                    )
                } else if inputSource == .camera {
                    MacWebcamZoneView(
                        cameraManager: cameraManager,
                        isProcessing: isProcessingPhoto,
                        onCapture: { Task { await captureAndDetectPhoto() } },
                        onUploadFile: { openFilePicker() }
                    )
                } else {
                    MacDropzoneView(
                        isDropTargeted: isDropTargeted,
                        isProcessing: isProcessingPhoto,
                        onUploadFile: { openFilePicker() },
                        onSwitchToWebcam: { inputSource = .camera }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)

            if originalImage != nil {
                Divider()
                MacDetectionsPanel(
                    detections: photoDetections,
                    allBreeds: allBreeds,
                    onSaveToGallery: { savePhotoToBreedGallery() },
                    onSaveToDevice: { triggerSavePhotoToFile() }
                )
                .frame(width: 340)
            }
        }
    }

    // MARK: - 2. Video Mode Content
    @ViewBuilder
    private var videoContentView: some View {
        if let vm = activeVideoVM {
            MacVideoContainerView(
                vm: vm,
                allBreeds: allBreeds,
                onSaveToGallery: {
                    Task {
                        await vm.saveToBreedGallery(modelContext: modelContext, allBreeds: allBreeds)
                        DispatchQueue.main.async {
                            self.savedAlertMessage = vm.saveMessage
                            withAnimation {
                                self.showSavedAlert = true
                            }
                        }
                    }
                },
                onSaveToFile: { showOriginal in
                    triggerSaveVideoToFile(vm: vm, showOriginal: showOriginal)
                },
                onSaveToPhotos: {
                    vm.saveToPhotos()
                    DispatchQueue.main.async {
                        self.savedAlertMessage = "Video successfully saved to Photos."
                        withAnimation {
                            self.showSavedAlert = true
                        }
                    }
                },
                onScanAnother: {
                    resetVideoScanState()
                }
            )
        } else {
            VStack {
                MacVideoZoneView(
                    inputSource: inputSource,
                    cameraManager: cameraManager,
                    isDropTargeted: isDropTargeted,
                    isInferring: false,
                    inferenceProgress: 0.0,
                    onStartRecording: { startWebcamRecording() },
                    onStopRecording: { stopWebcamRecording() },
                    onUploadFile: { openFilePicker() },
                    onSwitchToCamera: { inputSource = .camera }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    // MARK: - 3. Live Scanner Mode Content
    private var liveContentView: some View {
        VStack {
            MacLiveScannerOverlayView(
                cameraManager: cameraManager,
                liveViewModel: liveScannerVM
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Camera Lifecycle Handlers
    private func setupCamera() {
        cameraManager.setup()
        if (scannerMode == .live || inputSource == .camera) && activeVideoVM == nil && originalImage == nil {
            cameraManager.startSession()
        }
    }

    private func handleModeChange(to newMode: ScannerMode) {
        if newMode == .live {
            cameraManager.startSession()
        } else if inputSource == .camera && activeVideoVM == nil && originalImage == nil {
            cameraManager.startSession()
        } else {
            cameraManager.stopSession()
        }
    }

    private func handleInputSourceChange(to newSource: MediaInputSource) {
        if (scannerMode == .live || newSource == .camera) && activeVideoVM == nil && originalImage == nil {
            cameraManager.startSession()
        } else {
            cameraManager.stopSession()
        }
    }

    // MARK: - Photo Detection Logic
    private func resetPhotoScanState() {
        withAnimation {
            originalImage = nil
            annotatedImage = nil
            photoDetections = []
        }
        if inputSource == .camera {
            cameraManager.startSession()
        }
    }

    private func captureAndDetectPhoto() async {
        isProcessingPhoto = true
        do {
            let photo = try await cameraManager.capturePhoto()
            cameraManager.stopSession()
            await runPhotoDetection(on: photo)
        } catch {
            print("Capture failed: \(error)")
            isProcessingPhoto = false
        }
    }

    private func runPhotoDetection(on image: NSImage) async {
        isProcessingPhoto = true
        do {
            let results = try await MacModelService.shared.detectDogs(in: image)
            let annotated = MacModelService.shared.renderAnnotatedImage(image: image, detections: results)

            withAnimation {
                self.originalImage = image
                self.annotatedImage = annotated
                self.photoDetections = results
                self.isProcessingPhoto = false
            }
        } catch {
            print("Detection error: \(error)")
            withAnimation {
                self.originalImage = image
                self.annotatedImage = nil
                self.photoDetections = []
                self.isProcessingPhoto = false
            }
        }
    }

    private func savePhotoToBreedGallery() {
        guard let origImg = originalImage else { return }
        do {
            let savedNames = try MacGallerySaver.saveEligibleDetections(
                originalImage: origImg,
                annotatedImage: annotatedImage,
                detections: photoDetections,
                modelContext: modelContext
            )
            if savedNames.isEmpty {
                savedAlertMessage = "No detections with ≥ 70% confidence to save."
            } else {
                let namesList = savedNames.joined(separator: ", ")
                savedAlertMessage = "Saved \(namesList) to your Breed Gallery and synced with iCloud."
            }
            showSavedAlert = true
        } catch {
            print("Failed to save to gallery: \(error)")
        }
    }

    private func triggerSavePhotoToFile() {
        let targetImg = showOriginalPhoto ? originalImage : (annotatedImage ?? originalImage)
        guard let img = targetImg else { return }
        let defaultBreed = photoDetections.first?.label.replacingOccurrences(of: " ", with: "_") ?? "Dog"
        let filename = "DogLens_\(defaultBreed)_\(showOriginalPhoto ? "Original" : "Detection").jpg"

        MacFileExporter.saveImage(image: img, defaultName: filename) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    self.savedAlertMessage = "Photo successfully saved to:\n\(url.path)"
                    self.showSavedAlert = true
                case .failure(let error):
                    print("Failed to save image to file: \(error)")
                }
            }
        }
    }

    // MARK: - Video Detection Logic
    private func resetVideoScanState() {
        withAnimation {
            activeVideoVM = nil
        }
        if inputSource == .camera && scannerMode == .video {
            cameraManager.startSession()
        }
    }

    private func startWebcamRecording() {
        cameraManager.startRecordingVideo { result in
            switch result {
            case .success(let url):
                Task { @MainActor in
                    self.processVideoURL(url)
                }
            case .failure(let error):
                print("Recording failed: \(error)")
            }
        }
    }

    private func stopWebcamRecording() {
        cameraManager.stopRecordingVideo()
    }

    private func processVideoURL(_ url: URL) {
        cameraManager.stopSession()
        withAnimation {
            self.scannerMode = .video
            self.inputSource = .file
            let vm = MacVideoInferenceViewModel(videoURL: url)
            self.activeVideoVM = vm
            Task {
                await vm.runInference()
            }
        }
    }

    private func triggerSaveVideoToFile(vm: MacVideoInferenceViewModel, showOriginal: Bool) {
        let targetURL = (showOriginal ? nil : vm.annotatedVideoURL) ?? vm.sourceURL
        let defaultBreed = vm.trackedDogs.first?.breedName.replacingOccurrences(of: " ", with: "_")
            ?? vm.allVideoDetections.keys.first?.replacingOccurrences(of: " ", with: "_")
            ?? "Dog"
        let filename = "DogLens_\(defaultBreed)_\(showOriginal ? "Original" : "Detection").mp4"

        MacFileExporter.saveVideo(sourceURL: targetURL, defaultName: filename) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let destURL):
                    self.savedAlertMessage = "Video successfully saved to:\n\(destURL.path)"
                    self.showSavedAlert = true
                case .failure(let error):
                    print("Failed to save video: \(error)")
                }
            }
        }
    }

    // MARK: - File Picker & Drop Handlers
    private func copySecurityScopedURLToTemp(url: URL) -> URL? {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("doglens_input_\(UUID().uuidString)")
            .appendingPathExtension(ext)

        do {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: url, to: tempURL)
            return tempURL
        } catch {
            print("Failed to copy security scoped file: \(error)")
            return url
        }
    }

    private func loadImageFromURL(_ url: URL) -> NSImage? {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
            return img
        }
        if let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        if scannerMode == .video {
            panel.title = "Select Dog Video"
            panel.message = "Choose a video to scan with DogLens"
            panel.prompt = "Choose Video"
            panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        } else {
            panel.title = "Select Dog Photo"
            panel.message = "Choose an image to scan with DogLens"
            panel.prompt = "Choose Image"
            panel.allowedContentTypes = [.jpeg, .png, .heic]
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let ext = url.pathExtension.lowercased()
            let isVideoExt = ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext) || self.scannerMode == .video

            if isVideoExt {
                let safeURL = self.copySecurityScopedURLToTemp(url: url)
                DispatchQueue.main.async {
                    if let target = safeURL {
                        self.processVideoURL(target)
                    }
                }
            } else {
                let img = self.loadImageFromURL(url)
                DispatchQueue.main.async {
                    if let image = img {
                        self.scannerMode = .photo
                        self.inputSource = .file
                        Task { @MainActor in
                            await self.runPhotoDetection(on: image)
                        }
                    }
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // 1. Try loading as URL (File URL from Finder / Desktop / Downloads)
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
            provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ||
            provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {

            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else {
                    self.loadDroppedImageDirectly(provider: provider)
                    return
                }

                let ext = url.pathExtension.lowercased()
                let isVideoExt = ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext)

                if isVideoExt {
                    let safeURL = self.copySecurityScopedURLToTemp(url: url)
                    DispatchQueue.main.async {
                        self.scannerMode = .video
                        self.inputSource = .file
                        if let target = safeURL {
                            self.processVideoURL(target)
                        }
                    }
                } else {
                    let loadedImage = self.loadImageFromURL(url)
                    DispatchQueue.main.async {
                        if let img = loadedImage {
                            self.scannerMode = .photo
                            self.inputSource = .file
                            Task { @MainActor in
                                await self.runPhotoDetection(on: img)
                            }
                        } else {
                            self.loadDroppedImageDirectly(provider: provider)
                        }
                    }
                }
            }
            return true
        }

        // 2. Direct Image Provider Fallback (e.g. dragged from Photos, Safari, Clipboard)
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            loadDroppedImageDirectly(provider: provider)
            return true
        }

        return false
    }

    private func loadDroppedImageDirectly(provider: NSItemProvider) {
        _ = provider.loadObject(ofClass: NSImage.self) { img, _ in
            guard let img = img as? NSImage else { return }
            DispatchQueue.main.async {
                self.scannerMode = .photo
                self.inputSource = .file
                Task { @MainActor in
                    await self.runPhotoDetection(on: img)
                }
            }
        }
    }
}
