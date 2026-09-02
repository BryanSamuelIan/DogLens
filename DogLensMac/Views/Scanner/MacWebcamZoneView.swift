//
//  MacWebcamZoneView.swift
//  DogLensMac
//

import SwiftUI
import AVFoundation

struct MacWebcamZoneView: View {
    @Bindable var cameraManager: MacCameraManager
    let isProcessing: Bool
    let onCapture: () -> Void
    let onUploadFile: () -> Void

    var body: some View {
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
                    cameraStatusPlaceholder
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
                Button(action: onCapture) {
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

                Button(action: onUploadFile) {
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

    private var cameraStatusPlaceholder: some View {
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
}
