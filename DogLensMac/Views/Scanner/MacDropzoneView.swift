//
//  MacDropzoneView.swift
//  DogLensMac
//

import SwiftUI

struct MacDropzoneView: View {
    let isDropTargeted: Bool
    let isProcessing: Bool
    let onUploadFile: () -> Void
    let onSwitchToWebcam: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isDropTargeted ? Color.orange : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(isDropTargeted ? Color.orange.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.4))
                )

            VStack(spacing: 22) {
                // DogLens Viewfinder Icon
                Image(systemName: "viewfinder.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.orange, .blue.opacity(0.8))

                VStack(spacing: 8) {
                    Text("Identify Dogs with DogLens")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Drag & drop photos or select from your Mac to detect 52 dog breeds")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

                HStack(spacing: 14) {
                    Button(action: onUploadFile) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Upload Photo")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: onSwitchToWebcam) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                            Text("Webcam Snapshot")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            .padding(40)

            if isProcessing {
                ZStack {
                    Color.black.opacity(0.5)
                    ProgressView("Analyzing image with CoreML…")
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .foregroundColor(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }
}
