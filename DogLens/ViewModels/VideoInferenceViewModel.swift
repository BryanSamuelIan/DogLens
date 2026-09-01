import SwiftUI
import AVFoundation
import Photos
import SwiftData
import Combine

// MARK: - Video Inference ViewModel

@MainActor
final class VideoInferenceViewModel: ObservableObject {

    // MARK: - Published State
    @Published var isInferring   = false
    @Published var progress: Double = 0          // 0…1
    @Published var annotatedVideoURL: URL?
    @Published var errorMessage: String?
    @Published var showingSaveAlert  = false
    @Published var saveMessage       = ""
    @Published var isSavingToPhotos  = false
    @Published var trackedDogs: [TrackedDogSummary] = []

    // MARK: - Best Frame (for Breed Gallery)
    private(set) var bestAnnotatedFrame: UIImage?
    private(set) var bestOriginalFrame:  UIImage?
    private(set) var bestFrameResults:   [DetectionResult] = []

    // MARK: - Dependencies (injected from View)
    var modelContext: ModelContext?
    var breeds: [DogBreed] = []

    // MARK: - Config
    let sourceURL: URL
    private let targetFPS: Double = 15.0

    init(videoURL: URL) {
        self.sourceURL = videoURL
    }

    // MARK: - All Detected Breeds Across Video
    private(set) var allVideoDetections: [String: Double] = [:] // Breed Name -> Max Confidence

    // Returns true if ANY detected breed (with confidence >= 0.7)
    // has never been saved to the gallery before
    var isNewBreed: Bool {
        allVideoDetections.contains { name, conf in
            guard conf >= 0.7 else { return false }
            return breeds.first(where: { $0.name == name })?.imageCount == 0
        }
    }

    // MARK: - Run Inference

    func runInference() async {
        isInferring   = true
        progress      = 0
        annotatedVideoURL = nil
        bestAnnotatedFrame = nil
        bestOriginalFrame  = nil
        bestFrameResults   = []
        allVideoDetections = [:]
        trackedDogs        = []

        do {
            let url = try await processVideo()
            annotatedVideoURL = url
        } catch {
            errorMessage = "Inference failed: \(error.localizedDescription)"
        }

        isInferring = false
    }

    // MARK: - Private: Frame Extraction → Inference → Write

    private func processVideo() async throws -> URL {
        let asset    = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let totalSec = CMTimeGetSeconds(duration)

        guard totalSec > 0 else {
            throw NSError(domain: "VideoError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid video duration."])
        }

        // Build timestamp array at 15 fps
        let interval = 1.0 / targetFPS
        var times: [CMTime] = []
        var t = 0.0
        while t < totalSec {
            times.append(CMTimeMakeWithSeconds(t, preferredTimescale: 600))
            t += interval
        }

        let totalFrames = max(times.count, 1)
        let tolerance   = CMTimeMakeWithSeconds(interval / 2.0, preferredTimescale: 600)

