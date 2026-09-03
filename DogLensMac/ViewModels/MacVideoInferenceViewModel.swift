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
    @Published var trackedDogs: [TrackedDogSummary] = []

    // MARK: - Best Frame (for Breed Gallery Thumbnail)
    private(set) var bestAnnotatedFrame: NSImage?
    private(set) var bestOriginalFrame: NSImage?
    private(set) var bestFrameResults: [DetectionResult] = []

    // MARK: - Config
    let sourceURL: URL
    private let targetFPS: Double = 15.0

    // MARK: - All Detected Breeds Across Video (Breed Name -> Highest Confidence)
    private(set) var allVideoDetections: [String: Double] = [:]

    init(videoURL: URL) {
        self.sourceURL = videoURL
    }

    // Returns true if ANY detected breed (with confidence >= 0.7) has never been saved to gallery before
    func isNewBreed(allBreeds: [DogBreed]) -> Bool {
        allVideoDetections.contains { name, conf in
            guard conf >= 0.7 else { return false }
            if let match = allBreeds.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
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

    // MARK: - Private Pipeline: Frame Extraction → Inference → Tracking → Write
    private func processVideo() async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let totalSec = CMTimeGetSeconds(duration)

        guard totalSec > 0 else {
            throw NSError(domain: "VideoError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid video duration."])
        }

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

        // 2. Extract frames using AVAssetImageGenerator
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        var rawFrames: [(NSImage, CMTime)] = []
        for (i, time) in times.enumerated() {
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let size = NSSize(width: cgImage.width, height: cgImage.height)
                let nsImage = NSImage(cgImage: cgImage, size: size)
                rawFrames.append((nsImage, time))
            }
            await MainActor.run { self.progress = Double(i + 1) / Double(totalFrames) * 0.4 }
        }

        guard !rawFrames.isEmpty else {
            throw NSError(domain: "VideoError", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not extract any frames from video."])
        }

        // 3. Multi-Object Tracking & CoreML inference across extracted frames
        let tracker = MacDogTracker(iouThreshold: 0.25, maxLostFrames: 15, baseDetectionThreshold: 0.30)
        var annotatedFrames: [(NSImage, CMTime)] = []
        var bestConf: Float = 0.0

        for (i, (frame, time)) in rawFrames.enumerated() {
            let rawResults = (try? await MacModelService.shared.detectDogs(in: frame)) ?? []
            let trackedResults = tracker.processFrame(detections: rawResults, frameIndex: i)
            let annotated = MacModelService.shared.renderAnnotatedImage(image: frame, detections: trackedResults)
            annotatedFrames.append((annotated, time))

            // Track highest confidence frame for gallery thumbnail
            if let top = rawResults.max(by: { $0.confidence < $1.confidence }), top.confidence > bestConf {
                bestConf = top.confidence
                bestAnnotatedFrame = annotated
                bestOriginalFrame = frame
                bestFrameResults = trackedResults
            }

            await MainActor.run { self.progress = 0.4 + (Double(i + 1) / Double(rawFrames.count) * 0.4) }
        }

        // 4. Consolidate tracks across time
        let minFrames = rawFrames.count > 5 ? 2 : 1
        let consolidatedSummaries = tracker.getConsolidatedSummaries(minFrames: minFrames, highConfidenceThreshold: 0.70)
        
        for summary in consolidatedSummaries {
            let existing = allVideoDetections[summary.breedName] ?? 0.0
            allVideoDetections[summary.breedName] = max(existing, summary.confidence)
        }
        self.trackedDogs = consolidatedSummaries

        // Fallback for best frame if none had detections
        if bestOriginalFrame == nil, let first = rawFrames.first?.0 {
            bestOriginalFrame = first
            bestAnnotatedFrame = annotatedFrames.first?.0 ?? first
        }

        // 5. Write annotated video to MP4
        let outputURL = try await writeVideo(frames: annotatedFrames)
        await MainActor.run { self.progress = 1.0 }
        return outputURL
    }

    // MARK: - AVAssetWriter
    private func writeVideo(frames: [(NSImage, CMTime)]) async throws -> URL {
        guard let firstImg = frames.first?.0 else {
            throw NSError(domain: "VideoError", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "No frames to write."])
        }

        let w = Int(firstImg.size.width)
        let h = Int(firstImg.size.height)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac_annotated_\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(w * h * 2, 2_000_000),
            ],
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: adaptorAttrs
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTimeMakeWithSeconds(1.0 / targetFPS, preferredTimescale: 600)
        var presentationTime = CMTime.zero
        let total = frames.count

        for (i, (image, _)) in frames.enumerated() {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms
            }

            if let pb = image.pixelBuffer(width: w, height: h) {
                adaptor.append(pb, withPresentationTime: presentationTime)
            }
            presentationTime = CMTimeAdd(presentationTime, frameDuration)
            await MainActor.run { self.progress = 0.8 + (Double(i + 1) / Double(total) * 0.2) }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? NSError(domain: "VideoError", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to write video."])
        }

        return outputURL
    }

    // MARK: - Save to Breed Gallery (Only Confidence >= 0.70)
    func saveToBreedGallery(modelContext: ModelContext, allBreeds: [DogBreed]) {
        guard let rawVideoData = try? Data(contentsOf: sourceURL) else {
            saveMessage = "Failed to read original video data."
            showingSaveAlert = true
            return
        }

        let annotatedVideoData = annotatedVideoURL.flatMap { try? Data(contentsOf: $0) }

        guard let originalThumb = bestOriginalFrame,
              let origThumbData = originalThumb.jpegData else {
            saveMessage = "No thumbnail available to save."
            showingSaveAlert = true
            return
        }

        let annotatedThumbData = (bestAnnotatedFrame ?? originalThumb).jpegData

        var savedCount = 0
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
                annotatedImageData: annotatedThumbData,
                videoData: rawVideoData,
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

            // iCloud background sync
            let savedEntry = entry
            let bName = breed.name
            Task {
                await MacCloudKitService.shared.uploadBreedImage(savedEntry, breedName: bName)
                try? modelContext.save()
            }
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
