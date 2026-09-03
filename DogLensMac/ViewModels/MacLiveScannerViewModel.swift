//
//  MacLiveScannerViewModel.swift
//  DogLensMac
//

import SwiftUI
import AppKit
import AVFoundation
import CoreImage
import Combine

@MainActor
final class MacLiveScannerViewModel: ObservableObject {
    @Published var detectionResults: [DetectionResult] = []
    @Published var isDetecting: Bool = false
    @Published var frameSize: CGSize = CGSize(width: 1280, height: 720)

    private var isProcessing = false
    private var lastInferenceTime = Date.distantPast
    private let inferenceInterval: TimeInterval = 1.0 / 15.0 // 15 FPS throttle
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastInferenceTime) >= inferenceInterval else { return }
        guard !isProcessing else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessing = true
        lastInferenceTime = now

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let currentSize = CGSize(width: width, height: height)

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            isProcessing = false
            return
        }

        let nsSize = NSSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(cgImage: cgImage, size: nsSize)

        Task { @MainActor in
            defer { self.isProcessing = false }
            do {
                let results = try await MacModelService.shared.detectDogs(in: image)
                self.detectionResults = results
                self.frameSize = currentSize
                self.isDetecting = true
            } catch {
                // Silently handle transient inference skips in live loop
            }
        }
    }

    func clearResults() {
        self.detectionResults = []
        self.isDetecting = false
    }
}
