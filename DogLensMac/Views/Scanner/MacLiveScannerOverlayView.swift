//
//  MacLiveScannerOverlayView.swift
//  DogLensMac
//

import SwiftUI
import AVFoundation

struct MacLiveScannerOverlayView: View {
    @Bindable var cameraManager: MacCameraManager
    @ObservedObject var liveViewModel: MacLiveScannerViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if cameraManager.isRunning {
                    MacCameraPreviewView(session: cameraManager.session)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1.5)
                        )

                    // Bounding Box Overlay Layer
                    let viewSize = geometry.size
                    let imageSize = liveViewModel.frameSize

                    ForEach(Array(liveViewModel.detectionResults.enumerated()), id: \.offset) { index, result in
                        let rect = convertRect(box: result.boundingBox, imageSize: imageSize, viewSize: viewSize)
                        if rect.width > 0 && rect.height > 0 {
                            detectionBoxView(result: result, rect: rect)
                        }
                    }

                    // Live Status Floating Badge
                    VStack {
                        HStack {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)

                                Text("LIVE SCANNER")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)

                                if !liveViewModel.detectionResults.isEmpty {
                                    Text("• \(liveViewModel.detectionResults.count) detected")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.7), in: Capsule())
                            .padding(16)

                            Spacer()
                        }
                        Spacer()
                    }
                } else {
                    cameraStatusPlaceholder
                }
            }
        }
        .onAppear {
            cameraManager.onSampleBufferReceived = { sampleBuffer in
                liveViewModel.processSampleBuffer(sampleBuffer)
            }
        }
        .onDisappear {
            cameraManager.onSampleBufferReceived = nil
            liveViewModel.clearResults()
        }
    }

    // MARK: - Bounding Box & Label
    private func detectionBoxView(result: DetectionResult, rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            // Outline
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.orange, lineWidth: 3)
                .frame(width: rect.width, height: rect.height)

            // Label pill
            HStack(spacing: 4) {
                Text(result.label)
                    .font(.system(size: 11, weight: .bold))
                if result.confidence > 0 {
                    Text(String(format: "%.0f%%", result.confidence * 100))
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.orange)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .offset(y: -22)
        }
        .position(x: rect.midX, y: rect.midY)
    }

    // MARK: - Coordinate Conversion (Aspect Fill)
    private func convertRect(box: CGRect, imageSize: CGSize, viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return .zero
        }

        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let displayedWidth = imageSize.width * scale
        let displayedHeight = imageSize.height * scale
        let offsetX = (viewSize.width - displayedWidth) / 2.0
        let offsetY = (viewSize.height - displayedHeight) / 2.0

        return CGRect(
            x: box.origin.x * scale + offsetX,
            y: box.origin.y * scale + offsetY,
            width: box.size.width * scale,
            height: box.size.height * scale
        )
    }

    private var cameraStatusPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black.opacity(0.85))
            .overlay {
                VStack(spacing: 14) {
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.orange.opacity(0.85))
                    Text("Starting Live Detection Camera…")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
    }
}
