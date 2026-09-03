//
//  MacVideoPreviewView.swift
//  DogLensMac
//

import SwiftUI
import AVKit

struct MacVideoPreviewView: View {
    @ObservedObject var vm: MacVideoInferenceViewModel
    let onScanAnother: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 20) {
            // Video Player
            if let player = player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Loading Video…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Controls / Progress Bar
            if vm.isInferring {
                VStack(spacing: 12) {
                    ProgressView(value: vm.progress)
                        .progressViewStyle(.linear)
                        .tint(.orange)
                        .frame(maxWidth: 400)

                    Text("Running CoreML at 15 FPS (\(Int(vm.progress * 100))%)")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Detecting and tracking dog breeds across video frames…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 16) {
                    Button {
                        Task {
                            await vm.runInference()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "brain")
                                .font(.title3)
                            Text("Detect Dogs")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .frame(minWidth: 180, minHeight: 40)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        player?.pause()
                        onScanAnother()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Record / Choose Again")
                        }
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let p = AVPlayer(url: vm.sourceURL)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
    }
}
