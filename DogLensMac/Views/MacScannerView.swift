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
    @StateObject private var videoInferenceVMHolder = VideoInferenceHolder()

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
        .onDrop(of: [.image, .movie, .fileURL], isTargeted: $isDropTargeted) { providers in
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
        .onChange(of: scannerMode) { _, newMode in
            handleModeChange(to: newMode)
        }
        .onChange(of: inputSource) { _, newSource in
            handleInputSourceChange(to: newSource)
        }
        .alert("Notice", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(savedAlertMessage ?? "")
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
        if let vm = videoInferenceVMHolder.vm, vm.annotatedVideoURL != nil {
            MacVideoResultView(
                vm: vm,
                allBreeds: allBreeds,
                onSaveToGallery: {
                    vm.saveToBreedGallery(modelContext: modelContext, allBreeds: allBreeds)
                },
                onSaveToFile: { showOriginal in
                    triggerSaveVideoToFile(vm: vm, showOriginal: showOriginal)
                },
                onSaveToPhotos: {
                    vm.saveToPhotos()
                },
                onScanAnother: {
                    resetVideoScanState()
                }
            )
        } else {
            VStack {
                let isInferring = videoInferenceVMHolder.vm?.isInferring ?? false
                let progress = videoInferenceVMHolder.vm?.progress ?? 0.0

                MacVideoZoneView(
                    inputSource: inputSource,
                    cameraManager: cameraManager,
                    isDropTargeted: isDropTargeted,
                    isInferring: isInferring,
                    inferenceProgress: progress,
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
        if scannerMode == .live || inputSource == .camera {
            cameraManager.startSession()
        }
    }

    private func handleModeChange(to newMode: ScannerMode) {
        if newMode == .live {
            cameraManager.startSession()
        } else if inputSource == .camera {
            cameraManager.startSession()
        } else {
            cameraManager.stopSession()
        }
    }

    private func handleInputSourceChange(to newSource: MediaInputSource) {
        if scannerMode == .live || newSource == .camera {
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
    }

    private func captureAndDetectPhoto() async {
        isProcessingPhoto = true
        do {
            let photo = try await cameraManager.capturePhoto()
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
            videoInferenceVMHolder.vm = nil
        }
        if inputSource == .camera {
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
        let vm = MacVideoInferenceViewModel(videoURL: url)
        self.videoInferenceVMHolder.vm = vm
        Task {
            await vm.runInference()
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

            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if self.scannerMode == .video {
                self.processVideoURL(url)
            } else {
                guard let data = try? Data(contentsOf: url),
                      let image = NSImage(data: data) else { return }
                Task { @MainActor in
                    await self.runPhotoDetection(on: image)
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }

                let ext = url.pathExtension.lowercased()
                let isVideoExt = ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext)

                DispatchQueue.main.async {
                    if isVideoExt {
                        self.scannerMode = .video
                        self.processVideoURL(url)
                    } else if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
                        self.scannerMode = .photo
                        Task { @MainActor in
                            await self.runPhotoDetection(on: img)
                        }
                    }
                }
            }
            return true
        } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    self.scannerMode = .video
                    self.processVideoURL(url)
                }
            }
            return true
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            _ = provider.loadObject(ofClass: NSImage.self) { img, _ in
                guard let img = img as? NSImage else { return }
                DispatchQueue.main.async {
                    self.scannerMode = .photo
                    Task { @MainActor in
                        await self.runPhotoDetection(on: img)
                    }
                }
            }
            return true
        }

        return false
    }
}

// MARK: - State Holder for Observable Object
final class VideoInferenceHolder: ObservableObject {
    @Published var vm: MacVideoInferenceViewModel?
}
