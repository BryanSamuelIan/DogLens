//
//  MacVideoInferenceViewModel.swift
//  DogLensMac
//

import SwiftUI
import AppKit
import AVFoundation
import Photos
import SwiftData
import Combine

@MainActor
final class MacVideoInferenceViewModel: ObservableObject {

    // MARK: - Published State
    @Published var isInferring = false
    @Published var progress: Double = 0.0          // 0…1
    @Published var annotatedVideoURL: URL?
    @Published var errorMessage: String?
    @Published var showingSaveAlert = false
    @Published var saveMessage = ""
    @Published var isSavingToPhotos = false
    @Published var isSavingToGallery = false
    @Published var trackedDogs: [TrackedDogSummary] = []
    @Published var breeds: [DogBreed] = []

    // MARK: - Best Frame (for Breed Gallery Thumbnail)
    private(set) var bestAnnotatedFrame: NSImage?
    private(set) var bestOriginalFrame: NSImage?
    private(set) var bestFrameResults: [DetectionResult] = []

    // MARK: - Config
    let sourceURL: URL
    private let targetFPS: Double = 15.0

    // MARK: - All Detected Breeds Across Video (Breed Name -> Highest Confidence)
    @Published private(set) var allVideoDetections: [String: Double] = [:]

    init(videoURL: URL) {
        self.sourceURL = videoURL
    }

