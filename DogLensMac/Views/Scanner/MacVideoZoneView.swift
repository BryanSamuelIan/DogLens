//
//  MacVideoZoneView.swift
//  DogLensMac
//

import SwiftUI
import AVFoundation

struct MacVideoZoneView: View {
    let inputSource: MediaInputSource
    @Bindable var cameraManager: MacCameraManager
    let isDropTargeted: Bool
    let isInferring: Bool
    let inferenceProgress: Double
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onUploadFile: () -> Void
    let onSwitchToCamera: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                if inputSource == .camera {
                    cameraArea
                } else {
                    dropzoneArea
                }

                if isInferring {
                    inferringOverlay
                }
            }

            // Bottom action buttons
            if !isInferring {
                actionButtons
            }
        }
    }

    // MARK: - Camera Area
    private var cameraArea: some View {
        ZStack {
            if cameraManager.isRunning {
                MacCameraPreviewView(session: cameraManager.session)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(cameraManager.isRecording ? Color.red.opacity(0.6) : Color.orange.opacity(0.2), lineWidth: 2)
                    )
            } else {
                cameraStatusPlaceholder
            }

            // Recording Indicator Overlay
            if cameraManager.isRecording {
                VStack {
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                                .opacity(1.0)

                            Text(formatDuration(cameraManager.recordingDuration))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(16)

                        Spacer()
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Dropzone Area
    private var dropzoneArea: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(isDropTargeted ? Color.orange.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.5))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? Color.orange : Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.5, dash: [8, 5])
                    )
            }
            .overlay {
                VStack(spacing: 16) {
                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 46))
                        .foregroundColor(isDropTargeted ? .orange : .secondary.opacity(0.8))
                        .scaleEffect(isDropTargeted ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3), value: isDropTargeted)

                    VStack(spacing: 6) {
                        Text(isDropTargeted ? "Drop Video to Scan" : "Drag & Drop Dog Video")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        Text("Supports MP4, MOV, and M4V video formats")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button(action: onUploadFile) {
                            Label("Select Video…", systemImage: "plus.rectangle.on.folder.fill")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.regular)

                        Button(action: onSwitchToCamera) {
                            Label("Record with Webcam", systemImage: "video.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                    .padding(.top, 4)
                }
                .padding(32)
            }
    }

    // MARK: - Inferring Overlay
    private var inferringOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
            VStack(spacing: 18) {
                ProgressView(value: inferenceProgress)
                    .progressViewStyle(.linear)
                    .tint(.orange)
                    .frame(width: 280)

                VStack(spacing: 4) {
                    Text("Running CoreML at 15 FPS (\(Int(inferenceProgress * 100))%)")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("Detecting and tracking dog breeds across video frames…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 14) {
            if inputSource == .camera {
                if cameraManager.isRecording {
                    Button(action: onStopRecording) {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                            Text("Stop Recording")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .frame(minWidth: 180, minHeight: 40)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onStartRecording) {
                        HStack(spacing: 8) {
                            Image(systemName: "record.circle.fill")
                                .foregroundColor(.red)
                            Text("Record Video")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .frame(minWidth: 180, minHeight: 40)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!cameraManager.isRunning)
                }

                Button(action: onUploadFile) {
                    HStack(spacing: 8) {
                        Image(systemName: "film")
                        Text("Upload Video…")
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

    private var cameraStatusPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black.opacity(0.85))
            .overlay {
                VStack(spacing: 14) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.orange.opacity(0.85))
                    Text("Starting Camera…")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, tenths)
    }
}