        // Extract frames using AVAssetImageGenerator
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore   = tolerance
        generator.requestedTimeToleranceAfter    = tolerance
        // Use the video's natural size so bounding boxes are in the right coordinate space
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        var rawFrames: [(UIImage, CMTime)] = []
        for (i, time) in times.enumerated() {
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                rawFrames.append((UIImage(cgImage: cgImage), time))
            }
            await MainActor.run { self.progress = Double(i + 1) / Double(totalFrames) * 0.4 }
        }

        guard !rawFrames.isEmpty else {
            throw NSError(domain: "VideoError", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not extract any frames."])
        }

        // Initialize Multi-Object Tracker with calibrated parameters
        let tracker = DogTracker(iouThreshold: 0.25, maxLostFrames: 15, baseDetectionThreshold: 0.30)

        // Run CoreML inference at 15 fps and track dogs across frames
        var annotatedFrames: [(UIImage, CMTime)] = []
        var bestConf: Float = 0

        for (i, (frame, time)) in rawFrames.enumerated() {
            let rawResults = (try? await ModelService.shared.detectDogs(in: frame)) ?? []
            let trackedResults = tracker.processFrame(detections: rawResults, frameIndex: i)
            let annotated = Self.annotate(image: frame, results: trackedResults)
            annotatedFrames.append((annotated, time))

            // Track best frame based on raw detection quality
            if let top = rawResults.max(by: { $0.confidence < $1.confidence }), top.confidence > bestConf {
                bestConf             = top.confidence
                bestAnnotatedFrame   = annotated
                bestOriginalFrame    = frame
                bestFrameResults     = trackedResults
            }

            await MainActor.run { self.progress = 0.4 + Double(i + 1) / Double(rawFrames.count) * 0.4 }
        }

        // Collect consolidated detections for all unique dogs across the video
        // (Merges tracks of the same breed that disappeared and reappeared at different times)
        let minFrames = rawFrames.count > 5 ? 2 : 1
        let consolidatedSummaries = tracker.getConsolidatedSummaries(minFrames: minFrames, highConfidenceThreshold: 0.70)
        
        for summary in consolidatedSummaries {
            let existing = allVideoDetections[summary.breedName] ?? 0.0
            allVideoDetections[summary.breedName] = max(existing, summary.confidence)
        }
        self.trackedDogs = consolidatedSummaries

        // Write annotated video
        let outputURL = try await writeVideo(frames: annotatedFrames)
        await MainActor.run { self.progress = 1.0 }
        return outputURL
    }

    // MARK: - Annotation

    private static func annotate(image: UIImage, results: [DetectionResult]) -> UIImage {
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        image.draw(at: .zero)
        guard let ctx = UIGraphicsGetCurrentContext() else { return image }

        let lineWidth: CGFloat = max(3.0, size.width / 200.0)
        ctx.setLineWidth(lineWidth)
        ctx.setStrokeColor(UIColor.orange.cgColor)

        for result in results {
            ctx.stroke(result.boundingBox)

            let text: String
            if result.confidence > 0 {
                text = String(format: "%@ %.0f%%", result.label, result.confidence * 100)
            } else {
                text = result.label
            }
            let fontSize: CGFloat = max(14.0, size.width / 45.0)
            let attrs: [NSAttributedString.Key: Any] = [
                .font:            UIFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.orange,
            ]
            let sz   = text.size(withAttributes: attrs)
            let rect = CGRect(
                x: result.boundingBox.minX + lineWidth / 2,
                y: max(0, result.boundingBox.minY - sz.height - 4),
                width:  sz.width  + 8,
                height: sz.height + 4
            )
            // Background pill
            ctx.setFillColor(UIColor.orange.cgColor)
            let pill = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            ctx.addPath(pill.cgPath)
            ctx.fillPath()

            text.draw(at: CGPoint(x: rect.minX + 4, y: rect.minY + 2), withAttributes: attrs)
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    // MARK: - AVAssetWriter

    private func writeVideo(frames: [(UIImage, CMTime)]) async throws -> URL {
        guard let firstImg = frames.first?.0 else {
            throw NSError(domain: "VideoError", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "No frames to write."])
        }

        let w = Int(firstImg.size.width)
        let h = Int(firstImg.size.height)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("annotated_\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: w * h * 2,
            ],
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey  as String: w,
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
            // Spin-wait until ready (async-safe)
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000) // 5 ms
            }

            // toPixelBuffer must be called on the main thread (UIKit context)
            if let pb = image.toPixelBuffer(width: w, height: h) {
                adaptor.append(pb, withPresentationTime: presentationTime)
            }
            presentationTime = CMTimeAdd(presentationTime, frameDuration)
            await MainActor.run { self.progress = 0.8 + Double(i + 1) / Double(total) * 0.2 }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? NSError(domain: "VideoError", code: -4)
        }

        return outputURL
    }

    // MARK: - Save: Photos

    func saveToPhotos() {
        guard let url = annotatedVideoURL else { return }
        isSavingToPhotos = true

        PHPhotoLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSavingToPhotos = false

                guard status == .authorized || status == .limited else {
                    self.saveMessage = "Please grant Photo Library permission in Settings."
                    self.showingSaveAlert = true
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { success, error in
                    DispatchQueue.main.async {
                        self.saveMessage = success
                            ? "Annotated video saved to your Photos."
                            : "Failed to save: \(error?.localizedDescription ?? "Unknown error")"
                        self.showingSaveAlert = true
                    }
                }
            }
        }
    }

    // MARK: - Save: Breed Gallery (Video)

    func saveToBreedGallery() {
        guard let ctx = modelContext else {
            saveMessage = "Database context error."
            showingSaveAlert = true
            return
        }

        // Read raw video data
        guard let rawVideoData = try? Data(contentsOf: sourceURL) else {
            saveMessage = "Failed to read original video data."
            showingSaveAlert = true
            return
        }

        let annotatedVideoData = annotatedVideoURL.flatMap { try? Data(contentsOf: $0) }

        // Thumbnail images (best original frame & best annotated frame)
        guard let originalThumb = bestOriginalFrame,
              let origThumbData = originalThumb.jpegData(compressionQuality: 0.8) else {
            saveMessage = "No frame thumbnail available to save."
            showingSaveAlert = true
            return
        }
        let annotatedThumbData = (bestAnnotatedFrame ?? originalThumb).jpegData(compressionQuality: 0.8)

        var savedCount = 0
        for (breedName, highestConf) in allVideoDetections {
            guard highestConf >= 0.7 else { continue }
            if let breed = breeds.first(where: { $0.name == breedName }) {
                let entry = BreedImage(
                    imageData: origThumbData,
                    annotatedImageData: annotatedThumbData,
                    videoData: rawVideoData,
                    annotatedVideoData: annotatedVideoData,
                    isVideo: true,
                    confidence: highestConf
                )
                breed.images.append(entry)
                savedCount += 1

                // Backup to iCloud in background
                let savedEntry = entry
                let bName = breedName
                Task {
                    _ = try? await CloudKitService.shared.uploadBreedMedia(breedImage: savedEntry, breedName: bName)
                }
            }
        }

        do {
            try ctx.save()
            saveMessage = savedCount > 0
                ? "Saved video to Breed Gallery (\(savedCount) breed\(savedCount == 1 ? "" : "s"))."
                : "No matching breeds found in gallery."
        } catch {
            saveMessage = "Failed to save to gallery: \(error.localizedDescription)"
        }
        showingSaveAlert = true
    }
}
