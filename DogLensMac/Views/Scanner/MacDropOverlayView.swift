//
//  MacDropOverlayView.swift
//  DogLensMac
//

import SwiftUI

struct MacDropOverlayView: View {
    let isTargeted: Bool
    var scannerMode: ScannerMode = .photo

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, dash: [10]))
                .background(Color.orange.opacity(0.12))
                .padding(24)

            VStack(spacing: 16) {
                Image(systemName: scannerMode == .video ? "film.stack.fill" : "photo.on.rectangle.angled")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)

                Text(scannerMode == .video ? "Drop Video to Scan & Detect Dogs" : "Drop Image to Scan & Detect Dogs")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(scannerMode == .video ? "Supports MP4, MOV, and M4V files" : "Supports JPG, PNG, HEIC, and Video files")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
    }
}
