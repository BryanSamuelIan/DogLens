//
//  MacResultDisplayView.swift
//  DogLensMac
//

import SwiftUI
import AppKit

struct MacResultDisplayView: View {
    @Binding var showOriginal: Bool
    let originalImage: NSImage?
    let annotatedImage: NSImage?
    let onSaveToFile: () -> Void
    let onScanAnother: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Picker("", selection: $showOriginal) {
                    Text("Detection").tag(false)
                    Text("Original").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
                .tint(.orange)

                Spacer()

                Button(action: onSaveToFile) {
                    Label("Save to File…", systemImage: "arrow.down.doc.fill")
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button(action: onScanAnother) {
                    Label("Scan Another", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }

            ZStack {
                Color.black.opacity(0.04)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                let displayImg = showOriginal ? originalImage : (annotatedImage ?? originalImage)
                if let img = displayImg {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                }
            }
        }
    }
}
