//
//  MacScannerView.swift
//  DogLensMac
//

import SwiftUI
import AppKit
import SwiftData
import UniformTypeIdentifiers
import AVFoundation

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
                MacScannerHeader(
                    inputMode: $inputMode,
                    cameraManager: cameraManager,
                    onUploadFile: { openFilePicker() }
                )
                Divider()
                mainContentArea
            }

            if isDropTargeted {
                MacDropOverlayView(isTargeted: isDropTargeted)
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

    // MARK: - Main Content Area
    private var mainContentArea: some View {
        HStack(spacing: 0) {
            VStack {
                if originalImage != nil {
                    MacResultDisplayView(
                        showOriginal: $showOriginal,
                        originalImage: originalImage,
                        annotatedImage: annotatedImage,
                        onSaveToFile: { triggerSaveToFile() },
                        onScanAnother: { resetScanState() }
                    )
                } else if inputMode == .webcam {
                    MacWebcamZoneView(
                        cameraManager: cameraManager,
                        isProcessing: isProcessing,
                        onCapture: { Task { await captureAndDetect() } },
                        onUploadFile: { openFilePicker() }
                    )
                } else {
                    MacDropzoneView(
                        isDropTargeted: isDropTargeted,
                        isProcessing: isProcessing,
                        onUploadFile: { openFilePicker() },
                        onSwitchToWebcam: { inputMode = .webcam }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)

            if originalImage != nil {
                Divider()
                MacDetectionsPanel(
                    detections: detections,
                    allBreeds: allBreeds,
                    onSaveToGallery: { saveToBreedGallery() },
                    onSaveToDevice: { triggerSaveToFile() }
                )
                .frame(width: 340)
            }
        }
    }

    // MARK: - Actions & Handlers
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

    private func resetScanState() {
        withAnimation {
            originalImage = nil
            annotatedImage = nil
            detections = []
        }
    }

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

    private func saveToBreedGallery() {
        guard let origImg = originalImage else { return }
        do {
            let savedNames = try MacGallerySaver.saveEligibleDetections(
                originalImage: origImg,
                annotatedImage: annotatedImage,
                detections: detections,
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

    private func triggerSaveToFile() {
        let targetImg = showOriginal ? originalImage : (annotatedImage ?? originalImage)
        guard let img = targetImg else { return }
        let defaultBreed = detections.first?.label.replacingOccurrences(of: " ", with: "_") ?? "Dog"
        let filename = "DogLens_\(defaultBreed)_\(showOriginal ? "Original" : "Detection").jpg"

        MacFileExporter.saveImage(image: img, defaultName: filename) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    self.savedAlertMessage = "Image successfully saved to:\n\(url.path)"
                    self.showSavedAlert = true
                case .failure(let error):
                    print("Failed to save image to file: \(error)")
                }
            }
        }
    }
}