    // Returns true if ANY detected breed (with confidence >= 0.70) has never been saved to gallery before
    var isNewBreed: Bool {
        allVideoDetections.contains { name, conf in
            guard conf >= 0.70 else { return false }
            if let match = breeds.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return match.images.isEmpty
            }
            return true
        }
    }

    // MARK: - Run Inference
    func runInference() async {
        isInferring = true
        progress = 0
        annotatedVideoURL = nil
        bestAnnotatedFrame = nil
        bestOriginalFrame = nil
        bestFrameResults = []
        allVideoDetections = [:]
        trackedDogs = []
        errorMessage = nil

        do {
            let url = try await processVideo()
            self.annotatedVideoURL = url
        } catch {
            self.errorMessage = "Inference failed: \(error.localizedDescription)"
        }

        isInferring = false
    }

    // MARK: - Streaming Pipeline: Memory-Efficient Single Pass Processing
    private func processVideo() async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let rawDurationSec = CMTimeGetSeconds(duration)

        guard rawDurationSec > 0 else {
            throw NSError(domain: "VideoError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid video duration."])
        }

        // Limit processing duration to 20 seconds max to maintain high responsiveness
        let totalSec = min(rawDurationSec, 20.0)

        // 1. Build timestamp array at 15 FPS
        let interval = 1.0 / targetFPS
        var times: [CMTime] = []
        var t = 0.0
        while t < totalSec {
            times.append(CMTimeMakeWithSeconds(t, preferredTimescale: 600))
            t += interval
        }

        let totalFrames = max(times.count, 1)
        let tolerance = CMTimeMakeWithSeconds(interval / 2.0, preferredTimescale: 600)

        // 2. Setup AVAssetImageGenerator
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        // Extract first frame to verify dimensions
        guard let firstCG = try? generator.copyCGImage(at: times[0], actualTime: nil) else {
            throw NSError(domain: "VideoError", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not read video frames."])
        }

        let outputWidth = firstCG.width
        let outputHeight = firstCG.height

        // 3. Setup AVAssetWriter for streaming output
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac_annotated_\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputWidth,
            AVVideoHeightKey: outputHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(outputWidth * outputHeight * 2, 2_000_000),
            ],
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outputWidth,
            kCVPixelBufferHeightKey as String: outputHeight,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: adaptorAttrs
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // 4. Stream: Extract -> Detect -> Track -> Render -> Write (Single-Pass with Autoreleasepool)
        let tracker = MacDogTracker(iouThreshold: 0.25, maxLostFrames: 15, baseDetectionThreshold: 0.30)
        let frameDuration = CMTimeMakeWithSeconds(interval, preferredTimescale: 600)
        var presentationTime = CMTime.zero
        var bestConf: Float = 0.0

        for (i, time) in times.enumerated() {
            var frameToProcess: NSImage?
            autoreleasepool {
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    let size = NSSize(width: cgImage.width, height: cgImage.height)
                    frameToProcess = NSImage(cgImage: cgImage, size: size)
                }
            }

            guard let frame = frameToProcess else { continue }

            let rawResults = (try? await MacModelService.shared.detectDogs(in: frame)) ?? []
            let trackedResults = tracker.processFrame(detections: rawResults, frameIndex: i)
            let annotated = MacModelService.shared.renderAnnotatedImage(image: frame, detections: trackedResults)

            // Record raw detections
            for raw in rawResults {
                let existing = allVideoDetections[raw.label] ?? 0.0
                allVideoDetections[raw.label] = max(existing, Double(raw.confidence))
            }

            // Save best thumbnail for Breed Gallery
            if let top = rawResults.max(by: { $0.confidence < $1.confidence }), top.confidence > bestConf {
                bestConf = top.confidence
                bestAnnotatedFrame = annotated
                bestOriginalFrame = frame
                bestFrameResults = trackedResults
            } else if bestOriginalFrame == nil {
                bestOriginalFrame = frame
                bestAnnotatedFrame = annotated
            }

            // Write frame to video
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms
            }

            if let pb = annotated.pixelBuffer(width: outputWidth, height: outputHeight) {
                adaptor.append(pb, withPresentationTime: presentationTime)
            }
            presentationTime = CMTimeAdd(presentationTime, frameDuration)

            await MainActor.run {
                self.progress = Double(i + 1) / Double(totalFrames)
            }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? NSError(domain: "VideoError", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to write video."])
        }

        // 5. Consolidate tracks
        let minFrames = totalFrames > 5 ? 2 : 1
        let consolidatedSummaries = tracker.getConsolidatedSummaries(minFrames: minFrames, highConfidenceThreshold: 0.70)
        for summary in consolidatedSummaries {
            let existing = allVideoDetections[summary.breedName] ?? 0.0
            allVideoDetections[summary.breedName] = max(existing, summary.confidence)
        }
        self.trackedDogs = consolidatedSummaries

        return outputURL
    }

    // MARK: - Save to Breed Gallery (Only Confidence >= 0.70)
    func saveToBreedGallery(modelContext: ModelContext, allBreeds: [DogBreed]) async {
        guard !isSavingToGallery else { return }
        isSavingToGallery = true
        defer { isSavingToGallery = false }

        let source = sourceURL
        let annotated = annotatedVideoURL
        let origThumb = bestOriginalFrame
        let annThumb = bestAnnotatedFrame ?? bestOriginalFrame

        guard let origThumbData = origThumb?.jpegData else {
            saveMessage = "No thumbnail available to save."
            showingSaveAlert = true
            return
        }

        let annThumbData = annThumb?.jpegData

        // Heavy video data disk reading offloaded to background task
        let (rawVideoData, annotatedVideoData) = await Task.detached(priority: .userInitiated) { () -> (Data?, Data?) in
            let raw = try? Data(contentsOf: source)
            let ann = annotated.flatMap { try? Data(contentsOf: $0) }
            return (raw, ann)
        }.value

        guard let validRawVideo = rawVideoData else {
            saveMessage = "Failed to read original video data."
            showingSaveAlert = true
            return
        }

        var savedCount = 0
        var savedEntries: [(BreedImage, String)] = []

        for (breedName, highestConf) in allVideoDetections {
            guard highestConf >= 0.70 else { continue }

            let breed: DogBreed
            if let existing = allBreeds.first(where: { $0.name.caseInsensitiveCompare(breedName) == .orderedSame }) {
                breed = existing
            } else {
                let newBreed = DogBreed(name: breedName)
                modelContext.insert(newBreed)
                breed = newBreed
            }

            let entry = BreedImage(
                imageData: origThumbData,
                annotatedImageData: annThumbData,
                videoData: validRawVideo,
                annotatedVideoData: annotatedVideoData,
                isVideo: true,
                detectionDate: Date(),
                confidence: highestConf,
                breed: breed,
                isSyncedToCloud: false
            )
            modelContext.insert(entry)
            breed.images.append(entry)
            savedCount += 1
            savedEntries.append((entry, breed.name))
        }

        do {
            try modelContext.save()
            saveMessage = savedCount > 0
                ? "Saved video to Breed Gallery (\(savedCount) breed\(savedCount == 1 ? "" : "s"))."
                : "No detections with ≥ 70% confidence to save."
        } catch {
            saveMessage = "Failed to save to gallery: \(error.localizedDescription)"
        }
        showingSaveAlert = true

        // Background CloudKit sync
        for (item, bName) in savedEntries {
            Task {
                await MacCloudKitService.shared.uploadBreedImage(item, breedName: bName)
                try? modelContext.save()
            }
        }
    }

    // MARK: - Save to Photos Library
    func saveToPhotos() {
        guard let url = annotatedVideoURL ?? (try? FileManager.default.copyItemToTemp(url: sourceURL)) else { return }
        isSavingToPhotos = true

        PHPhotoLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSavingToPhotos = false

                guard status == .authorized || status == .limited else {
                    self.saveMessage = "Please grant Photo Library permission in macOS System Settings."
                    self.showingSaveAlert = true
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { success, error in
                    DispatchQueue.main.async {
                        self.saveMessage = success
                            ? "Video successfully saved to your Apple Photos."
                            : "Failed to save: \(error?.localizedDescription ?? "Unknown error")"
                        self.showingSaveAlert = true
                    }
                }
            }
        }
    }
}

private extension FileManager {
    func copyItemToTemp(url: URL) -> URL? {
        let temp = temporaryDirectory.appendingPathComponent("temp_\(UUID().uuidString).mp4")
        try? copyItem(at: url, to: temp)
        return temp
    }
}
